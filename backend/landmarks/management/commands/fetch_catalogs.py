from django.core.management.base import BaseCommand, CommandError

from config.http import ExternalServiceError
from landmarks import catalog as catalog_mod
from landmarks.catalog import WGSN_FILE, ensure_files, fetch_wgsn, get_catalog


class Command(BaseCommand):
    help = ("Download the landmark catalogues (OpenNGC + IAU star names, including the current "
            "WGSN list) into CATALOG_DIR.")

    def add_arguments(self, parser):
        parser.add_argument("--force", action="store_true", help="Re-download existing files.")

    def handle(self, *args, force=False, **options):
        try:
            folder = ensure_files(force=force)
        except ExternalServiceError as exc:
            raise CommandError(f"Download failed: {exc}") from exc
        if force or not (folder / WGSN_FILE).is_file():
            try:
                count = fetch_wgsn(folder)
                self.stdout.write(f"{count} IAU star names saved to {folder / WGSN_FILE}")
            except (ExternalServiceError, ValueError) as exc:
                # Optional: the older IAU-CSN.txt list still works without it.
                self.stderr.write(self.style.WARNING(f"Current IAU star names skipped: {exc}"))
        catalog_mod._catalog = None          # reload with the new files
        catalog = get_catalog()
        self.stdout.write(self.style.SUCCESS(
            f"{len(catalog.landmarks)} landmarks ready in {folder}"))
