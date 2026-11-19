# Remaining actions before publication

All existing image files are kept. Twelve curated images now have matching sources,
published CC BY 4.0 policies, and displayed credits/licence/change notices. The items
below are unresolved; this is not a claim that every pending work is prohibited.

| Image/source | What is unresolved | Action |
|---|---|---|
| Mellinger Milky Way panorama: `app/assets/sky/mellinger_east.webp`, `mellinger_west.webp`, plus online Mellinger cutouts | Published permission does not establish app-store redistribution rights | Obtain Axel Mellinger's written licence covering transformed/bundled images, server delivery, caching and intended markets; ask separately about later tips/monetisation. Draft in permission-requests.md. |
| Double Cluster: `ae32c697f819496faf073faf296530dd.jpg` | Mårten Frosth granted permission with credit and link; bundled credits and modification description need reconciliation | Preserve the permission privately, update the bundled credit and link, and verify the modification description. |
| Andromeda: `bb5491dc42d54832810b8d4dcc09c392.jpg` | ESA's general CC BY policy supports reuse, but the older asset bears Robert Gendler copyright | Preserve © 2002 R. Gendler credit; clarify with ESA whether this exact image has any exception. Copyright attribution alone does not prove it is prohibited. |
| Online DSS2 / DSSColor | MAST confirmed CC BY-NC-SA 4.0 for scientific, educational and nonprofit use; CDS confirmed general HiPS terms, subject to original data rights | Preserve both replies, implement required notices and share-alike obligations, and clarify ODbL obligations for cutouts and caches. For-profit use is excluded. |
| Online Hubble and Webb scientific tiles | Scientific ESASky HiPS licensing was not established by the press-gallery CC licences | Ask ESA/ESDC about actual layer IDs, recolouring, blended backgrounds, rendering/caching and redistribution; record required credits and terms. |

The full per-image evidence and policy links are in [rights-research.md](rights-research.md)
and [survey-rights-research.md](survey-rights-research.md). [rights-register.json](rights-register.json)
contains file hashes and actionable statuses. Never change `pending` to `cleared` just
to make a build pass.

## Metadata corrected without replacing images

- Record 12 was labelled Pleiades but contains **NGC 6139**. Its object ID/coordinates/name now match the photograph.
- Record 13 was labelled Hercules/M13 but contains **Messier 92 / NGC 6341**. Its association is corrected.
- Fixed IC 348's source URL in the wrong field, identified missing Ring/Helix source pages, and restored verified full credits.
- The curator now saves/exports licence URLs and change notices. An older local curator database must be migrated and have its metadata updated before another export, otherwise it can restore obsolete credits/associations. The release gate detects changed source/credit/licence fields. See local_tools/curator/README.md.

## Publisher/account work still needed

1. Verify actual Vercel deployment region, logs/traces/request-body capture, temporary-file deletion, retention and provider processing terms. Only repository code/configuration has been inspected; the policy deliberately leaves hosting details blank.
2. Review legal bases, international-processing safeguards, rights/complaint procedures and final market list. Complete the corresponding blank fields in publisher.json; obtain a focused legal review for worldwide distribution.
3. Confirm icon/contributor ownership and trademark clearance for NightSky. Dependency notices are inventoried and shipped; that does not settle provenance of supplied artwork/code.
4. Complete Play identity/trader details, precise country/age selections, Data Safety and content rating. Recruit testers if your account needs closed testing. No declarations have been submitted.
5. Complete physical-device and 16 KB checks, create final store screenshots/artwork from cleared assets, build/review the signed AAB, then deploy the final public policy and submit through Play.

Run `python tools/release.py check` for the current blockers. Documents are marked
DRAFT until required inputs/reviews are recorded. The default policy URL will not
serve the new document until the backend is deployed.
