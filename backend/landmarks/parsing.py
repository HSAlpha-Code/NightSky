"""Parse OpenNGC (Messier/NGC/IC) and the IAU star-name lists into Landmark records."""
import csv
import io
import re
from dataclasses import dataclass
from html.parser import HTMLParser

TYPE_LABELS = {
    "G": "Galaxy", "GPair": "Galaxy pair", "GTrpl": "Galaxy triplet", "GGroup": "Galaxy group",
    "OCl": "Open cluster", "GCl": "Globular cluster", "Cl+N": "Star cluster with nebula",
    "PN": "Planetary nebula", "HII": "Emission nebula (HII region)", "EmN": "Emission nebula",
    "Neb": "Nebula", "RfN": "Reflection nebula", "SNR": "Supernova remnant",
    "DrkN": "Dark nebula", "*Ass": "Stellar association", "star": "Star",
    "*": "Star", "**": "Double star", "Other": "Asterism",
}
# Not real deep-sky objects (single/double stars, asterisms, plate flaws, duplicates...).
SKIP_TYPES = {"", "Dup", "NonEx", "*", "**", "Other", "Nova"}
# ...but Messier objects among them are kept: M40 is a double star, M73 an asterism, and both
# are classic observing targets. Duplicates and non-existent entries are never kept.
NEVER_KEEP = {"", "Dup", "NonEx"}
# Messier numbers OpenNGC doesn't assign. M102's identity is disputed: OpenNGC lists it as a
# duplicate of M101, but most modern lists (and OpenNGC's own note) use NGC 5866.
MESSIER_OVERRIDES = {"NGC5866": 102}
LY_PER_PC = 3.26156
LY_PER_MPC = 3.26156e6
HUBBLE_CONSTANT = 70.0     # km/s/Mpc, for rough galaxy distances from redshift


@dataclass(frozen=True)
class Landmark:
    id: str
    name: str
    kind: str                       # "dso" | "star"
    type: str                       # OpenNGC type code, or "star"
    ra: float
    dec: float
    magnitude: float | None = None
    size_arcmin: float | None = None
    messier: int | None = None
    common_name: bool = False       # has a real name, not just a catalogue number
    constellation: str = ""
    aliases: tuple[str, ...] = ()
    distance_ly: float | None = None

    @property
    def type_label(self) -> str:
        return TYPE_LABELS.get(self.type, self.type)

    def to_dict(self) -> dict:
        return {
            "id": self.id, "name": self.name, "kind": self.kind, "type": self.type,
            "type_label": self.type_label, "ra": self.ra, "dec": self.dec,
            "magnitude": self.magnitude, "size_arcmin": self.size_arcmin,
            "messier": self.messier, "constellation": self.constellation,
            "aliases": list(self.aliases), "distance_ly": self.distance_ly,
        }


def _float(value) -> float | None:
    try:
        return float(value) if value not in (None, "") else None
    except ValueError:
        return None


def _sexagesimal(text: str) -> float:
    sign = -1.0 if text.strip().startswith("-") else 1.0
    parts = [abs(float(p)) for p in text.strip().lstrip("+-").split(":")]
    return sign * (parts[0] + parts[1] / 60 + parts[2] / 3600)


def pretty_code(code: str) -> str:
    """NGC0224 -> NGC 224, IC0434 -> IC 434, Mel022 -> Mel 22."""
    m = re.match(r"^([A-Za-z]+)0*(\d+)(.*)$", code)
    return f"{m[1]} {m[2]}{m[3]}" if m else code


def distance_ly(parallax_mas: float | None, redshift: float | None) -> float | None:
    if parallax_mas and parallax_mas > 0.05:
        return round(1000 / parallax_mas * LY_PER_PC, -1)
    if redshift and redshift > 0.002:
        return round(redshift * 299792.458 / HUBBLE_CONSTANT * LY_PER_MPC, -5)
    return None


def parse_openngc(text: str) -> list[Landmark]:
    out = []
    for row in csv.DictReader(io.StringIO(text), delimiter=";"):
        kind = (row.get("Type") or "").strip()
        row_id = (row.get("Name") or "").strip()
        messier = int(row["M"]) if (row.get("M") or "").strip().isdigit() else None
        messier = messier or MESSIER_OVERRIDES.get(row_id)
        if kind in SKIP_TYPES and (kind in NEVER_KEEP or not messier):
            continue
        try:
            ra, dec = _sexagesimal(row["RA"]) * 15, _sexagesimal(row["Dec"])
        except (KeyError, ValueError, IndexError, AttributeError):
            continue
        common = [c.strip() for c in (row.get("Common names") or "").split(",") if c.strip()]
        common = [c[0].upper() + c[1:] for c in common]   # "the Running Man Nebula"
        code = pretty_code(row_id)
        name = common[0] if common else (f"M{messier}" if messier else code)
        aliases = [f"M{messier}" if messier else "", code, *common[1:]]
        same = lambda a: a.replace(" ", "") == name.replace(" ", "")   # "M 40" == "M40"
        v_mag, b_mag = _float(row.get("V-Mag")), _float(row.get("B-Mag"))
        out.append(Landmark(
            id=row_id, name=name, kind="dso", type=kind, ra=ra, dec=dec,
            magnitude=v_mag if v_mag is not None else b_mag,
            size_arcmin=_float(row.get("MajAx")), messier=messier, common_name=bool(common),
            constellation=(row.get("Const") or "").strip(),
            aliases=tuple(dict.fromkeys(a for a in aliases if a and not same(a))),
            distance_ly=distance_ly(_float(row.get("Pax")), _float(row.get("Redshift"))),
        ))
    return out


_STAR_TAIL = re.compile(
    r"(?P<mag>-?\d+\.\d+|_)\s+(?P<band>\S+)\s+(?P<hip>\d+|_)\s+(?P<hd>\d+|_)\s+"
    r"(?P<ra>\d+\.\d+)\s+(?P<dec>[-+]?\d+\.\d+)\s+\d{4}-\d{2}-\d{2}")
_CONSTELLATION = re.compile(r"\s([A-Z][a-z]{2})\s")


class _TableParser(HTMLParser):
    """Collects every <table> as (header cells, body rows) of plain text."""

    def __init__(self):
        super().__init__()
        self.tables: list[tuple[list[str], list[list[str]]]] = []
        self._cell: list[str] | None = None
        self._row: list[str] | None = None

        self._header_row = False      # the current row has <th> cells

    def handle_starttag(self, tag, attrs):
        if tag == "table":
            self.tables.append(([], []))
        elif tag == "tr" and self.tables:
            self._row, self._header_row = [], False
        elif tag in ("td", "th") and self._row is not None:
            self._cell = []
            self._header_row = self._header_row or tag == "th"

    def handle_endtag(self, tag):
        if tag in ("td", "th") and self._cell is not None and self._row is not None:
            self._row.append(" ".join("".join(self._cell).split()))
            self._cell = None
        elif tag == "tr" and self._row is not None:
            headers, rows = self.tables[-1]
            if self._row:
                (headers.extend if self._header_row and not headers else rows.append)(self._row)
            self._row = None

    def handle_data(self, data):
        if self._cell is not None:
            self._cell.append(data)


WGSN_COLUMNS = ("name", "hip", "designation", "bayer", "constellation", "ra", "dec", "mag",
                "band", "date")
_WGSN_HEADERS = {"proper names": "name", "hip": "hip", "designation": "designation",
                 "bayer id": "bayer", "constellation": "constellation", "ra": "ra", "dec": "dec",
                 "mag": "mag", "band": "band", "date of adoption": "date"}


def wgsn_html_to_csv(html: str) -> str:
    """Convert the WGSN star-name table (exopla.net, an HTML page) into a compact CSV.

    Raises ValueError if no table with names and coordinates is found (page layout changed)."""
    parser = _TableParser()
    parser.feed(html)
    for headers, rows in parser.tables:
        index = {_WGSN_HEADERS[h.strip().lower()]: i for i, h in enumerate(headers)
                 if h.strip().lower() in _WGSN_HEADERS}
        if not {"name", "ra", "dec"} <= index.keys():
            continue
        out = io.StringIO()
        writer = csv.writer(out, lineterminator="\n")
        writer.writerow(WGSN_COLUMNS)
        count = 0
        for row in rows:
            cell = lambda k: row[index[k]].strip() if k in index and index[k] < len(row) else ""
            if not cell("name") or _float(cell("ra")) is None or _float(cell("dec")) is None:
                continue
            writer.writerow([cell(k) for k in WGSN_COLUMNS])
            count += 1
        if count:
            return out.getvalue()
    raise ValueError("no star-name table with name/RA/Dec columns found")


def parse_wgsn_csv(text: str) -> list[Landmark]:
    """Stars from the CSV written by wgsn_html_to_csv (decimal-degree J2000 coordinates)."""
    out = []
    for row in csv.DictReader(io.StringIO(text)):
        name = (row.get("name") or "").strip()
        ra, dec = _float(row.get("ra")), _float(row.get("dec"))
        if not name or ra is None or dec is None or not -90 <= dec <= 90:
            continue
        hip = (row.get("hip") or "").strip()
        hip = hip if hip.isdigit() else None
        designation = (row.get("designation") or "").strip()
        bayer = (row.get("bayer") or "").strip()
        out.append(Landmark(
            id=f"HIP{hip}" if hip else "STAR-" + re.sub(r"\W+", "-", name),
            name=name, kind="star", type="star", ra=ra % 360, dec=dec,
            magnitude=_float(row.get("mag")), common_name=True,
            constellation=(row.get("constellation") or "").strip(),
            aliases=tuple(dict.fromkeys(a for a in (bayer, designation,
                                                    f"HIP {hip}" if hip else "")
                                        if a and a not in ("-", "_") and a != name)),
        ))
    return out


def merge_stars(primary: list[Landmark], extra: list[Landmark]) -> list[Landmark]:
    """`primary` plus the stars of `extra` that aren't in it (same id or same name)."""
    ids = {s.id for s in primary}
    names = {s.name.casefold() for s in primary}
    return primary + [s for s in extra if s.id not in ids and s.name.casefold() not in names]


def parse_iau_stars(text: str) -> list[Landmark]:
    """IAU-CSN fixed-width text: name in columns 1-18, designation in 37-49."""
    out = []
    for line in text.splitlines():
        if not line[:1].isalpha():
            continue
        m = _STAR_TAIL.search(line)
        if not m:
            continue
        name = line[:18].strip()
        designation = line[36:49].strip()
        con = _CONSTELLATION.search(line[36:m.start()])
        hip = m["hip"] if m["hip"] != "_" else None
        out.append(Landmark(
            id=f"HIP{hip}" if hip else "STAR-" + re.sub(r"\W+", "-", name),
            name=name, kind="star", type="star", ra=float(m["ra"]), dec=float(m["dec"]),
            magnitude=_float(m["mag"]) if m["mag"] != "_" else None, common_name=True,
            constellation=con[1] if con else "",
            aliases=tuple(a for a in (designation, f"HIP {hip}" if hip else "") if a),
        ))
    return out
