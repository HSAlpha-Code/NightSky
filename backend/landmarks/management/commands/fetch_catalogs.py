from django.core.management.base import BaseCommand, CommandError

from config.http import ExternalServiceError
from landmarks.catalog import ensure_files, get_catalog


class Command(BaseCommand):
    help = "Download the landmark catalogues (OpenNGC + IAU star names) into CATALOG_DIR."

    def add_arguments(self, parser):
        parser.add_argument("--force", action="store_true", help="Re-download existing files.")

    def handle(self, *args, force=False, **options):
        try:
            folder = ensure_files(force=force)
        except ExternalServiceError as exc:
            raise CommandError(f"Download failed: {exc}") from exc
        catalog = get_catalog()
        self.stdout.write(self.style.SUCCESS(
            f"{len(catalog.landmarks)} landmarks ready in {folder}"))
