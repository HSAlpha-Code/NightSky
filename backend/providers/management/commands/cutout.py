from pathlib import Path

from django.core.management.base import BaseCommand, CommandError

from providers.base import ProviderError
from providers.registry import all_providers, get_provider


class Command(BaseCommand):
    help = "Save a sky cutout. Example: manage.py cutout 83.82 -5.39 2.0 -o orion.jpg"

    def add_arguments(self, parser):
        parser.add_argument("ra", type=float, help="Right ascension, degrees")
        parser.add_argument("dec", type=float, help="Declination, degrees")
        parser.add_argument("fov", type=float, help="Horizontal field of view, degrees")
        parser.add_argument("-o", "--output", default="cutout.jpg")
        parser.add_argument("-p", "--provider", default=None,
                            help="Provider key: " + ", ".join(p.key for p in all_providers()))
        parser.add_argument("--rotation", type=float, default=0.0, help="Degrees east of north")
        parser.add_argument("--width", type=int, default=1200)
        parser.add_argument("--height", type=int, default=800)

    def handle(self, *args, **o):
        provider = get_provider(o["provider"])
        if provider is None:
            raise CommandError(f"Unknown provider {o['provider']!r}")
        if not provider.supports(o["ra"], o["dec"], o["fov"]):
            raise CommandError(f"NO_COVERAGE: {provider.name} covers {provider.coverage}")
        try:
            data = provider.fetch_cutout(o["ra"], o["dec"], o["fov"], o["rotation"],
                                         o["width"], o["height"])
        except ProviderError as exc:
            raise CommandError(f"PROVIDER_UNAVAILABLE: {exc}") from exc
        Path(o["output"]).write_bytes(data)
        self.stdout.write(self.style.SUCCESS(
            f"Saved {len(data)} bytes from {provider.name} to {o['output']}"))
