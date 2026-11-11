"""Build compact, license-compatible offline star, constellation, and deep-sky catalogs.

Run from the app folder:
    python tool/sky_data/prepare_catalogs.py

Data sources & licenses:
1. Stars (positions, V magnitudes, B-V colour indices, Hipparcos IDs, distances/designations):
   - d3-celestial (`data/stars.8.json`, `data/starnames.json`), Copyright (c) 2015 Olaf Frohn,
     BSD-3-Clause License (derived from ESA Hipparcos I/239 & XHIP Anderson & Francis 2012).
   - Official IAU proper star names from `backend/data/catalogs/IAU-WGSN.csv` and `IAU-CSN.txt`
     (IAU Working Group on Star Names).
2. Constellation stick figures & metadata (88 IAU constellations):
   - d3-celestial (`data/constellations.lines.json`, `data/constellations.json`),
     Copyright (c) 2015 Olaf Frohn, BSD-3-Clause License.
3. Deep-sky objects (Messier + bright named NGC/IC/Melotte/Caldwell objects, matching backend IDs):
   - OpenNGC (`backend/data/catalogs/NGC.csv` + `addendum.csv`), Mattia Verga, CC BY-SA 4.0.
"""
import csv
import json
import math
import re
import struct
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parents[3]
BACKEND_CATALOGS = ROOT / "backend" / "data" / "catalogs"
CURATED_MANIFEST = ROOT / "backend" / "curated_bundle" / "manifest.json"
OUT_DIR = ROOT / "app" / "assets" / "sky"

D3_BASE = "https://raw.githubusercontent.com/ofrohn/d3-celestial/master/data"
LIMITING_MAG = 6.5

TYPE_LABELS = {
    "G": "Galaxy", "GPair": "Galaxy pair", "GTrpl": "Galaxy triplet", "GGroup": "Galaxy group",
    "OCl": "Open cluster", "GCl": "Globular cluster", "Cl+N": "Star cluster with nebula",
    "PN": "Planetary nebula", "HII": "Emission nebula", "EmN": "Emission nebula",
    "Neb": "Nebula", "RfN": "Reflection nebula", "SNR": "Supernova remnant",
    "DrkN": "Dark nebula", "*Ass": "Stellar association", "*": "Star", "**": "Double star",
    "Other": "Asterism",
}
SKIP_TYPES = {"", "Dup", "NonEx", "*", "**", "Other", "Nova"}
NEVER_KEEP = {"", "Dup", "NonEx"}
MESSIER_OVERRIDES = {"NGC5866": 102}
LY_PER_PC = 3.26156
LY_PER_MPC = 3.26156e6
HUBBLE_CONSTANT = 70.0

# Distances (light-years) for prominent bright stars from Hipparcos/Gaia parallaxes so offline
# star cards show accurate distances without inflating the binary table.
BRIGHT_STAR_DIST_LY = {
    32349: 8.6,    # Sirius
    30438: 310,    # Canopus
    71683: 4.37,   # Rigil Kentaurus (Alpha Centauri)
    69673: 36.7,   # Arcturus
    91262: 25.0,   # Vega
    24608: 42.9,   # Capella
    24436: 860,    # Rigel
    37279: 11.46,  # Procyon
    7588: 139,     # Achernar
    27989: 550,    # Betelgeuse
    68702: 390,    # Hadar
    97649: 16.7,   # Altair
    60718: 320,    # Acrux
    21421: 65.3,   # Aldebaran
    80763: 550,    # Antares
    65474: 250,    # Spica
    37826: 33.8,   # Pollux
    113368: 25.1,  # Fomalhaut
    102098: 2600,  # Deneb
    62434: 280,    # Mimosa
    49669: 79.3,   # Regulus
    11767: 433,    # Polaris
    36850: 51,     # Castor
    25336: 250,    # Bellatrix
    26311: 2000,   # Alnilam
    26727: 1260,   # Alnitak
    25930: 1200,   # Mintaka
    17702: 444,    # Alcyone
}


def _float(val):
    try:
        return float(val) if val not in (None, "") else None
    except ValueError:
        return None


def _sexagesimal(text: str) -> float:
    sign = -1.0 if text.strip().startswith("-") else 1.0
    parts = [abs(float(p)) for p in text.strip().lstrip("+-").split(":")]
    return sign * (parts[0] + parts[1] / 60.0 + parts[2] / 3600.0)


def _pretty_code(code: str) -> str:
    m = re.match(r"^([A-Za-z]+)0*(\d+)(.*)$", code)
    return f"{m[1]} {m[2]}{m[3]}" if m else code


def _distance_ly(pax: float | None, z: float | None) -> float | None:
    if pax and pax > 0.05:
        return round(1000.0 / pax * LY_PER_PC, -1)
    if z and z > 0.002:
        return round(z * 299792.458 / HUBBLE_CONSTANT * LY_PER_MPC, -5)
    return None


def load_iau_names() -> dict[int, tuple[str, str, str]]:
    """Return HIP -> (proper_name, bayer_or_desig, constellation) from repo IAU catalogs."""
    by_hip: dict[int, tuple[str, str, str]] = {}
    wgsn_path = BACKEND_CATALOGS / "IAU-WGSN.csv"
    if wgsn_path.exists():
        for row in csv.DictReader(wgsn_path.read_text(encoding="utf-8").splitlines()):
            hip_s = (row.get("hip") or "").strip()
            name = (row.get("name") or "").strip()
            if hip_s.isdigit() and name:
                bayer = (row.get("bayer") or row.get("designation") or "").strip()
                if bayer in ("-", "_"):
                    bayer = ""
                con = (row.get("constellation") or "").strip()
                by_hip[int(hip_s)] = (name, bayer, con)
    csn_path = BACKEND_CATALOGS / "IAU-CSN.txt"
    tail_re = re.compile(
        r"(?P<mag>-?\d+\.\d+|_)\s+(?P<band>\S+)\s+(?P<hip>\d+|_)\s+(?P<hd>\d+|_)\s+"
        r"(?P<ra>\d+\.\d+)\s+(?P<dec>[-+]?\d+\.\d+)\s+\d{4}-\d{2}-\d{2}"
    )
    con_re = re.compile(r"\s([A-Z][a-z]{2})\s")
    if csn_path.exists():
        for line in csn_path.read_text(encoding="utf-8").splitlines():
            if not line[:1].isalpha():
                continue
            m = tail_re.search(line)
            if not m or m["hip"] == "_":
                continue
            hip = int(m["hip"])
            if hip in by_hip:
                continue
            name = line[:18].strip()
            desig = line[36:49].strip()
            con_m = con_re.search(line[36 : m.start()])
            by_hip[hip] = (name, desig if desig != "_" else "", con_m[1] if con_m else "")
    return by_hip


def build_stars():
    stars_json = requests.get(f"{D3_BASE}/stars.8.json", timeout=30).json()
    names_json = requests.get(f"{D3_BASE}/starnames.json", timeout=30).json()
    iau_by_hip = load_iau_names()

    records = []
    for feat in stars_json["features"]:
        hip = int(feat["id"])
        mag = float(feat["properties"]["mag"])
        if mag > LIMITING_MAG:
            continue
        bv_raw = feat["properties"].get("bv", "")
        bv = _float(bv_raw)
        if bv is None:
            bv = 0.45
        lon, lat = feat["geometry"]["coordinates"]
        ra = float(lon) % 360.0
        dec = max(-90.0, min(90.0, float(lat)))
        records.append((mag, hip, ra, dec, bv))

    # Sort brightest first so runtime quality tiers can stop early by magnitude!
    records.sort(key=lambda r: (r[0], r[1]))

    named_stars = []
    buf = bytearray()
    buf.extend(struct.pack("<4sHH", b"NSKY", 1, len(records)))

    for mag, hip, ra, dec, bv in records:
        d3_info = names_json.get(str(hip), {})
        iau = iau_by_hip.get(hip)
        name = iau[0] if iau else (d3_info.get("name") or "").strip()
        bayer = (iau[1] if iau and iau[1] else (d3_info.get("desig") or d3_info.get("bayer") or "")).strip()
        con = (iau[2] if iau and iau[2] else (d3_info.get("c") or "")).strip()

        # Keep named stars up to mag 5.2 (all ~320 naked-eye proper-named stars).
        has_meta = bool(name) and mag <= 5.2
        flags = 1 if has_meta else 0
        if has_meta:
            dist = BRIGHT_STAR_DIST_LY.get(hip)
            named_stars.append([
                hip,
                name,
                bayer,
                con,
                dist,
            ])

        ra_q = int(round((ra % 360.0) / 360.0 * 65535)) & 0xFFFF
        dec_q = max(-32767, min(32767, int(round(dec / 90.0 * 32767))))
        mag_mmag = max(-32767, min(32767, int(round(mag * 1000.0))))
        bv_c = max(-127, min(127, int(round(max(-0.5, min(2.5, bv)) * 50.0))))
        buf.extend(struct.pack("<IHhhbB", hip, ra_q, dec_q, mag_mmag, bv_c, flags))

    return bytes(buf), named_stars


def build_constellations():
    lines_json = requests.get(f"{D3_BASE}/constellations.lines.json", timeout=30).json()
    meta_json = requests.get(f"{D3_BASE}/constellations.json", timeout=30).json()

    meta_by_id = {}
    for feat in meta_json["features"]:
        cid = feat["id"]
        props = feat["properties"]
        lon, lat = feat["geometry"]["coordinates"]
        meta_by_id[cid] = {
            "id": cid,
            "name": props.get("en") or props.get("name") or cid,
            "latin": props.get("la") or props.get("name") or cid,
            "genitive": props.get("gen") or "",
            "rank": int(props.get("rank") or 2),
            "ra": round(float(lon) % 360.0, 3),
            "dec": round(float(lat), 3),
        }

    by_code: dict[str, dict] = {}
    for feat in lines_json["features"]:
        raw_id = feat["id"]
        # Merge Ser1/Ser2 into official IAU 3-letter code 'Ser' if split, otherwise keep 3-letter code.
        code = "Ser" if raw_id.startswith("Ser") else raw_id
        info = meta_by_id.get(raw_id) or meta_by_id.get(code) or {
            "id": code, "name": code, "latin": code, "genitive": "", "rank": 2, "ra": 0.0, "dec": 0.0,
        }
        polylines = []
        for line in feat["geometry"]["coordinates"]:
            flat = []
            for lon, lat in line:
                flat.append(round(float(lon) % 360.0, 3))
                flat.append(round(float(lat), 3))
            if len(flat) >= 4:
                polylines.append(flat)
        if code in by_code:
            by_code[code]["lines"].extend(polylines)
        else:
            by_code[code] = {
                "id": code,
                "name": info["name"],
                "latin": info["latin"],
                "rank": info["rank"],
                "ra": info["ra"],
                "dec": info["dec"],
                "lines": polylines,
            }

    return sorted(by_code.values(), key=lambda c: c["name"])


def build_dso():
    curated_ids = set()
    if CURATED_MANIFEST.exists():
        manifest = json.loads(CURATED_MANIFEST.read_text(encoding="utf-8"))
        for item in manifest.get("highlights", []):
            if item.get("enabled", True) and item.get("body_id"):
                curated_ids.add(item["body_id"])

    rows = []
    for fname in ("NGC.csv", "addendum.csv"):
        p = BACKEND_CATALOGS / fname
        if p.exists():
            rows.extend(csv.DictReader(p.read_text(encoding="utf-8").splitlines(), delimiter=";"))

    seen = set()
    out = []
    for row in rows:
        kind = (row.get("Type") or "").strip()
        row_id = (row.get("Name") or "").strip()
        if not row_id or row_id in seen:
            continue
        messier = int(row["M"]) if (row.get("M") or "").strip().isdigit() else None
        messier = messier or MESSIER_OVERRIDES.get(row_id)
        if kind in SKIP_TYPES and (kind in NEVER_KEEP or not messier) and row_id not in curated_ids:
            continue
        try:
            ra = _sexagesimal(row["RA"]) * 15.0
            dec = _sexagesimal(row["Dec"])
        except (KeyError, ValueError, IndexError, AttributeError):
            continue

        v_mag, b_mag = _float(row.get("V-Mag")), _float(row.get("B-Mag"))
        mag = v_mag if v_mag is not None else b_mag
        common = [c.strip() for c in (row.get("Common names") or "").split(",") if c.strip()]
        common = [c[0].upper() + c[1:] for c in common]

        # Include all 110 Messier objects, all curated bodies, and bright named deep-sky gems.
        keep = (
            messier is not None
            or row_id in curated_ids
            or (bool(common) and mag is not None and mag <= 7.2)
        )
        if not keep:
            continue

        seen.add(row_id)
        code = _pretty_code(row_id)
        name = common[0] if common else (f"M{messier}" if messier else code)
        aliases = [f"M{messier}" if messier else "", code, *common[1:]]
        same = lambda a: a.replace(" ", "").lower() == name.replace(" ", "").lower()
        clean_aliases = list(dict.fromkeys(a for a in aliases if a and not same(a)))[:3]
        size_arcmin = _float(row.get("MajAx"))
        dist = _distance_ly(_float(row.get("Pax")), _float(row.get("Redshift")))

        out.append({
            "id": row_id,
            "name": name,
            "type": TYPE_LABELS.get(kind, kind or "Deep-sky object"),
            "ra": round(ra % 360.0, 4),
            "dec": round(dec, 4),
            "mag": round(mag, 2) if mag is not None else None,
            "size": round(size_arcmin, 1) if size_arcmin is not None else None,
            "m": messier,
            "con": (row.get("Const") or "").strip(),
            "aliases": clean_aliases,
            "dist": dist,
        })

    out.sort(key=lambda d: (0 if d["m"] else 1, d["mag"] if d["mag"] is not None else 99.0))
    return out


def write_sources_doc(star_count: int, named_count: int, con_count: int, dso_count: int) -> None:
    (OUT_DIR / "SOURCES.md").write_text(
        "# Sky View Bundled Data Sources & Licenses\n\n"
        "All catalogs and imagery shipped inside `app/assets/sky/` are used offline at runtime.\n\n"
        "| File | Contents | Upstream Source | License |\n"
        "|---|---|---|---|\n"
        "| `mellinger_galactic.webp` | 3600×1800 Galactic `CAR` all-sky Milky Way panorama | "
        "Axel Mellinger (2009, *PASP* 121, 1180) via NASA SkyView (`Mellinger Red/Green/Blue`) | "
        "© Axel Mellinger — **verify commercial/redistribution license terms with Axel Mellinger before release** |\n"
        f"| `stars.bin` | {star_count} stars to V ≤ 6.5 (J2000 RA/Dec, Vmag, B−V, HIP) | "
        "`ofrohn/d3-celestial` (`data/stars.8.json`, derived from ESA Hipparcos `I/239` & XHIP) | "
        "BSD-3-Clause (Copyright © 2015 Olaf Frohn) |\n"
        f"| `sky_catalog.json` (`named_stars`) | {named_count} proper star names & Bayer designations | "
        "IAU Working Group on Star Names (`IAU-WGSN.csv` / `IAU-CSN.txt`) + `ofrohn/d3-celestial` (`starnames.json`) | "
        "IAU Public / BSD-3-Clause |\n"
        f"| `sky_catalog.json` (`constellations`) | {con_count} IAU constellation stick figures & names | "
        "`ofrohn/d3-celestial` (`constellations.lines.json`, `constellations.json`) | "
        "BSD-3-Clause (Copyright © 2015 Olaf Frohn) |\n"
        f"| `sky_catalog.json` (`dso`) | {dso_count} Messier, curated & bright deep-sky objects | "
        "OpenNGC (`NGC.csv` + `addendum.csv`, Mattia Verga) | "
        "CC BY-SA 4.0 |\n",
        encoding="utf-8",
    )


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    stars_bin, named_stars = build_stars()
    constellations = build_constellations()
    dso = build_dso()

    stars_path = OUT_DIR / "stars.bin"
    stars_path.write_bytes(stars_bin)

    catalog_path = OUT_DIR / "sky_catalog.json"
    catalog_json = json.dumps(
        {
            "named_stars": named_stars,
            "constellations": constellations,
            "dso": dso,
        },
        separators=(",", ":"),
        ensure_ascii=False,
    )
    catalog_path.write_text(catalog_json, encoding="utf-8")

    star_count = struct.unpack_from("<H", stars_bin, 6)[0]
    write_sources_doc(star_count, len(named_stars), len(constellations), len(dso))

    print(
        f"stars.bin: {len(stars_bin)/1024:.1f} KB ({star_count} stars, {len(named_stars)} named) | "
        f"sky_catalog.json: {catalog_path.stat().st_size/1024:.1f} KB "
        f"({len(constellations)} constellations, {len(dso)} DSOs)"
    )


if __name__ == "__main__":
    main()
