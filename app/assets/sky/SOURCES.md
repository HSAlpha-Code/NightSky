# Sky View Bundled Data Sources & Licenses

All catalogs and imagery shipped inside `app/assets/sky/` are used offline at runtime.

| File | Contents | Upstream Source | License |
|---|---|---|---|
| `mellinger_galactic.webp` | 3600×1800 Galactic `CAR` all-sky Milky Way panorama | Axel Mellinger (2009, *PASP* 121, 1180) via NASA SkyView (`Mellinger Red/Green/Blue`) | © Axel Mellinger — **verify commercial/redistribution license terms with Axel Mellinger before release** |
| `stars.bin` | 8874 stars to V ≤ 6.5 (J2000 RA/Dec, Vmag, B−V, HIP) | `ofrohn/d3-celestial` (`data/stars.8.json`, derived from ESA Hipparcos `I/239` & XHIP) | BSD-3-Clause (Copyright © 2015 Olaf Frohn) |
| `sky_catalog.json` (`named_stars`) | 574 proper star names & Bayer designations | IAU Working Group on Star Names (`IAU-WGSN.csv` / `IAU-CSN.txt`) + `ofrohn/d3-celestial` (`starnames.json`) | IAU Public / BSD-3-Clause |
| `sky_catalog.json` (`constellations`) | 88 IAU constellation stick figures & names | `ofrohn/d3-celestial` (`constellations.lines.json`, `constellations.json`) | BSD-3-Clause (Copyright © 2015 Olaf Frohn) |
| `sky_catalog.json` (`dso`) | 145 Messier, curated & bright deep-sky objects | OpenNGC (`NGC.csv` + `addendum.csv`, Mattia Verga) | CC BY-SA 4.0 |
