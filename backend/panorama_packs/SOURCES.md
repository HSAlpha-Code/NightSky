# NASA Deep Star Maps 2020 texture packs

Source: https://svs.gsfc.nasa.gov/4851/ (Ernie Wright, released 9 September 2020).
Use the corrected Galactic maps published 4 January 2021, centered on longitude
zero with longitude increasing to the left.

Credit: NASA/Goddard Space Flight Center Scientific Visualization Studio.
Gaia DR2: ESA/Gaia/DPAC.

NASA SVS declares its content public domain unless otherwise noted:
https://svs.gsfc.nasa.gov/help/. This item states no separate copyright restriction
for the star map. Reuse and redistribution follow that policy and NASA's media
usage guidelines: https://www.nasa.gov/nasa-brand-center/images-and-media/.
These notices grant no NASA trademark rights and imply no NASA endorsement.

8K: `starmap_2020_8k_gal.exr`, native 8192 x 4096, split into two hemispheres.
16K: `starmap_2020_16k_gal.exr`, native 16384 x 8192.
32K: `starmap_2020_32k_gal.exr`, native 32768 x 16384.

The 16K/32K manifests record the exact original EXR SHA-256 and the size and
SHA-256 of each 2048-pixel tile. Tiles include a one-pixel sampling gutter.
All textures use **lossless WebP**, with an exact decoded RGB pixel comparison
during generation. Nothing is spatially downsampled or upscaled in preparation.
Lossless compression preserves the converted display pixels, not the full HDR
representation: linear half-float RGB is converted to 8-bit sRGB, with negative
values clamped to zero and highlights above display white clipped.

Generate with `python app/tool/sky_data/prepare_nasa.py` and
`python app/tool/sky_data/prepare_nasa.py --packs`. Deploy this directory with the
backend before offering the optional packs. The original EXRs are cached outside
the repository; they are not included in the app. The app ships only the 8K map.
Other catalogs, constellation figures and imagery retain their separate terms.

Online NASA cutouts use a perspective reprojection of the 8K map and lossless PNG encoding.

Vercel serves the optional packs from its static CDN after collectstatic, with a rewrite
from the versioned API paths. The 16K/32K files are excluded from the Python function bundle.
Self-hosted Django serves the same paths directly from panorama_packs.

Lossless payload sizes (excluding small manifests): included 8K 34,837,846 bytes
(33.2 MiB); optional 16K 107,421,670 bytes (102.4 MiB); optional 32K 366,526,918
bytes (349.5 MiB). The app shows download sizes before installation.
