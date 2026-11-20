# Sky View Bundled Data Sources & Licenses

All catalogs and imagery shipped inside `app/assets/sky/` are used offline at runtime.

| File | Contents | Upstream Source | License |
|---|---|---|---|
| `nasa_2020_east.webp`, `nasa_2020_west.webp` | 8192 x 4096 (8K, dual 4096 x 4096) Galactic plate carree star map | [NASA Deep Star Maps 2020, SVS #4851](https://svs.gsfc.nasa.gov/4851/), Ernie Wright; corrected Galactic version (4 January 2021) | Public domain per [NASA SVS policy](https://svs.gsfc.nasa.gov/help/); NASA media usage guidelines apply. Credit: NASA/Goddard Space Flight Center Scientific Visualization Studio. Gaia DR2: ESA/Gaia/DPAC. |
| `stars.bin` | 8874 stars to V ≤ 6.5 (J2000 RA/Dec, Vmag, B−V, HIP) | `ofrohn/d3-celestial` (`data/stars.8.json`, derived from ESA Hipparcos `I/239` & XHIP) | BSD-3-Clause (Copyright © 2015 Olaf Frohn) |
| `sky_catalog.json` (`named_stars`) | 574 proper star names & Bayer designations | IAU Working Group on Star Names (`IAU-WGSN.csv` / `IAU-CSN.txt`) + `ofrohn/d3-celestial` (`starnames.json`) | IAU Public / BSD-3-Clause |
| `sky_catalog.json` (`constellations`) | 88 IAU constellation stick figures & names | `ofrohn/d3-celestial` (`constellations.lines.json`, `constellations.json`) | BSD-3-Clause (Copyright © 2015 Olaf Frohn) |
| `sky_catalog.json` (`dso`) | 145 Messier, curated & bright deep-sky objects | OpenNGC (`NGC.csv` + `addendum.csv`, Mattia Verga) | CC BY-SA 4.0 |

The bundled map is derived from `starmap_2020_8k_gal.exr` (corrected 4 January 2021),
SHA-256 `d70924422d3e0159764b16a19658784befcf73b97e06e5c16614860c1514bb58`.
Linear HDR light is converted to sRGB and clipped at white, then encoded as lossless WebP (pixel-exact after the documented sRGB8 conversion).
Native 16K/32K equivalents are prepared as optional offline tile packs under
`backend/panorama_packs/`; each manifest records the exact NASA source URL, original hash,
tile sizes, checksums, credit and reuse policy. The base app bundles only 8K.
NASA SVS declares its content public domain unless noted otherwise; no separate
copyright restriction is stated for this map. This does not grant NASA trademark rights
or imply endorsement. Other catalogs and imagery retain the terms in their own notices.
