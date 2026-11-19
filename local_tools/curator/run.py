r"""Local curator launcher.   Usage (from the repo root, with the backend venv):

    set ENABLE_CURATOR=1                (PowerShell: $env:ENABLE_CURATOR=1)
    backend\.venv\Scripts\python local_tools\curator\run.py            # start the UI
    backend\.venv\Scripts\python local_tools\curator\run.py export     # write backend/curated_bundle

It only ever listens on 127.0.0.1 and refuses to start unless ENABLE_CURATOR=1.
"""
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PORT = os.environ.get("CURATOR_PORT", "8765")


def main() -> None:
    if os.environ.get("ENABLE_CURATOR") != "1":
        sys.exit("Curator is disabled. Set ENABLE_CURATOR=1 first (see README.md).")
    sys.path.insert(0, str(HERE))
    os.environ["DJANGO_SETTINGS_MODULE"] = "curator_settings"
    import django
    from django.core.management import call_command
    django.setup()
    call_command("migrate", interactive=False, verbosity=0)
    command = sys.argv[1] if len(sys.argv) > 1 else "run"
    if command == "export":
        from curator_export import export_bundle
        result = export_bundle()
        print(f"Exported {result['highlights']} image(s) for {result['bodies']} body(ies) "
              f"to {result['path']}")
        if result["missing_files"]:
            print("WARNING: image files missing for:", ", ".join(result["missing_files"]))
    elif command == "run":
        print(f"Curator running at http://127.0.0.1:{PORT}/  (Ctrl+C to stop)")
        call_command("runserver", f"127.0.0.1:{PORT}", use_reloader=False)
    elif command == "sync-metadata":
        # Explicitly requested local maintenance; never touches image bytes.
        import hashlib
        import json
        from django.db import transaction
        from curated.models import CuratedHighlight
        from django.conf import settings
        manifest = Path(settings.CURATED_BUNDLE_DIR) / "manifest.json"
        rows = json.loads(manifest.read_text(encoding="utf-8"))["highlights"]
        updates = []
        for row in rows:
            local_image = Path(settings.CURATED_MEDIA_ROOT) / row["image_file"]
            bundle_image = manifest.parent / "images" / row["image_file"]
            if local_image.exists() and hashlib.sha256(local_image.read_bytes()).digest() != hashlib.sha256(bundle_image.read_bytes()).digest():
                sys.exit(f"Image differs from reviewed bundle; no metadata synced: {row['image_file']}")
            fields = ("body_id", "body_name", "title", "source_outlet", "source_url", "source_link_text", "credit",
                      "license_name", "license_url", "modifications", "ra", "dec")
            updates.append((row["image_file"], {k: row[k] for k in fields if k in row}))
        changed = 0
        with transaction.atomic():
            for filename, values in updates:
                changed += CuratedHighlight.objects.filter(image_file=filename).update(**values)
        print(f"Synced reviewed bundle metadata into {changed} existing local record(s). No images changed.")
    else:
        sys.exit(f"Unknown command {command!r}: use 'run', 'export' or 'sync-metadata'.")


if __name__ == "__main__":
    main()
