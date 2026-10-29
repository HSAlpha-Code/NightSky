"""Parse OpenNGC (Messier/NGC/IC) and the IAU Catalog of Star Names into Landmark records."""
import csv
import io
import re
from dataclasses import dataclass

TYPE_LABELS = {
    "G": "Galaxy", "GPair": "Galaxy pair", "GTrpl": "Galaxy triplet", "GGroup": "Galaxy group",
    "OCl": "Open cluster", "GCl": "Globular cluster", "Cl+N": "Star cluster with nebula",
    "PN": "Planetary nebula", "HII": "Emission nebula (HII region)", "EmN": "Emission nebula",
    "Neb": "Nebula", "RfN": "Reflection nebula", "SNR": "Supernova remnant",
    "DrkN": "Dark nebula", "*Ass": "Stellar association", "star": "Star",
}
SKIP_TYPES = {"", "Dup", "NonEx", "*", "**", "Other", "Nova"}
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
        if kind in SKIP_TYPES:
            continue
        try:
            ra, dec = _sexagesimal(row["RA"]) * 15, _sexagesimal(row["Dec"])
        except (KeyError, ValueError, IndexError, AttributeError):
            continue
        messier = int(row["M"]) if (row.get("M") or "").strip().isdigit() else None
        common = [c.strip() for c in (row.get("Common names") or "").split(",") if c.strip()]
        common = [c[0].upper() + c[1:] for c in common]   # "the Running Man Nebula"
        code = pretty_code(row["Name"].strip())
        name = common[0] if common else (f"M{messier}" if messier else code)
        aliases = [f"M{messier}" if messier else "", code, *common[1:]]
        v_mag, b_mag = _float(row.get("V-Mag")), _float(row.get("B-Mag"))
        out.append(Landmark(
            id=row["Name"].strip(), name=name, kind="dso", type=kind, ra=ra, dec=dec,
            magnitude=v_mag if v_mag is not None else b_mag,
            size_arcmin=_float(row.get("MajAx")), messier=messier, common_name=bool(common),
            constellation=(row.get("Const") or "").strip(),
            aliases=tuple(dict.fromkeys(a for a in aliases if a and a != name)),
            distance_ly=distance_ly(_float(row.get("Pax")), _float(row.get("Redshift"))),
        ))
    return out


_STAR_TAIL = re.compile(
    r"(?P<mag>-?\d+\.\d+|_)\s+(?P<band>\S+)\s+(?P<hip>\d+|_)\s+(?P<hd>\d+|_)\s+"
    r"(?P<ra>\d+\.\d+)\s+(?P<dec>[-+]?\d+\.\d+)\s+\d{4}-\d{2}-\d{2}")
_CONSTELLATION = re.compile(r"\s([A-Z][a-z]{2})\s")


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
