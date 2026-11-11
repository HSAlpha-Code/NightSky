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

// Sun altitude in degrees (-90..+90) for gentle twilight/daylight sky tint,
// exposure multiplier, and red night-vision flag (0 = normal, 1 = red).
uniform float uSunAltDeg;
uniform float uExposure;
uniform float uNightVision;

uniform sampler2D uPanorama;

out vec4 fragColor;

const float PI = 3.141592653589793;
const float TWO_PI = 6.283185307179586;

void main() {
  vec2 frag = FlutterFragCoord().xy;
  // Normalised screen coordinates: x in [-1, 1] across width, y in [-aspect, +aspect] (up positive).
  float nx = (frag.x / uWidth) * 2.0 - 1.0;
  float ny = (0.5 - frag.y / uHeight) * 2.0 * (uHeight / uWidth);

  vec3 fwd = vec3(uFwdX, uFwdY, uFwdZ);
  vec3 rightV = vec3(uRightX, uRightY, uRightZ);
  vec3 upV = vec3(uUpX, uUpY, uUpZ);
  vec3 zenith = vec3(uZenithX, uZenithY, uZenithZ);

  vec3 dir = normalize(fwd + (nx * uTanHalfFov) * rightV + (ny * uTanHalfFov) * upV);

  // Galactic longitude l in [-pi, +pi], latitude b in [-pi/2, +pi/2].
  // Mellinger CAR convention: centre (0.5, 0.5) = (l=0, b=0), l increases left, b=+90 at top.
  float l = atan(dir.y, dir.x);
  float b = asin(clamp(dir.z, -1.0, 1.0));
  float u = fract(0.5 - l / TWO_PI);
  float v = clamp(0.5 - b / PI, 0.0005, 0.9995);

  vec3 sky = texture(uPanorama, vec2(u, v)).rgb * uExposure;
  // Gentle contrast curve so dark sky stays velvety black while the Milky Way core pops.
  sky = pow(max(sky, vec3(0.0)), vec3(1.08));

  // Altitude sine relative to local horizon: > 0 above horizon, < 0 below ground.
  float sinAlt = dot(dir, zenith);

  // Atmospheric twilight / daylight scattering when the Sun is above -15 deg.
  float twilight = smoothstep(-15.0, 6.0, uSunAltDeg);
  if (twilight > 0.001 && sinAlt > -0.05) {
    float horizonGlow = pow(1.0 - clamp(sinAlt, 0.0, 1.0), 2.4);
    vec3 zenithTint = vec3(0.05, 0.13, 0.32);
    vec3 horizonTint = vec3(0.20, 0.24, 0.42);
    vec3 scatter = mix(zenithTint, horizonTint, horizonGlow) * twilight * 0.65;
    sky = mix(sky, sky * (1.0 - 0.55 * twilight) + scatter, 0.85);
  }

  // Subtle translucent earth shading below the mathematical horizon so users still get spatial
  // continuity while clearly seeing where the ground begins.
  if (sinAlt < 0.0) {
    float groundMix = smoothstep(0.0, -0.08, sinAlt);
    vec3 groundCol = vec3(0.018, 0.024, 0.036) + sky * 0.18;
    sky = mix(sky, groundCol, groundMix * 0.88);
  }

  if (uNightVision > 0.5) {
    float lum = dot(sky, vec3(0.299, 0.587, 0.114));
    sky = vec3(lum * 1.15, lum * 0.07, lum * 0.04);
  }

  fragColor = vec4(clamp(sky, 0.0, 1.0), 1.0);
}
