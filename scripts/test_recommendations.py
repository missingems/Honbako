"""Offline behavioral checks: no third-party or paid API calls."""
import copy
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import update_recommendations as rec


class RecommendationTests(unittest.TestCase):
    def setUp(self):
        self.seed = rec.load(rec.ROOT / "recommendations/seed.json")
        self.when = "2026-10-26T14:30:00Z"

    def test_seed_is_valid_and_has_only_official_series_links(self):
        rec.validate_feed(self.seed)
        self.assertEqual(len(self.seed["items"]), 19)
        self.assertTrue(all(i["popularity"]["rank"] is None for i in self.seed["items"]))

    def test_observations_match_author_dedupe_and_preserve_editorial_fallback(self):
        feed = rec.apply_observations(self.seed, rec.load(Path(__file__).parent / "fixtures/open_library.json"), self.when)
        self.assertEqual(feed["items"][0]["id"], "honbako:haikyu")
        self.assertEqual(feed["items"][0]["popularity"]["rank"], 1)
        self.assertEqual(feed["items"][1]["id"], "honbako:spy-x-family")
        self.assertEqual(feed["items"][1]["popularity"]["rank"], 4)
        self.assertEqual(len(feed["items"]), 19)
        self.assertEqual(feed["items"][-1]["popularity"]["metric"], "editorial-selection")
        self.assertEqual(self.seed["items"][0]["id"], "honbako:spy-x-family")

    def test_empty_or_unsafe_catalog_results_never_replace_feed(self):
        self.assertIsNone(rec.apply_observations(self.seed, {"docs": []}, self.when))
        self.assertIsNone(rec.apply_observations(self.seed, {"docs": [{"key": "/works/OL1W", "title": "Unreviewed Adult Title", "author_name": ["Unknown"], "trending_z_score": 99}]}, self.when))

    def test_missing_key_or_optin_never_calls_paid_api(self):
        with patch.object(rec, "request_json") as network:
            rec.rerank(self.seed, enabled=True, api_key=None, model="claude-sonnet-test")
            rec.rerank(self.seed, enabled=False, api_key="test-only", model="claude-sonnet-test")
            network.assert_not_called()

    def test_valid_model_response_can_only_reorder_existing_items(self):
        ids = [i["id"] for i in reversed(self.seed["items"])]
        response = {"stop_reason": "end_turn", "content": [{"type": "text", "text": json.dumps({"ids": ids})}]}
        with patch.object(rec, "request_json", return_value=response) as network:
            feed = rec.rerank(self.seed, enabled=True, api_key="test-only", model="claude-sonnet-test")
            network.assert_called_once()
        self.assertEqual(feed["items"], list(reversed(self.seed["items"])))
        self.assertEqual(feed["curation"]["model"], "claude-sonnet-test")

    def test_invented_duplicate_or_extra_model_fields_rejected(self):
        ids = [i["id"] for i in self.seed["items"]]
        for payload in ({"ids": ids[:-1] + ["invented"]}, {"ids": ids[:-1] + [ids[0]]}, {"ids": ids, "title": "Invented"}):
            with self.assertRaises(ValueError):
                rec.validate_order(payload, self.seed["items"])
        response = {"stop_reason": "end_turn", "content": [{"type": "text", "text": "{}"}]}
        with patch.object(rec, "request_json", return_value=response):
            self.assertEqual(rec.rerank(self.seed, enabled=True, api_key="test-only", model="claude-sonnet-test"), self.seed)

    def test_adaptive_thinking_is_not_published_as_feed_data(self):
        ids = [i["id"] for i in reversed(self.seed["items"])]
        response = {"stop_reason": "end_turn", "content": [
            {"type": "thinking", "thinking": "Private model reasoning", "signature": "test"},
            {"type": "text", "text": json.dumps({"ids": ids})},
        ]}
        with patch.object(rec, "request_json", return_value=response):
            feed = rec.rerank(self.seed, enabled=True, api_key="test-only", model="claude-sonnet-test")
        self.assertEqual([item["id"] for item in feed["items"]], ids)
        self.assertNotIn("Private model reasoning", json.dumps(feed))

    def test_cover_chapter_and_untrusted_urls_rejected(self):
        for field, value in (("coverURL", "https://example.com/scan.jpg"), ("officialURL", "https://www.viz.com/shonenjump/chapters/naruto"), ("officialURL", "https://www.viz.com.evil.test/naruto")):
            feed = copy.deepcopy(self.seed)
            feed["items"][0][field] = value
            with self.assertRaises(ValueError):
                rec.validate_feed(feed)

    def test_dry_run_even_with_key_and_optin_does_not_call_network_or_write(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "feed.json"
            argv = ["update_recommendations.py", "--dry-run", "--sonnet", "--output", str(output)]
            with patch("sys.argv", argv), patch.dict(os.environ, {"ANTHROPIC_API_KEY": "test-only"}), patch.object(rec, "request_json") as network:
                self.assertEqual(rec.main(), 0)
                network.assert_not_called()
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
