# Release-preparation validation — 17 November 2026

- Flutter static analysis: passed, no issues.
- Flutter unit/widget suite: passed, including upload-consent choices and visible licence/credit links with image details collapsed.
- Android debug APK: built successfully at `app/build/app/outputs/flutter-apk/app-debug.apk`. This is a development artifact, not cleared for public distribution.
- APK inspection: all six bundled legal files are present; Flutter's generated compressed package notices are present (about 1.35 MB uncompressed).
- Debug APK's seven 64-bit native libraries: ELF LOAD alignment is at least 16 KB. This does not verify the final release engine/bundle, ZIP alignment, Play delivery or execution on a 16 KB device; that manual release item remains open.
- Backend suite: 110 tests completed, 5 skipped because optional sample data is absent; no failures after fixing offline IERS freshness handling. The stale 30-day predictive-table check previously broke sensor pointing even though automatic IERS downloads are intentionally disabled; approximate sensor pointing now allows the bundled data and retains degraded-accuracy warnings.
- Django model/migration consistency: passed; new licence metadata migration is included. No production or local curator database was migrated.
- Release-gate tests: 6 passed, covering incomplete identity/retention, invalid policy URLs, changed author metadata, unregistered images, and creating a candidate before final device tests.
- Gradle `:app:verifyReleaseReadiness`: executed and rejected unresolved release inputs as intended; release signing has no debug-key fallback.
- Final `python tools/release.py check`: intentionally fails for the remaining rights, hosting/legal inputs, final country selection and manual reviews listed in remaining-actions.md. Generated legal documents are current and remain marked DRAFT.
- Image files remain unchanged. Source/credit/licence metadata and two incorrect object associations were corrected.

Existing Gradle/plugin deprecation warnings remain: some dependencies still use the
legacy Kotlin Gradle Plugin/AGP DSL. The current debug build succeeds; review plugin
compatibility before a future Flutter/AGP upgrade. Dependencies were not upgraded.

No production deployment, Play Console upload/declaration, external message or legal
permission request was sent. No trademark clearance or global legal certification is
claimed. The prepared policy URL is a route in the next backend deployment, not a
claim that the current public deployment already serves the new document.
