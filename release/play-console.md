# Play Console worksheet — publisher completion required

Prepared for Hemant Sharma (India), first release without ads, accounts, purchases or analytics.
This is a worksheet, not answers already submitted to Google.

## Listing draft

- App name: NightSky — check trademark/name availability first.
- Short description: Explore the night sky with an offline star map and astronomical images.
- Category candidate: Education; confirm against the finished app and intended audience.
- Contact email: hemantsharma.devs@gmail.com
- Privacy URL: https://nightsky-backend.vercel.app/privacy/ — prepared route, must deploy final policy.
- Terms URL: https://nightsky-backend.vercel.app/terms/ — prepared route, must review/deploy.
- Ads: no, provided the final binary and all SDKs remain as reviewed.
- In-app purchases/accounts: none in this version.

Long description draft:

> Explore the night sky with NightSky. Use Sky View to find stars, constellations and
> Solar System objects with a star map that works offline. Choose your observing
> location manually or allow foreground location access to align the view.
>
> In camera mode, capture a sky photograph and send it to the selected server to
> identify the field and retrieve astronomical survey imagery. Online close-ups and
> curated highlights let you explore observations from astronomical telescopes.
>
> Survey images are separate observations, not extra detail captured by your phone.
> Pointing and identification can be approximate; online features need internet access
> and depend on source coverage. Camera uploads are explained before you agree.

Use this description only once source rights and image/object assignments are resolved.
Do not claim an official NASA/ESA affiliation or worldwide legal clearance.

## Data Safety: audit before answering

| Data/use | Repository observation | Console action |
|---|---|---|
| Photographs | JPEG sent to selected backend for plate solving | Evaluate Photos collection, purpose = app functionality. Verify ephemeral criteria against temporary disk files, logs, traces and hosting. |
| Location | Available latitude/longitude/altitude sent with photo; location also used locally in Sky View | Evaluate precise/approximate categories from actual accuracy. Collection is optional when permission is denied; don't conflate local-only use with server upload. |
| Time/orientation/FOV | Uploaded as photograph metadata | Describe in privacy policy; map to current form definitions rather than inventing a data category. |
| IP/request metadata | Visible to backend/host; used in anonymous rate limiting | Inspect actual host logs, retention and whether any identifiers/diagnostics categories apply. IP is not automatically a persistent device identifier. |
| Preferences/last location | Stored locally, Android backup disabled in this change | Local-only processing generally does not count as off-device collection. Verify final manifest and SDK behaviour. |
| Analytics/ads/account data | No such SDK/features found or requested for first release | Re-check final dependency graph and hosting integrations before confirming absence. |
| Service providers | Vercel and configured backend; external astronomical services receive sky-query parameters | Determine sharing exclusions only after reviewing processor roles/contracts and actual payloads. |

Ephemeral processing still needs assessment in the questionnaire. It is narrowly
defined as memory-only real-time processing; temporary files or retained request
logs may change the answer. Do not claim “no data collected” solely because there
is no database/account/advertising. Do not claim “not shared” without evaluating
the provider rules. All selected countries' required disclosures still apply.

Source: https://support.google.com/googleplay/android-developer/answer/10787469?hl=en
User Data: https://support.google.com/googleplay/android-developer/answer/10144311?hl=en

## Account and policy declarations

- Select individual/organisation truthfully and complete developer verification. If required, complete physical Android-device verification using Google's flow.
- Confirm trader/non-trader classification based on actual activity, not simply the absence of a price. See legal-market-notes.md. Provide the required public details through Console, not this repository.
- Choose an explicit country/region list from Google's currently supported distribution markets. “Everywhere except sanctioned countries” is an intention, not a compliance determination; don't use a guessed sanctions blacklist.
- Select age groups based on product intent and marketing. General audience does not automatically mean “all ages.” User has confirmed the app is not child-directed.
- Complete IARC content rating and the current app-content declarations. Use the actual imagery/content; no rating is assigned by this worksheet.
- No app login exists. All review features must be accessible; explain any backend/network prerequisites.
- If the personal developer account was created after 13 November 2023, complete the applicable 12-testers/14-continuous-days closed test and apply for production access.
- No account-deletion flow is needed for a version with no account creation; privacy/data-request handling still needs to work.

Testing: https://support.google.com/googleplay/android-developer/answer/14151465?hl=en

## Binary and store assets

- Confirm permanent application ID `com.nightsky.night_sky` before the first upload.
- Choose Play App Signing; back up the upload keystore and key.properties privately. Never commit key/password material. Release builds no longer fall back to debug signing.
- The installed Flutter 3.47.4 SDK sets compile/target API 36 and NDK 28.2.13676358. Inspect the actual final merged manifest/AAB and satisfy Console's then-current requirements.
- Complete device-checks.md, inspect 16 KB alignment for **all** native libraries, and review Play's pre-launch report. Source-level SDK versions alone do not prove 16 KB compatibility.
- Build an AAB, not just an APK. Increase `version`'s `+N` for every uploaded build. Initial version is currently 1.0.0+1; don't increment automatically without checking previously uploaded version codes.
- Prepare a 512×512 store icon and 1024×500 feature graphic from artwork whose rights are verified. Capture real release-build screenshots (phone and other supported form factors); label survey replacement imagery clearly.
- Upload first to internal testing, then closed testing where applicable, review crashes/ANRs/policy warnings, and choose staged rollout for production.

Target API: https://support.google.com/googleplay/android-developer/answer/11926878?hl=en
16 KB: https://developer.android.com/guide/practices/page-sizes
