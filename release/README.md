# NightSky release preparation

Publisher: **Hemant Sharma**, India. Public contact: **hemantsharma.devs@gmail.com**.
First release: free, no ads, purchases, accounts or analytics; not child-directed.
Images are retained as requested. **Public release is blocked pending the items below.**

## Start here

1. Read [image/data rights findings](rights-research.md), [survey terms](survey-rights-research.md), and the per-file [rights register](rights-register.json). Resolve the named pending items; do not treat an evidence URL as permission.
2. Confirm deployed hosting location, request/error-log retention, temporary-file handling, diagnostics and subprocessors. Fill [publisher.json](publisher.json), then review the generated privacy policy and terms for the selected countries.
3. Review [market/legal notes](legal-market-notes.md), [Play Console worksheet](play-console.md), [permission request drafts](permission-requests.md), and [manual device checks](device-checks.md).
4. Review [dependency inventory](dependency-inventory.json) and icon ownership. Installed dependency licences are inventoried, not certified. Confirm trademark/name clearance and the final country list. Preserve evidence privately where appropriate.
5. Record an asset as `cleared` only after verifying its exact file/hash, source, full credit, licence, modifications and required acknowledgements. Keep privately obtained permission originals; use a non-secret reference in the register. Do not paste personal correspondence or keystore passwords into tracked files.
6. Set review booleans in publisher.json only after doing the associated work. Regenerate documents, run checks, then review the concrete AAB before uploading.

```powershell
# From C:\Projects\NightSky
python tools/release.py render
python tools/release.py check
powershell -ExecutionPolicy Bypass -File tools/preflight.ps1
# Once all release blockers are resolved:
powershell -ExecutionPolicy Bypass -File tools/preflight.ps1 -BuildBundle
```

The normal Gradle `preReleaseBuild` runs `check --for-build` and requires a real
release keystore. This variant still requires legal/privacy/rights reviews but lets
you create a candidate before final device/16 KB tests. After testing the resulting
artifact, the full `check` must pass before publication. Document draft status depends
on the legal/privacy inputs, not final hardware tests, so testing does not require
changing the policy inside an already tested bundle. Debug builds/tests remain
available. Python must be on PATH.
The gate checks recorded inputs and known assets; it cannot grant rights, verify a
human attestation, guarantee legal compliance, or replace Play's review.

## Documents ready to review and deploy

Bundled legal text: `app/assets/legal/`. Full BSD, OpenNGC CC BY-SA and project MIT
notices are shipped; Flutter supplies dependency notices to its licence screen.
Public HTML and adapted catalogue: `backend/legal/`. The existing backend serves:

- `/privacy/` — Play Console privacy policy URL, after completing and deploying it.
- `/terms/` — Terms of use, after review.
- `/credits/` — image/data credits.
- `/legal/sky_catalog.json` — exact copy of the bundled adapted catalogue, with component licences described in credits.

`python tools/release.py render` updates both document copies and the public catalogue.
They are intentionally labelled **DRAFT** while release inputs remain incomplete.
The production backend currently deployed is not changed by editing these files.
Do not submit the existing public URL as final until the reviewed document is deployed
and checked publicly without login, region restrictions or a PDF viewer.

## Items only the publisher/account owner can settle

- Axel Mellinger/photographer permissions and ambiguous survey terms, unless replacing assets.
- Trademark clearance and ownership/provenance of the supplied icon and other contributions.
- Actual hosting account retention/processing settings, provider contracts and privacy rights process.
- Trader/business classification, legal address/phone, developer identity/payment verification.
- Exact distribution countries supported for an India-based publisher under current trade rules.
- Play account/testing eligibility, tester recruitment, account declarations and final age groups.
- Real-device/16 KB results, final store screenshots and submission approval.

No messages to rights holders have been sent. No Play submission, production deployment,
legal signature, fee payment or country selection has been performed.

## Later: support page

A future “Support me” page needs a fresh Play payments-policy review for the exact flow.
A personal tip, charitable donation and purchase unlocking functionality are different
arrangements. Do not add an external payment link or describe tips as charitable tax-
deductible donations by default. Update policy, Data Safety and store declarations if
payment/analytics SDKs or accounts are added. No payment UI or SDK is included now.
