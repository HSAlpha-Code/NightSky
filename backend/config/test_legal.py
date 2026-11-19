from django.test import SimpleTestCase


class LegalDocumentTests(SimpleTestCase):
    def test_public_policy_is_html_and_needs_no_login(self):
        response = self.client.get("/privacy/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response["Content-Type"], "text/html; charset=utf-8")
        content = b"".join(response.streaming_content).decode()
        self.assertIn("NightSky Privacy Policy", content)
        self.assertIn("hemantsharma.devs@gmail.com", content)
        self.assertNotIn("<script", content)

    def test_adapted_catalogue_is_public(self):
        response = self.client.get("/legal/sky_catalog.json")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response["Content-Type"], "application/json")

    def test_legal_document_does_not_accept_uploads(self):
        self.assertEqual(self.client.post("/privacy/", {}).status_code, 405)
