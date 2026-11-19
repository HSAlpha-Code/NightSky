"""Inventory installed Flutter/Python dependencies without upgrading or contacting registries.

Use backend/.venv/Scripts/python.exe tools/dependency_licenses.py.
This inventories the local environment; review the locked production build separately.
"""
import hashlib
import importlib.metadata as metadata
import json
from pathlib import Path
from urllib.parse import unquote, urlparse
from urllib.request import url2pathname

ROOT = Path(__file__).resolve().parents[1]


def main():
    config_path = ROOT / "app/.dart_tool/package_config.json"
    config = json.loads(config_path.read_text(encoding="utf-8"))
    flutter = []
    for package in config["packages"]:
        uri = urlparse(package["rootUri"])
        folder = (Path(url2pathname(uri.path)) if uri.scheme == "file" else
                  (config_path.parent / unquote(package["rootUri"])).resolve())
        notices = [p for p in folder.iterdir()
                   if p.is_file() and p.name.upper().startswith(("LICENSE", "LICENCE", "NOTICE"))]
        flutter.append({"package": package["name"], "notices": [
            {"name": p.name, "sha256": hashlib.sha256(p.read_bytes()).hexdigest()}
            for p in notices], "review_required": not bool(notices)})
    python = []
    notice_text = []
    for dist in sorted(metadata.distributions(), key=lambda d: d.metadata["Name"].lower()):
        info = dist.metadata
        files = [f for f in dist.files or [] if
                 any(x in str(f).lower() for x in (".dist-info/licenses/", ".dist-info/license", ".dist-info/notice"))]
        python.append({
            "package": info["Name"], "version": dist.version,
            "license_expression": info.get("License-Expression", ""),
            "license": info.get("License", ""),
            "license_classifiers": [c for c in info.get_all("Classifier", []) if c.startswith("License ::")],
            "notice_files": [str(f) for f in files],
            "project_urls": info.get_all("Project-URL", []),
        })
        for f in files:
            path = dist.locate_file(f)
            if path.is_file():
                notice_text.append(f"\n{'=' * 72}\n{info['Name']} {dist.version}: {Path(str(f)).name}\n\n"
                                   + path.read_text(encoding="utf-8", errors="replace"))
    result = {"scope": "Installed local environment, including development dependencies. Not a legal clearance or vulnerability scan.",
              "flutter": flutter, "python": python}
    (ROOT / "release/dependency-inventory.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    (ROOT / "backend/legal/python-notices.txt").write_text("Installed Python dependency notices\n" + "\n".join(notice_text), encoding="utf-8")
    print(f"Inventoried {len(flutter)} Flutter packages and {len(python)} installed Python packages.")
    missing = [p["package"] for p in flutter if p["review_required"]]
    print("Flutter packages without a root notice file: " + ", ".join(missing))


if __name__ == "__main__":
    main()
