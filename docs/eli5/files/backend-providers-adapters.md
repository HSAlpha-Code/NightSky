# The Sky Map Printing Machines (`backend/providers/hips2fits.py`, `hips_render.py`, `skyview.py`)

**Files covered in this guide:**
- `backend/providers/hips2fits.py`
- `backend/providers/hips_render.py`
- `backend/providers/skyview.py`

---

## Role
In our Backstage Astronomy Lab, these three files are the **Specialized Printing Presses** that talk to world astronomy archives — or stitch sky tiles right inside our own lab if an outside archive can't be reached!

## Why They Exist
Different sky surveys live on different continents in completely different formats. Without these adapters, NightSky couldn't turn raw **HiPS** *(Hierarchical Progressive Surveys — a giant zoomable patchwork quilt of the whole sky split into numbered square tiles, like Google Maps but for space)* or NASA SkyView plates into a tilted rectangle that lines up with your phone photo.

## What's Inside
- **`hips2fits.py` (The Strasbourg Printer + Mirror Switch)**: Asks the CDS `hips2fits` service in France to cut out a `DSS2 Color` JPEG. Because some internet providers have trouble reaching Strasbourg, if CDS times out, it immediately marks CDS down for 2 minutes and hands the job to `hips_render.py` using the European Space Agency's (`ESASky`) tile mirror in Spain!
- **`hips_render.py` (Our In-House Tile Stitcher)**: Builds a custom **TAN projection** *(gnomonic camera-style flat view of a curved sphere, matching how a phone camera lens sees the sky)* grid using `astropy`, calculates which **HEALPix** *(a clever math grid that divides a sphere into equal-area diamond tiles)* squares cover every pixel, downloads up to 96 tiles in parallel, and paints the rotated sky picture locally. Also powers Hubble and Webb tile sampling in `mosaic.py`!
- **`skyview.py` (The NASA SkyView Printer)**: Talks to NASA's Goddard Space Flight Center to render 3-channel RGB color composites of Axel Mellinger's wide Milky Way panorama. Includes a smart retry loop because NASA SkyView sometimes returns an HTML `"Too Many Processes"` web page with HTTP status `200` when lots of astronomers query it at once!

## Talks To
- Called by `backend/providers/services.py` (and `hips_render.sample()` is also called by `backend/landmarks/mosaic.py`).
- Uses `backend/config/http.py` and `backend/config/images.py`.

---

## Important Code Blocks

### 1. Automatic Failover From CDS France to Local ESA Tile Stitching
**File:** `backend/providers/hips2fits.py` (`Hips2FitsProvider.fetch_cutout`)
```python
if not cds_down:
    try:
        return self._fetch_cds(*args)
    except ProviderError as exc:
        if "HTTP 4" not in str(exc):
            cache.set(CDS_DOWN_KEY, True, settings.PROVIDER_DOWN_SECONDS)
        if not self.mirror:
            raise
return hips_render.render(self.mirror, self.mirror_max_order, *args)
```
- **In plain words:** First try asking the French `hips2fits` server to cut the image for us. If it is unreachable, put up a 2-minute detour sign (`hips2fits_cds_down`) and immediately stitch the exact same `DSS2 Color` picture ourselves from the European Space Agency's backup tile server!
- **Why it matters:** Users get genuine `DSS2 Color` images reliably even when one whole astronomy data center is unreachable.
- **What goes in / what comes out:** `(ra, dec, fov, rotation, width, height)` → JPEG bytes of `DSS2 Color`.

### 2. Mapping Every Output Pixel to a Sky Quilt Tile (`HEALPix` Bit Unpacking)
**File:** `backend/providers/hips_render.py` (`_sample`)
```python
lon, lat = w.wcs_pix2world(cols, height_px - 1 - rows, 0)
order = choose_order(fov_deg, width_px, max_order)
nside = 2 ** order * TILE_WIDTH
ipix = lonlat_to_healpix(lon * u.deg, lat * u.deg, nside, order="nested").astype(np.int64)
tiles = ipix // (TILE_WIDTH * TILE_WIDTH)
tile_rows, tile_cols = tile_rows_cols(ipix - tiles * TILE_WIDTH * TILE_WIDTH)
```
- **In plain words:** For every single pixel `(col, row)` in our final picture, figure out what sky longitude and latitude `(lon, lat)` it points to, pick the zoom level (`order`) sharp enough for that field size, look up which numbered 512×512 sky tile holds that spot, and pluck the exact pixel color out of that tile!
- **Why it matters:** Lets NightSky project curved sky tiles onto any camera angle and tilt — for both ground surveys and Hubble/Webb space-telescope mosaics.
- **What goes in / what comes out:** Tile server URL + target sky camera geometry → `(rgb pixel array, has_data mask, any_tile flag)`.

### 3. Catching NASA SkyView's Polite "Too Busy" Disguise
**File:** `backend/providers/skyview.py` (`_query` & `_is_busy`)
```python
def _is_busy(resp) -> bool:
    ctype = resp.headers.get("content-type", "")
    return not ctype.startswith("image/") and "too many processes" in resp.text.lower()
```
- **In plain words:** Even when NASA's SkyView server is overloaded, it still stamps `"200 OK"` on the envelope while tucking a `"Too Many Processes"` apology note inside instead of a picture. This check reads the note and waits 1.5–3 seconds to try again.
- **Why it matters:** Without checking the content inside, the lab would mistake `"200 OK"` for success or give up immediately instead of waiting two seconds for a free slot.
- **What goes in / what comes out:** HTTP response from SkyView → `True` (wait and retry) or `False` (ready to read).
