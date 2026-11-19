# Survey and catalogue rights research

Reviewed 2026-11-17 using TinyFish search and fetch. This records published evidence and a CDS response supplied by the user, not a legal opinion. No image files or providers were changed.

CDS confirmed in a response supplied by the user that Aladin HiPS are offered under ODbL, subject to the original data producers' rights, attribution, and applicable share-alike obligations. This confirms CDS's general terms; it does not settle how those obligations apply to this app's cutouts and cache. In a separate response supplied by the user, MAST confirmed DSS use under CC BY-NC-SA 4.0 for scientific, educational and nonprofit purposes, excluding for-profit use. Preserve both original responses privately and satisfy the applicable licence conditions.

## DSS2 / DSSColor: conditional noncommercial reuse; commercial clearance pending

The app uses CDS/P/DSS2/color and an ESA DSSColor mirror. The current [MAST data-use policy](https://archive.stsci.edu/publishing/data-use) specifically excludes DSS from its general public-domain treatment. It describes DSS and derived products as CC BY-NC-SA 4.0 and permits scientific, educational, and nonprofit uses, including software applications. A for-profit release needs additional permission; a free download does not by itself establish noncommercial use. Noncommercial redistribution must still meet attribution and share-alike terms.

The [older STScI data-use notice](https://gsss.stsci.edu/zzzoldwebsite/dss/data_use.html) also directs commercial users to obtain permission from the copyright holders. Prefer the current MAST policy for the published license and retain the older notice as corroborating history.

[Actual DSSColor properties](https://skies.esac.esa.int/DSSColor/properties) identify STScI/NASA source data, CDS colouring/HEALPix processing, and CNRS/Unistra copyright for the HiPS. They link to [DSS plate copyrights](https://archive.stsci.edu/dss/copyright.html). That page distinguishes northern Caltech plates, southern UK/AAO plates, and residual AURA material; applicable plate-specific notices occur in FITS headers. [Full acknowledgements](https://archive.stsci.edu/dss/acknowledging.html) cover STScI production, Palomar/Oschin and UK Schmidt photographic material, and funding/institutions. The app's generic provider credit should link to those acknowledgements and preserve the relevant notices; a NASA credit alone is inadequate. Clarify application of CDS terms to the intended processing and caching.

## ESASky Hubble/JWST scientific HiPS: precise reuse terms pending

The backend's `landmarks/mosaic.py` renders scientific HiPS, applies mission colour palettes, and blends survey backgrounds. These are distinct from individual publicity images on esahubble.org and esawebb.org. Do not automatically apply those publicity sites' CC BY 4.0 policies to these tiles.

The actual [HST ACS](https://skies.esac.esa.int/HST/ACS/properties), [WFC3](https://skies.esac.esa.int/HST/WFC3/properties), and [WFPC2](https://skies.esac.esa.int/HST/WFPC2/properties) metadata name ESA/ESDC as HiPS copyright holder and eHST/ESA for observations. [JWST NIRCam](https://skies.esac.esa.int/JWST/NIRCam_Imaging/properties) and [MIRI](https://skies.esac.esa.int/JWST/MIRI_Imaging/properties) metadata contain commented copyright placeholders rather than a populated reuse license. NIRCam acknowledges original data from the European JWST Archive at ESA/ESAC.

Their public/clonable status is not, by itself, an explicit grant covering every commercial derivative use. [ESA's contribution guidance](https://cosmos.esa.int/web/esdc/esasky-contributing) confirms that each properties file carries source/copyright information and describes clonable status as enabling ESASky mirroring. [MAST](https://archive.stsci.edu/publishing/data-use) says most of its own data are CC0, with some community products under CC BY, but that is not sufficient evidence to assign a license to ESA's separately processed HiPS. Obtain ESA/ESDC confirmation for rendering, recolouring, blending, caching, and app distribution, and record required eHST/eJWST credits. Keep any DSS or Mellinger background restrictions in the combined product's assessment.

## IAU/WGSN names: narrow public-domain statement verified

The [IAU WGSN scientific-objectives page](https://iau.org/WG280/WG280/Scientific%20Objectives.aspx?code=280&hkey=fad94c19-f0df-4c52-bad1-bf403f168c46) identifies the [Exopla IAU catalogue](https://exopla.net/star-names/modern-iau-star-names/) as its catalogue. The catalogue explicitly states that IAU star names are scientific standards, are public domain, and do not require intellectual-property licensing. It separately says its explanatory texts and images normally use CC BY, with some CC0 exceptions.

Therefore the app's use of approved names can cite that public-domain statement; do not extend it to copied etymologies, descriptions, artwork, or all other table data. Preserve the separate BSD obligations for d3-celestial-derived star records and confirm the generator takes names/designations rather than explanatory prose. No permission is asserted for material outside that narrow scope.

## Next actions

- Retain existing images and data while documenting pending clearance.
- Record commercial/noncommercial distribution and monetization plans before accepting DSS terms.
- Obtain and preserve DSS/HiPS permissions where needed; do not label an unconfirmed request as obtained.
- Add per-provider links, exact applicable attribution, and modification descriptions to notices shipped with the app.
- Verify each actual provider layer independently; publicity-image licenses do not replace archive-layer checks.

Research coverage: 37 unique URLs appeared in three search result sets or were fetched; the supporting primary URLs are linked above. The IAU legacy buying-stars URL returned page_not_found, so the working WGSN and Exopla sources support the names finding.
