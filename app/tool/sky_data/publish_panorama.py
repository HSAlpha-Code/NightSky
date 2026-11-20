"""Prepare/verify NASA panorama assets, then optionally publish a GitHub release.

python app/tool/sky_data/publish_panorama.py
python app/tool/sky_data/publish_panorama.py --publish

Uses GH_TOKEN/GITHUB_TOKEN or Git's credential helper. Credentials are never
printed or written to disk. Existing assets are verified, never overwritten.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[3]
REPOSITORY = "HSAlpha-Code/NightSky"
TAG = "panorama-nasa2020-v1"
API = f"https://api.github.com/repos/{REPOSITORY}"


def sha256(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def prepare():
    destination = ROOT / "release" / TAG
    destination.mkdir(parents=True, exist_ok=True)
    files = []
    for k in (16, 32):
        folder = ROOT / "backend" / "panorama_packs" / f"{k}k"
        manifest = folder / "manifest.json"
        data = json.loads(manifest.read_text(encoding="utf-8"))
        if (data["width"], data["height"]) != (k * 1024, k * 512):
            raise ValueError("Unexpected map dimensions")
        if "lossless" not in data["encoding"] or len(data["tiles"]) != k * k // 8:
            raise ValueError("Incomplete or unsupported pack")
        sources = [manifest]
        for tile in data["tiles"]:
            name = tile["file"]
            if Path(name).name != name or "/" in name or "\\" in name:
                raise ValueError("Invalid tile filename")
            path = folder / name
            if path.stat().st_size != tile["bytes"] or sha256(path) != tile["sha256"]:
                raise ValueError(f"Invalid tile: {path.name}")
            with path.open("rb") as source:
                if source.read(16)[12:16] != b"VP8L":
                    raise ValueError("Expected lossless WebP")
            sources.append(path)
        for source in sources:
            target = destination / f"nasa2020-{k}k-{source.name}"
            if not target.exists() or sha256(target) != sha256(source):
                shutil.copyfile(source, target)
            files.append(target)
    credit = destination / "NASA-SOURCES.txt"
    shutil.copyfile(ROOT / "backend/panorama_packs/SOURCES.md", credit)
    files.append(credit)
    checksums = destination / "SHA256SUMS.txt"
    checksums.write_text("".join(f"{sha256(p)}  {p.name}\n" for p in files), encoding="utf-8")
    files.append(checksums)
    print(f"Prepared {len(files)} assets, {sum(p.stat().st_size for p in files):,} bytes", flush=True)
    return files


def credentials():
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if token:
        return token
    result = subprocess.run(["git", "credential", "fill"], cwd=ROOT,
        input="protocol=https\nhost=github.com\n\n", text=True, capture_output=True,
        env=dict(os.environ, GIT_TERMINAL_PROMPT="0", GCM_INTERACTIVE="never"))
    values = dict(line.split("=", 1) for line in result.stdout.splitlines() if "=" in line)
    if not values.get("password"):
        raise RuntimeError("GitHub authentication required. Sign in to Git or set GH_TOKEN.")
    return values["password"]


def publish(files):
    token = credentials()

    def request(method, url, body=None, content_type="application/json"):
        if body is not None and not isinstance(body, bytes):
            body = json.dumps(body).encode()
        req = urllib.request.Request(url, data=body, method=method, headers={
            "Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json",
            "User-Agent": "NightSky-panorama-publisher", "Content-Type": content_type,
            "X-GitHub-Api-Version": "2022-11-28",
        })
        with urllib.request.urlopen(req, timeout=180) as response:
            return json.load(response)

    try:
        release = request("GET", f"{API}/releases/tags/{TAG}")
    except urllib.error.HTTPError as error:
        if error.code != 404:
            raise
        repo = request("GET", API)
        commit = request("GET", f"{API}/commits/{repo['default_branch']}")["sha"]
        release = request("POST", f"{API}/releases", {
            "tag_name": TAG, "target_commitish": commit, "name": "NASA Deep Star Maps 2020 - offline panorama packs",
            "draft": True, "make_latest": "false",
            "body": "Optional native 16K (102.4 MiB) and 32K (349.5 MiB) offline maps for NightSky. "
                "The app downloads the manifest and tiles directly from this release, verifies SHA-256, "
                "and installs them for offline Sky View. 8K remains included in the app.\n\n"
                "Tiles use pixel-verified lossless WebP. Original linear HDR is converted to sRGB8 "
                "with display-white clipping; native dimensions are preserved. No upscaling.\n\n"
                "Credit: NASA/Goddard Space Flight Center Scientific Visualization Studio. "
                "Gaia DR2: ESA/Gaia/DPAC. Visualization: Ernie Wright.\n\n"
                "Source: https://svs.gsfc.nasa.gov/4851/\n"
                "Public domain under https://svs.gsfc.nasa.gov/help/; NASA does not endorse NightSky. "
                "See NASA-SOURCES.txt for processing and reuse details.\n\n"
                "Versioned assets are immutable. Updated maps must use a new release tag.",
        })

    def assets():
        result = []
        page = 1
        while True:
            rows = request("GET", f"{API}/releases/{release['id']}/assets?per_page=100&page={page}")
            result.extend(rows)
            if len(rows) < 100:
                return {asset["name"]: asset for asset in result}
            page += 1

    existing = assets()

    def verify(path, asset):
        if asset["size"] != path.stat().st_size or asset.get("state") != "uploaded":
            raise ValueError(f"Release asset incomplete: {path.name}")
        digest = asset.get("digest")
        if digest and digest != f"sha256:{sha256(path)}":
            raise ValueError(f"Release checksum mismatch: {path.name}")

    def upload(path):
        if path.name in existing:
            verify(path, existing[path.name])
            return
        if not release["draft"]:
            raise RuntimeError("Published release is immutable; refusing to add or replace assets")
        url = release["upload_url"].split("{", 1)[0] + "?name=" + urllib.parse.quote(path.name)
        asset = request("POST", url, path.read_bytes(), "application/octet-stream")
        verify(path, asset)
        print(f"Uploaded {path.name}", flush=True)

    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(upload, files))
    uploaded = assets()
    for path in files:
        verify(path, uploaded[path.name])
    if release["draft"]:
        release = request("PATCH", f"{API}/releases/{release['id']}", {"draft": False, "make_latest": "false"})
    print(f"Published and verified {len(files)} assets: {release['html_url']}", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--publish", action="store_true", help="Upload verified assets and publish their GitHub release")
    args = parser.parse_args()
    prepared = prepare()
    if args.publish:
        publish(prepared)
