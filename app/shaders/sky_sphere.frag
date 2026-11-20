#version 460 core

#include <flutter/runtime_effect.glsl>

// Sequential scalar uniforms avoid vec3 std140 alignment differences across GPU backends.
uniform float uWidth;
uniform float uHeight;
uniform float uTanHalfFov;

// Camera basis expressed in Galactic coordinates (unit vectors).
uniform float uFwdX;
uniform float uFwdY;
uniform float uFwdZ;
uniform float uRightX;
uniform float uRightY;
uniform float uRightZ;
uniform float uUpX;
uniform float uUpY;
uniform float uUpZ;

// Local zenith (ENU +Z) expressed in Galactic coordinates, for horizon shading.
uniform float uZenithX;
uniform float uZenithY;
uniform float uZenithZ;

// Sun altitude in degrees (-90..+90), exposure multiplier, red night-vision flag,
// square edge dimension (in texels) of each hemisphere texture (e.g. 3200 or 4096),
// and horizon/twilight ground-shading flag (1.0 = shade sky & dim below horizon, 0.0 = uniform).
uniform float uSunAltDeg;
uniform float uExposure;
uniform float uNightVision;
uniform float uHemiSize;
uniform float uHorizonShading;
// Optional installed tile. Columns=0 selects the bundled dual-hemisphere sky.
uniform float uTileX;
uniform float uTileY;
uniform float uTileColumns;
uniform float uTileRows;
uniform float uTileSize;
uniform float uTileGutter;

// Dual 4096x4096 hemispheres forming an 8192x4096 8K Galactic CAR panorama:
// uPanoEast covers global u in [0, 0.5] (l in [+180, 0]);
// uPanoWest covers global u in [0.5, 1] (l in [0, -180]).
uniform sampler2D uPanoEast;
uniform sampler2D uPanoWest;

out vec4 fragColor;

const float PI = 3.141592653589793;
const float TWO_PI = 6.283185307179586;

// Fetch a single texel (gx in [0..2*S-1] wrapped, gy in [0..S-1] clamped) across both hemispheres.
vec3 fetchGlobalTexel(float gxRaw, float gyRaw, float S) {
  float totalW = 2.0 * S;
  float gx = gxRaw - totalW * floor(gxRaw / totalW);
  float gy = clamp(gyRaw, 0.0, S - 1.0);
  float v = (gy + 0.5) / S;
  if (gx < S) {
    return texture(uPanoEast, vec2((gx + 0.5) / S, v)).rgb;
  } else {
    return texture(uPanoWest, vec2((gx - S + 0.5) / S, v)).rgb;
  }
}

// Explicit sub-texel bilinear interpolation across both hemispheres. Flutter's RuntimeEffect
// binds sampler2D with nearest-neighbor filtering, so doing bilinear in GLSL eliminates all
// blocky texel stair-stepping and seamlessly bridges l = 0 deg and l = +/-180 deg.
vec3 samplePanoramaBilinear(float u, float v, float S) {
  float px = u * (2.0 * S) - 0.5;
  float py = clamp(v * S - 0.5, 0.0, S - 1.0001);
  float x0 = floor(px);
  float y0 = floor(py);
  float fx = px - x0;
  float fy = py - y0;

  vec3 c00 = fetchGlobalTexel(x0, y0, S);
  vec3 c10 = fetchGlobalTexel(x0 + 1.0, y0, S);
  vec3 c01 = fetchGlobalTexel(x0, y0 + 1.0, S);
  vec3 c11 = fetchGlobalTexel(x0 + 1.0, y0 + 1.0, S);

  return mix(mix(c00, c10, fx), mix(c01, c11, fx), fy);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float nx = (frag.x / uWidth) * 2.0 - 1.0;
  float ny = (0.5 - frag.y / uHeight) * 2.0 * (uHeight / uWidth);

  vec3 fwd = vec3(uFwdX, uFwdY, uFwdZ);
  vec3 rightV = vec3(uRightX, uRightY, uRightZ);
  vec3 upV = vec3(uUpX, uUpY, uUpZ);
  vec3 zenith = vec3(uZenithX, uZenithY, uZenithZ);

  vec3 dir = normalize(fwd + (nx * uTanHalfFov) * rightV + (ny * uTanHalfFov) * upV);

  float l = atan(dir.y, dir.x);
  float b = asin(clamp(dir.z, -1.0, 1.0));
  float u = fract(0.5 - l / TWO_PI);
  float sourceHeight = uTileColumns > 0.0 ? uTileRows * uTileSize : uHemiSize;
  float poleInset = 0.5 / max(sourceHeight, 1.0);
  float v = clamp(0.5 - b / PI, poleInset, 1.0 - poleInset);

  vec3 sky;
  if (uTileColumns > 0.0) {
    vec2 globalTile = vec2(u * uTileColumns, v * uTileRows);
    vec2 local = globalTile - vec2(uTileX, uTileY);
    if (local.x < 0.0 || local.x >= 1.0 || local.y < 0.0 || local.y >= 1.0) {
      fragColor = vec4(0.0);
      return;
    }
    float edge = uTileSize + 2.0 * uTileGutter;
    vec2 px = local * uTileSize + uTileGutter - 0.5;
    vec2 base = floor(px);
    vec2 f = fract(px);
    vec3 a = texture(uPanoEast, (base + vec2(0.5, 0.5)) / edge).rgb;
    vec3 b = texture(uPanoEast, (base + vec2(1.5, 0.5)) / edge).rgb;
    vec3 c = texture(uPanoEast, (base + vec2(0.5, 1.5)) / edge).rgb;
    vec3 d = texture(uPanoEast, (base + vec2(1.5, 1.5)) / edge).rgb;
    sky = mix(mix(a, b, f.x), mix(c, d, f.x), f.y) * uExposure;
  } else {
    sky = samplePanoramaBilinear(u, v, uHemiSize) * uExposure;
  }
  sky = pow(max(sky, vec3(0.0)), vec3(1.06));

  float sinAlt = dot(dir, zenith);

  if (uHorizonShading > 0.5) {
    float twilight = smoothstep(-15.0, 6.0, uSunAltDeg);
    float aboveMask = smoothstep(-0.08, 0.02, sinAlt);
    if (twilight > 0.001 && aboveMask > 0.001) {
      float horizonGlow = pow(1.0 - clamp(sinAlt, 0.0, 1.0), 2.4);
      vec3 zenithTint = vec3(0.05, 0.13, 0.32);
      vec3 horizonTint = vec3(0.20, 0.24, 0.42);
      vec3 scatter = mix(zenithTint, horizonTint, horizonGlow) * twilight * 0.65;
      sky = mix(sky, sky * (1.0 - 0.55 * twilight) + scatter, 0.85 * aboveMask);
    }

    if (sinAlt < 0.0) {
      float groundMix = smoothstep(0.0, -0.08, sinAlt);
      vec3 groundCol = vec3(0.018, 0.024, 0.036) + sky * 0.18;
      sky = mix(sky, groundCol, groundMix * 0.88);
    }
  }

  if (uNightVision > 0.5) {
    float lum = dot(sky, vec3(0.299, 0.587, 0.114));
    sky = vec3(lum * 1.15, lum * 0.07, lum * 0.04);
  }

  fragColor = vec4(clamp(sky, 0.0, 1.0), 1.0);
}
