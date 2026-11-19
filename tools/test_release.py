"""Tests for the release gate's fail-closed behaviour. No builds or network needed."""
import copy
import unittest
from unittest.mock import patch

from tools.release import CONFIG, check, documents, input_errors, inventory, read_json


class ReleaseInputTests(unittest.TestCase):
    def test_current_unverified_inputs_are_blocked_and_marked_draft(self):
        config = read_json(CONFIG)
        # Force an unverified condition so this remains valid once the real file is completed.
        config["production_retention_verified"] = False
        self.assertTrue(input_errors(config))
        self.assertIn("DRAFT - NOT APPROVED", documents(config)["privacy"])

    def test_retention_attestation_alone_does_not_complete_missing_identity(self):
        config = copy.deepcopy(read_json(CONFIG))
        config["production_retention_verified"] = True
        config["support_email"] = ""
        self.assertTrue(any("email" in e for e in input_errors(config)))

    def test_invalid_policy_url_is_blocked(self):
        config = read_json(CONFIG)
        config["privacy_policy_url"] = "http://localhost/privacy"
        self.assertTrue(any("HTTPS" in e for e in input_errors(config)))

    def test_changed_credited_work_cannot_reuse_previous_approval(self):
        rows = inventory()
        image = next(r for r in rows if "curated_bundle/images/" in r["id"])
        image["credit"] = "Different author"
        with patch("tools.release.inventory", return_value=rows):
            errors = check(read_json(CONFIG))
        self.assertIn(f"rights record changed/missing credit: {image['id']}", errors)

    def test_new_image_requires_its_own_record(self):
        rows = inventory() + [{"id": "new-image.webp", "sha256": "changed"}]
        with patch("tools.release.inventory", return_value=rows):
            errors = check(read_json(CONFIG))
        self.assertIn("rights unresolved: new-image.webp", errors)

    def test_candidate_build_does_not_require_testing_an_artifact_that_does_not_exist_yet(self):
        config = read_json(CONFIG)
        config["device_and_16kb_tests_passed"] = False
        config["production_retention_verified"] = False
        full = input_errors(config)
        candidate = input_errors(config, for_build=True)
        self.assertTrue(any("device_and_16kb" in e for e in full))
        self.assertFalse(any("device_and_16kb" in e for e in candidate))
        self.assertTrue(any("production_retention_verified" in e for e in candidate))


if __name__ == "__main__":
    unittest.main()
