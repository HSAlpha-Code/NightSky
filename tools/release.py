"""Generate bundled/public legal documents and audit release inputs; no network or secrets.

Run from any directory: python tools/release.py render | check | inventory
The Gradle release task runs `check` automatically. Draft/debug builds remain usable.
"""
import argparse
import hashlib
import html
import json
import re
import sys
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "release/publisher.json"
REGISTER = ROOT / "release/rights-register.json"
APP_LEGAL = ROOT / "app/assets/legal"
PUBLIC_LEGAL = ROOT / "backend/legal"


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inventory():
    """All shipped sky data and curated originals (thumbnails covered with originals)."""
    rows = []
    for path in sorted((ROOT / "app/assets/sky").iterdir()):
        if path.suffix in (".webp", ".bin", ".json"):
            rows.append({"id": path.relative_to(ROOT).as_posix(), "sha256": sha256(path)})
    manifest = read_json(ROOT / "backend/curated_bundle/manifest.json")
    for record in manifest["highlights"]:
        path = ROOT / "backend/curated_bundle/images" / record["image_file"]
        thumb = path.with_name(path.stem + "_t.jpg")
        rows.append({
            "id": path.relative_to(ROOT).as_posix(),
            "sha256": sha256(path),
            "thumbnail_sha256": sha256(thumb) if thumb.exists() else "",
            "source_url": record.get("source_url", ""),
            "credit": record.get("credit", ""),
            "license_name": record.get("license_name", ""),
            "license_url": record.get("license_url", ""),
            "modifications": record.get("modifications", ""),
            "body_name": record["body_name"],
            "body_id": record["body_id"], "ra": record.get("ra"), "dec": record.get("dec"),
        })
    return rows


def input_errors(config, for_build=False):
    errors = []
    for key in (
        "publisher_name", "publisher_country", "support_email", "effective_date",
        "hosting_provider", "hosting_regions", "hosting_log_retention", "upload_retention",
        "deletion_process", "audience_statement", "monetization_statement", "analytics_statement",
        "legal_bases", "international_processing_safeguards", "rights_and_complaints",
    ):
        value = config.get(key)
        if not isinstance(value, str) or not value.strip() or "TODO" in value or "[" in value:
            errors.append(f"publisher.json: complete {key}")
    if not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", config.get("support_email", "")):
        errors.append("publisher.json: supply a real public support/privacy email")
    url = urlparse(config.get("privacy_policy_url", ""))
    if url.scheme != "https" or not url.hostname or url.hostname.endswith(".invalid"):
        errors.append("publisher.json: privacy_policy_url must be a public HTTPS URL")
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", config.get("effective_date", "")):
        errors.append("publisher.json: effective_date must use YYYY-MM-DD")
    countries = config.get("release_countries")
    if (not isinstance(countries, list) or not countries or
            any(not isinstance(c, str) or not re.fullmatch(r"[A-Z]{2}", c) for c in countries)):
        errors.append("publisher.json: choose explicit two-letter release_countries from Play Console")
    for key in (
        "privacy_reviewed", "production_retention_verified", "dependency_and_icon_rights_reviewed",
        "trademark_reviewed", "play_console_declarations_reviewed", "device_and_16kb_tests_passed",
        "market_legal_reviewed",
    ):
        # Final artifact/device testing happens after producing the candidate bundle.
        if for_build and key == "device_and_16kb_tests_passed":
            continue
        if config.get(key) is not True:
            errors.append(f"publisher.json: evidence/review required for {key}")
    return errors


def documents(config):
    def field(key):
        return config.get(key) or f"[RELEASE INPUT REQUIRED: {key}]"

    # Draft status cannot be removed merely by supplying a name/email.
    draft = "DRAFT - NOT APPROVED FOR PUBLIC RELEASE\n\n" if input_errors(config, for_build=True) else ""
    privacy = f"""{draft}NightSky Privacy Policy
Effective date: {field('effective_date')}
Publisher: {field('publisher_name')} ({field('publisher_country')})
Privacy and support contact: {field('support_email')}
Public policy: {field('privacy_policy_url')}

Camera mode and online requests
When you agree to use camera uploads, NightSky sends your captured sky photograph,
capture time, camera field of view, phone orientation and, when available and permitted,
latitude, longitude and altitude to the server selected in Settings. These are used to
identify the photographed sky and retrieve astronomical survey images. Auto-capture,
if enabled, repeats this for each capture. Upload consent is requested again in a new
app session, after revocation, or when the selected server changes.

The server and hosting provider can receive your IP address and request metadata.
The backend queries astronomical image/catalogue services (including CDS, NASA SkyView,
ESA ESASky and MAST) using sky coordinates and image parameters. NightSky's solver
processes your photograph on the selected backend; it does not send the photograph
to those survey services. Opening source links launches an external website whose
own privacy policy applies. Custom servers are operated by their respective owners;
contact that operator for its retention practices before sending data there.

Sky View and device storage
The bundled star map and astronomical calculations work on the device. Sky View uses
location, when permitted, and orientation sensors to position the sky. A manually
chosen or last available location and app preferences can be stored locally. Online
object details and curated highlights require requests to the selected server; the
curated index is also requested when the app starts. Downloaded astronomical images
are cached locally (up to approximately 100 MB); the operating system may clear them.
Captured photographs and metadata are kept in the active in-memory result session.
NightSky attempts to remove the camera's temporary capture after reading it. The
result session is cleared when you leave the result screen. This is not a guarantee
that operating-system or hosting infrastructure never creates temporary copies.

Retention, hosting and deletion
Hosting provider: {field('hosting_provider')}
Hosting/processing regions: {field('hosting_regions')}
Uploaded photographs/metadata retention: {field('upload_retention')}
Hosting, security and request-log retention: {field('hosting_log_retention')}
Deletion/request process: {field('deletion_process')}
Local preferences, saved location and caches can be removed through Android's app
storage controls or by uninstalling. Location permission can be revoked in Android
settings. Photo upload consent can be revoked in NightSky Settings; this stops future
captures from uploading without asking again and does not undo an earlier request.

Applicable legal bases, international processing and rights
Legal bases for the described processing: {field('legal_bases')}
International processing and applicable safeguards: {field('international_processing_safeguards')}
Privacy rights, request process and complaints: {field('rights_and_complaints')}

Security and choices
The default production server uses HTTPS. Android release builds block cleartext
HTTP. Camera and foreground location access use Android runtime permissions; microphone
and background location permissions are not requested. Location is optional: you can
deny it or use a manual location in Sky View. You can decline a photo upload and use
Sky View. Permissions and upload consent are separate choices.

Audience: {field('audience_statement')}
Ads, purchases and accounts: {field('monetization_statement')}
Analytics and diagnostics: {field('analytics_statement')}

Changes and contact
We update the effective date when this policy changes. Contact the publisher above
for privacy questions and data requests. Applicable rights depend on where you live.
"""
    credits = """NightSky - Image and Data Credits

NightSky is an independent astronomy app. NASA, ESA, CSA, STScI, CDS and other
organisations listed as data sources do not sponsor or endorse the app.

Bundled catalogue data
Stars and constellation figures: d3-celestial, Copyright (c) 2015 Olaf Frohn,
BSD-3-Clause. Source: https://github.com/ofrohn/d3-celestial
NightSky converts/subsets upstream data into stars.bin and sky_catalog.json.
Full BSD terms are available under Settings > Open-source licences.

Deep-sky object catalogue: OpenNGC, Mattia Verga, CC BY-SA 4.0.
Source: https://github.com/mattiaverga/openngc
Licence: https://creativecommons.org/licenses/by-sa/4.0/
NightSky selects, merges and reformats catalogue entries. OpenNGC-derived adapted
catalogue data is distributed under CC BY-SA 4.0. Other components and third-party
data retain their own terms. The bundled sky_catalog.json is available on the
server at /legal/sky_catalog.json after deploying this release preparation.

Proper star names: IAU Working Group on Star Names; astrometry from ESA Hipparcos
and XHIP through d3-celestial. Geomagnetism: NOAA/NCEI WMM-2025.

Milky Way panorama: Copyright Axel Mellinger (2009, PASP 121, 1180), obtained
through NASA SkyView and reprojected/split/re-encoded for NightSky.

Online survey cutouts and mosaics
DSS2 / Digitized Sky Survey via CDS hips2fits and ESA ESASky; Hubble and Webb imagery
via ESA ESASky/MAST; Mellinger via NASA SkyView. Source-service access alone does not
grant all redistribution rights. Individual curated image credits and source links follow.
ESA/Hubble terms: https://esahubble.org/copyright/
ESA/Webb terms: https://esawebb.org/copyright/
CC BY 4.0: https://creativecommons.org/licenses/by/4.0/
NASA terms: https://www.nasa.gov/nasa-brand-center/images-and-media/
Images may have been resized/re-encoded; survey mosaics are assembled from tiles.

Curated images
"""
    manifest = read_json(ROOT / "backend/curated_bundle/manifest.json")
    for row in manifest["highlights"]:
        credits += (f"\n{row['body_name']}: {row['credit']}\n"
                    f"{row['source_url'] or '[Source pending verification]'}\n"
                    f"Licence: {row.get('license_name') or 'Not yet verified'}\n"
                    f"{row.get('license_url', '')}\nChanges: {row.get('modifications', '')}\n")
    terms = f"""{draft}NightSky Terms of Use
Publisher: {field('publisher_name')}
Contact: {field('support_email')}
Effective date: {field('effective_date')}

NightSky helps you explore the sky. Displayed survey images are observations by
other instruments, not extra detail captured by your phone. Pointing and object
identification may be approximate or incorrect. Do not rely on the app for navigation
or safety-critical decisions. Do not point an optical instrument at the Sun without
appropriate specialist equipment and knowledge.

Third-party images, data and software retain their own licences, available in the
app's credits and open-source notices. These terms do not restrict rights granted
under those licences. Online features depend on external services and availability
may vary. The Privacy Policy describes data use and choices. Applicable mandatory
consumer rights remain unaffected.
"""
    return {"privacy": privacy, "credits": credits, "terms": terms}


def generated_files(config):
    files = {}
    for name, content in documents(config).items():
        files[APP_LEGAL / f"{name}.txt"] = content
        files[PUBLIC_LEGAL / f"{name}.html"] = (
            "<!doctype html><html lang=\"en\"><meta charset=\"utf-8\">"
            "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
            f"<title>NightSky {name.title()}</title>"
            "<style>body{max-width:52rem;margin:2rem auto;padding:0 1rem;"
            "font:17px/1.6 system-ui}pre{white-space:pre-wrap;font:inherit}</style>"
            f"<main><pre>{html.escape(content)}</pre></main></html>\n"
        )
    return files


def check(config, for_build=False):
    errors = input_errors(config, for_build=for_build)
    for path, expected in generated_files(config).items():
        if not path.exists() or path.read_text(encoding="utf-8") != expected:
            errors.append(f"stale/missing document: {path.relative_to(ROOT)}; run render")
    if not REGISTER.exists():
        errors.append("missing release/rights-register.json")
        return errors
    register = read_json(REGISTER)
    rights = {r["id"]: r for r in register["assets"]}
    for current in inventory():
        record = rights.get(current["id"], {})
        if record.get("status") != "cleared" or not record.get("evidence"):
            errors.append(f"rights unresolved: {current['id']}")
        for key in ("sha256", "thumbnail_sha256", "source_url", "credit",
                    "license_name", "license_url", "modifications", "body_name", "body_id", "ra", "dec"):
            if key in current and record.get(key) != current[key]:
                errors.append(f"rights record changed/missing {key}: {current['id']}")
    expected_online = {"dss2_color", "skyview_mellinger", "esasky_hst", "esasky_jwst"}
    online = {r["id"] for r in register["online_sources"]}
    for missing in sorted(expected_online - online):
        errors.append(f"missing online source rights record: {missing}")
    for row in register["online_sources"]:
        if row.get("status") != "cleared" or not row.get("evidence"):
            errors.append(f"online source rights unresolved: {row['id']}")
    for name in ("d3-celestial-BSD.txt", "OpenNGC-CC-BY-SA-4.0.txt", "NightSky-MIT.txt"):
        if not (APP_LEGAL / name).is_file():
            errors.append(f"missing shipped licence: {name}")
    provenance_path = ROOT / "release/licence-provenance.json"
    if not provenance_path.is_file():
        errors.append("missing upstream licence provenance")
    else:
        for record in read_json(provenance_path):
            path = APP_LEGAL / record["file"]
            if not path.is_file() or sha256(path) != record["sha256"]:
                errors.append(f"shipped upstream licence changed: {record['file']}")
    catalog = ROOT / "app/assets/sky/sky_catalog.json"
    public_catalog = PUBLIC_LEGAL / "sky_catalog.json"
    if not public_catalog.exists() or sha256(public_catalog) != sha256(catalog):
        errors.append("public adapted catalogue copy is stale; run render")
    # Catch image files added without an entry, including unreferenced originals.
    covered = set()
    for row in inventory():
        if "curated_bundle/images/" in row["id"]:
            p = Path(row["id"])
            covered.update((p.name, p.stem + "_t.jpg"))
    for p in (ROOT / "backend/curated_bundle/images").iterdir():
        if p.is_file() and p.name not in covered:
            errors.append(f"unregistered bundled image: {p.name}")
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("render", "check", "inventory"))
    parser.add_argument("--for-build", action="store_true",
                        help="Allow creating a candidate before final device/16KB testing; not publication clearance")
    args = parser.parse_args()
    if args.command == "inventory":
        print(json.dumps(inventory(), indent=2, ensure_ascii=True))
        return 0
    config = read_json(CONFIG)
    if args.command == "render":
        for path, content in generated_files(config).items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")
        (PUBLIC_LEGAL / "sky_catalog.json").write_bytes(
            (ROOT / "app/assets/sky/sky_catalog.json").read_bytes())
        print("Legal documents rendered. Drafts remain blocked until reviews are complete.")
        return 0
    errors = check(config, for_build=args.for_build)
    if errors:
        print("PUBLIC RELEASE BLOCKED:\n" + "\n".join(f"- {e}" for e in errors))
        return 1
    print("Recorded release inputs passed. This is not legal clearance or Play approval.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
