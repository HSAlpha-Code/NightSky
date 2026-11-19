# Curated imagery rights research

Reviewed 2026-11-17. Existing images retained. This is an evidence register, not a legal opinion or permission obtained. `policy_verified` means an applicable published reuse policy and matching work were identified; the app must still satisfy attribution and modification notices.

## Critical findings

- Mellinger panorama remains pending written permission covering distributed apps, transformations and any commercial use. The [SkyView notice](https://skyview.gsfc.nasa.gov/blog/index.php/2009/12/16/mellinger-optical-survey/index.html) limits the available grant to research/personal noncommercial use.
- Double Cluster: Mårten Frosth granted permission in correspondence supplied by the user, requesting credit and a link to www.frosth.se. Update bundled credits and reconcile the modification description before marking the asset cleared.
- Pleiades record 12 contains NGC 6139, and Hercules/M13 record 13 contains Messier 92 (NGC 6341). Local images match their source previews closely; the object assignments are wrong. Correct metadata while keeping exact JPEGs.
- Missing Ring HST source is heic1310a and Ring JWST source is weic2320b, verified by local/source image comparison. Helix is a derivative crop/zoom of ESO eso1205a, visually matched.
- Andromeda matches heic0512d. ESA's blanket policy supports reuse unless otherwise stated; its old third-party copyright credit merits preserving and clarification. It is marked pending rather than permission obtained.

## Per-image source map

| Record | Object at start of audit | Verified matching source | License/policy status |
|---|---|---|---|
| 14 | C014 | [double-cluster-in-perseus](https://science.nasa.gov/image-detail/double-cluster-in-perseus/) | permission obtained; notice updates pending |
| 3 | IC0348 | [weic2619a](https://esawebb.org/images/weic2619a/) | policy_verified |
| 12 | Mel022 | [potw1826a](https://esahubble.org/images/potw1826a/) | pending_metadata_correction |
| 10 | NGC0224 | [heic0512d](https://esahubble.org/images/heic0512d/) | pending |
| 4 | NGC0602 | [weic2425a](https://esawebb.org/images/weic2425a/) | policy_verified |
| 9 | NGC1976 | [heic0601a](https://esahubble.org/images/heic0601a/) | policy_verified |
| 7 | NGC3372 | [carinanebula3](https://esawebb.org/images/carinanebula3/) | policy_verified |
| 8 | NGC4594 | [weic2427a](https://esawebb.org/images/weic2427a/) | policy_verified |
| 13 | NGC6205 | [potw1449a](https://esahubble.org/images/potw1449a/) | pending_metadata_correction |
| 5 | NGC6537 | [potm2510a](https://esawebb.org/images/potm2510a/) | policy_verified |
| 6 | NGC6611 | [weic2218a](https://esawebb.org/images/weic2218a/) | policy_verified |
| 1 | NGC6720 | [heic1310a](https://esahubble.org/images/heic1310a/) | policy_verified |
| 2 | NGC6720 | [weic2320b](https://esawebb.org/images/weic2320b/) | policy_verified |
| 11 | NGC7293 | [eso1205a](https://www.eso.org/public/images/eso1205a/) | policy_verified |

The machine-readable [source map](rights-research.json) contains exact credits, source and license URLs, match evidence, and proposed corrections. Research did not edit the manifest; the implementation subsequently applied the verified corrections while keeping all image bytes. See [remaining actions](remaining-actions.md) for the resulting status.

## Applicable public-image policies

- [ESA/Hubble](https://esahubble.org/copyright/) and [ESA/Webb](https://esawebb.org/copyright/): CC BY 4.0, complete unaltered credits visibly associated with each image, active links online, no implied endorsement; logos excluded.
- [ESO public media](https://www.eso.org/public/outreach/copyright/): CC BY 4.0 unless a specific exception is indicated; preserve full credit and indicate modifications.
- [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/): attribution, license link and change indication. Re-encoding/resizing alone is not evidence that new permission was obtained.
- Current curated captions are empty. Any future copied prose must receive its own source/license assessment.

## Object corrections from bundled OpenNGC

| Record | Correct object | RA (degrees) | Dec (degrees) |
|---|---|---|---|
| 12 | NGC 6139 | 246.91879166666666 | -38.84975 |
| 13 | NGC 6341 / Messier 92 | 259.2802916666667 | 43.13652777777778 |

Coordinates were converted from `backend/data/catalogs/NGC.csv`: 16:27:40.51, -38:50:59.1 and 17:17:07.27, +43:08:11.5. Preserve OpenNGC CC BY-SA attribution and data-license obligations.

## Scientific tiles and catalogues

See [survey-rights-research.md](survey-rights-research.md) for DSS noncommercial/share-alike restrictions, unresolved ESA scientific HiPS tile reuse terms, and the narrow public-domain statement for IAU approved names. Public-image CC BY policies must not be assumed to license scientific archive tiles.

## Verification limits

Source metadata were fetched with TinyFish. Local images and upstream preview JPEGs were compared read-only; originals were not changed. Most previews have mean RGB differences below 1/255 after resizing to a common comparison grid. Orion and Pillars versions differ more in colour/processing; Helix has a different crop/zoom. Those observations establish a matching work, not an exact transformation history. The source map deliberately records pending questions rather than asserting permissions.
