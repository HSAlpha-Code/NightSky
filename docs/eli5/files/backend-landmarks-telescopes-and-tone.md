# The Space-Telescope Stitcher & Brightness Tamer (`backend/landmarks/mast.py`, `mosaic.py`, `tone.py`)

**Files covered in this guide:**
- `backend/landmarks/mast.py`
- `backend/landmarks/mosaic.py`
- `backend/landmarks/tone.py`

---

## Role
In our Backstage Astronomy Lab, these three files are the **Space-Telescope Darkroom Artists** — they check whether **James Webb** or **Hubble** photographed an object, stitch razor-sharp telescope tiles seamlessly onto a colored sky backdrop, and dim blindingly bright cores so delicate dust lanes shine through!

## Why They Exist
Raw space-telescope archives have three tough problems:
1. Searching NASA's archive (`MAST`) takes 10–30 seconds, which would freeze the app if done while you wait for pins.
2. Public Hubble/Webb tile maps are black-and-white patchworks where neighboring exposures have mismatched brightness squares, and stray parallel frames sometimes sit off to the side without actually covering the target.
3. Bright nebulae (like Orion's core) blow out to solid white on photographic plates.
These three files solve all three problems!

## What's Inside
- **`mast.py` (The Background Scout)**: Uses a background worker pool (`ThreadPoolExecutor`) to ask STScI's **MAST** *(Mikulski Archive for Space Telescopes)* whether JWST or Hubble images exist near a deep-sky object, skipping calibration dark/flat frames. Never makes `/api/landmarks` wait — returns `None` ("still checking") first and caches answers for 30 days so markers turn gold once ready!
- **`mosaic.py` (The Seamless Telescope Mosaic Builder)**:
  - `locate()`: Takes a fast `192×192` preview look at ESASky's JWST (`NIRCam`, `MIRI`) or Hubble (`ACS`, `WFC3`, `WFPC2`) tiles, verifying that the telescope **actually imaged the object's center** (`covers_target`) and covers **at least 12%** of the framed box (`MIN_COVERAGE = 0.12`) — rejecting stray off-target frames.
  - `layer_detail()` & `compose()`: Erodes ugly detector borders, uses a **white top-hat filter** *(an image-math trick that keeps fine stars and filaments while subtracting flat background squares)* so overlapping telescope pointings leave zero visible seams, tints the detail (warm gold-amber for infrared Webb, cool blue-white for optical Hubble), and screen-blends it onto the ground survey's color!
- **`tone.py` (The Sunglasses / Highlight Compressor)**: Detects when an image is over-exposed or "burnt out" (solid featureless white) and applies a smooth **gamma & soft-knee curve** *(dimming blinding highlights gently while keeping natural color ratios)* so glowing cores show structure instead of a white blob.

## Talks To
- Called by `backend/landmarks/services.py`.
- Calls `hips_render.sample()` (`backend/providers/hips_render.py`), `http_post()` (`backend/config/http.py`), and `open_image()` (`backend/config/images.py`).

---

## Important Code Blocks

### 1. Non-Blocking Background Checks for Gold Markers
**File:** `backend/landmarks/mast.py` (`status`)
```python
def status(landmark) -> dict | None | bool:
    cached = cache.get(_key(landmark.id))
    if cached is not None:
        return False if cached == NO_PREVIEW else cached
    with _pool_lock:
        if landmark.id in _pending or len(_pending) >= settings.MAST_MAX_PENDING:
            return None
        _pending[landmark.id] = now
    _executor().submit(_run, landmark.id, landmark.ra, landmark.dec, search_radius(landmark.size_arcmin))
    return None
```
- **In plain words:** Check our memory cubby first. If we already know whether Webb/Hubble photographed this nebula, answer instantly! If not, hand a sticky note to a background helper thread to go ask NASA while we immediately reply `None` ("still checking") so the user's sky pins appear in milliseconds instead of waiting 20 seconds.
- **Why it matters:** Keeps the `"Your sky"` screen super fast; the phone simply checks back a few seconds later (`SessionNotifier._loadLandmarks`) to turn grey rings into gold rings.
- **What goes in / what comes out:** A `Landmark` record → cached preview dict (`True`), `False`, or `None` (pending).

### 2. Rejecting Stray Off-Target Frames & Removing Patchwork Squares
**File:** `backend/landmarks/mosaic.py` (`covers_target` & `layer_detail`)
```python
mask = binary_erosion(mask, iterations=max(2, round(sigma / 3)))
t = gaussian_filter(grey.astype(np.float32), 0.8)
size = max(5, int(sigma) | 1)
detail = white_tophat(np.where(mask, t, 0.0), size=size) * mask
...
edge_fade = np.clip((den - 0.6) * 3.0, 0, 1) ** 2
return np.tanh(detail / max(peak, 1.0) * 1.5) * edge_fade
```
- **In plain words:** After `covers_target` confirms the telescope really aimed at our object (and covers ≥12% of the frame), `layer_detail` trims noisy chip edges, subtracts each exposure's flat grey background so overlapping camera squares vanish completely, and feathers the outer boundary smoothly into the surrounding sky!
- **Why it matters:** Raw space-telescope tile maps look like a harsh greyscale checkerboard. This darkroom magic turns them into a seamless, natural-color cosmic portrait — and refuses to fake a picture when the telescope missed the target.
- **What goes in / what comes out:** Greyscale telescope tile array + footprint mask → normalized `0..1` fine-structure detail map.

### 3. Putting "Sunglasses" on Blinding Nebula Cores
**File:** `backend/landmarks/tone.py` (`_compress`)
```python
gamma = float(np.clip(np.log(TARGET_MEDIAN) / np.log(med), 1.0, MAX_GAMMA))
y = x ** gamma
knee = 0.65
over = np.clip(y - knee, 0, None)
y = np.where(y > knee, knee + 0.29 * np.tanh(over / 0.29 * 1.2), y)
out = rgb * (y * 255.0 / np.maximum(lum, 1.0))[..., None]
```
- **In plain words:** When a bright star or nebula core washes out the frame, gently pull down the overall brightness (`gamma`) and softly roll off the top 35% of highlights (`tanh` soft knee), scaling Red, Green, and Blue together so warm or blue star halos keep their true colors instead of turning muddy grey.
- **Why it matters:** Lets you actually see stars and dust filaments inside bright centers like the Orion Nebula.
- **What goes in / what comes out:** Over-exposed RGB pixel grid → balanced 8-bit RGB pixel grid.
