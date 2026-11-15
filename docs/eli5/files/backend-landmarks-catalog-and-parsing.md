# The Tour Guide's Sky Encyclopedia (`backend/landmarks/catalog.py`, `parsing.py`, `fetch_catalogs.py`)

**Files covered in this guide:**
- `backend/landmarks/catalog.py`
- `backend/landmarks/parsing.py`
- `backend/landmarks/management/commands/fetch_catalogs.py`

---

## Role
In our Backstage Astronomy Lab, these files are the **Tour Guide's Master Encyclopedia** — they read thousands of famous nebulae, galaxies, star clusters, and named stars into memory and work out which ones sit inside your photo without crowding each other!

## Why They Exist
Without these files, NightSky could show you a pretty sky picture, yet you would have no idea *what* any glowing cloud or bright star is called, how far away it is, or where to tap on screen.

## What's Inside
- **`parsing.py` (The Encyclopedia Translator)**:
  - Reads **OpenNGC** *(an open-source catalog of ~14,000 deep-sky objects)* CSV files, tossing out historical plate mistakes or duplicate entries while keeping classic **Messier** *(a famous 18th-century list of 110 bright sky treasures like M31 and M42)* targets.
  - Calculates approximate distances in **light-years** *(how far light travels in one year — about 9.46 trillion km)* from star parallax or galaxy redshift.
  - Parses official star names from both the classic IAU text table (`IAU-CSN.txt`) and the newer HTML table (`wgsn_html_to_csv`), merging them without duplicates.
- **`catalog.py` (The 3D Spotter & De-Clutterer)**:
  - Stores every object as a 3D unit arrow `(x, y, z)` on a sphere so a single fast math operation (**dot product** — *multiplying arrows to measure the angle between them*) finds every object near your camera's aim in milliseconds!
  - Projects hits onto `(0..1, 0..1)` image coordinates using `output_wcs`, ranks them by importance (`priority()` — Messier and bright named objects first!), and drops markers closer than `3.5%` of screen width (`MIN_SEPARATION`) so pins never pile on top of each other.
- **`fetch_catalogs.py`**: A terminal command (`python manage.py fetch_catalogs`) that downloads fresh OpenNGC and IAU star tables into `backend/data/catalogs/`.

## Talks To
- Called by `backend/landmarks/services.py` (`landmarks_in_field` and `landmark_detail`).
- Uses `output_wcs` from `backend/providers/hips_render.py` so marker `(x, y)` positions line up pixel-for-pixel with the sky image!

---

## Important Code Blocks

### 1. Ranking Objects & Keeping Pins From Overlapping
**File:** `backend/landmarks/catalog.py` (`Catalog.query`)
```python
near = np.nonzero(self._xyz @ centre >= math.cos(math.radians(radius)))[0]
wcs = output_wcs(ra, dec, fov_deg, rotation_deg, width, height)
px, py = wcs.wcs_world2pix(self._ra[near], self._dec[near], 0)
fx, fy = (px + 0.5) / width, 1 - (py + 0.5) / height
...
for _, hit in candidates:
    if len(chosen) >= max_markers:
        break
    if all(math.hypot(hit.x - c.x, (hit.y - c.y) * aspect) >= MIN_SEPARATION for c in chosen):
        chosen.append(hit)
```
- **In plain words:** First grab all sky objects inside a circle around where the camera aimed, convert their sky positions into `(0..1)` screen fractions from the top-left corner, sort them so famous sights like the Great Orion Nebula come before tiny faint galaxies, and place up to 20 pins while skipping any pin that sits right on top of an already-placed pin.
- **Why it matters:** Busy sky regions like Orion or Sagittarius contain hundreds of catalog entries. Without priority sorting and spacing rules, your screen would be buried under an unreadable blob of circles!
- **What goes in / what comes out:** Camera sky aim `(ra, dec, fov, rotation, aspect)` → list of spaced-out `Hit(landmark, x, y)` pins + total count.

### 2. Estimating Distance From Parallax or Galaxy Redshift
**File:** `backend/landmarks/parsing.py` (`distance_ly`)
```python
def distance_ly(parallax_mas: float | None, redshift: float | None) -> float | None:
    if parallax_mas and parallax_mas > 0.05:
        return round(1000 / parallax_mas * LY_PER_PC, -1)
    if redshift and redshift > 0.002:
        return round(redshift * 299792.458 / HUBBLE_CONSTANT * LY_PER_MPC, -5)
    return None
```
- **In plain words:** For nearby star clusters inside our Milky Way, compute distance from **parallax** *(how much the object appears to wobble as Earth orbits the Sun)*. For distant galaxies millions of light-years away, compute distance from **redshift** *(how much the universe's expansion stretches their light)*.
- **Why it matters:** Gives stargazers an awe-inspiring sense of scale — like seeing that the Pleiades are `440 light-years` away while a galaxy is `25 million light-years` away!
- **What goes in / what comes out:** Optional parallax or redshift from OpenNGC → rounded distance in light-years (or `None`).
