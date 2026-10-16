#!/usr/bin/env python3
"""Tests for the documentation link, index and status checks in docs.py."""

import importlib.util
import pathlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("docs", pathlib.Path(__file__).with_name("docs.py"))
docs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(docs)

PROPOSAL = "# Count newborn CPU\n\nStatus: **approved**, 2026-10-16. Waiting for implementation.\n\n## Contract\n"


class DocsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temp.name)
        self.write("README.md", "# Project\n\nSee [docs](docs/README.md).\n")
        self.write(
            "docs/README.md",
            "# Docs\n\n- [Usage](usage.md)\n- [Proposals](proposals/README.md)\n- [Decisions](decisions/README.md)\n",
        )
        self.write("docs/usage.md", "# Usage\n\n## Filters and measurements\n\nText.\n")
        self.write("docs/proposals/cpu.md", PROPOSAL)
        self.write("docs/proposals/README.md", "# Proposals\n\n<!-- status-table:begin -->\n<!-- status-table:end -->\n")
        self.write("docs/decisions/README.md", "# Decisions\n\n<!-- status-table:begin -->\n<!-- status-table:end -->\n")
        docs.sync(self.root)

    def tearDown(self):
        self.temp.cleanup()

    def write(self, path, text):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8")

    def read(self, path):
        return (self.root / path).read_text(encoding="utf-8")

    def test_synced_tree_passes(self):
        self.assertEqual(docs.check(self.root), [])

    def test_sync_writes_one_status_row_per_document(self):
        self.assertIn("| [Count newborn CPU](cpu.md) | approved | 2026-10-16 |", self.read("docs/proposals/README.md"))

    def test_missing_file_and_anchor_are_reported(self):
        self.write("docs/usage.md", "# Usage\n\n[gone](missing.md) and [bad](usage.md#nowhere) and [ok](#usage).\n")
        errors = docs.check(self.root)
        self.assertTrue(any("missing.md" in error for error in errors), errors)
        self.assertTrue(any("#nowhere" in error for error in errors), errors)
        self.assertEqual(len(errors), 2, errors)

    def test_anchor_uses_github_slug_rules(self):
        self.write("docs/usage.md", "# Usage\n\n## Review follow-up — 2026-10-16\n\n[x](#review-follow-up--2026-10-16)\n")
        self.assertEqual(docs.check(self.root), [])

    def test_links_inside_code_are_ignored(self):
        self.write("docs/usage.md", "# Usage\n\n`[a](missing.md)`\n\n```\n[b](missing.md)\n```\n")
        self.assertEqual(docs.check(self.root), [])

    def test_unindexed_document_is_reported(self):
        self.write("docs/installation.md", "# Installation\n")
        self.assertTrue(any("installation.md" in error for error in docs.check(self.root)))

    def test_table_drift_is_reported(self):
        self.write("docs/proposals/cpu.md", PROPOSAL.replace("**approved**", "**on hold**"))
        self.assertTrue(any("out of date" in error for error in docs.check(self.root)))

    def test_status_outside_folder_vocabulary_is_reported(self):
        self.write("docs/proposals/cpu.md", PROPOSAL.replace("**approved**", "**implemented**"))
        self.assertTrue(any("implemented" in error for error in docs.check(self.root)))

    def test_missing_status_line_is_reported(self):
        self.write("docs/proposals/cpu.md", "# Count newborn CPU\n\nNo status here.\n")
        self.assertTrue(any("Status:" in error for error in docs.check(self.root)))

    def test_status_command_updates_document_and_table(self):
        docs.set_status(self.root, self.root / "docs/proposals/cpu.md", "on hold", "2026-10-17")
        self.assertTrue(self.read("docs/proposals/cpu.md").startswith(
            "# Count newborn CPU\n\nStatus: **on hold**, 2026-10-17. Waiting for implementation."))
        self.assertIn("| on hold | 2026-10-17 |", self.read("docs/proposals/README.md"))
        self.assertEqual(docs.check(self.root), [])

    def test_status_command_rejects_foreign_keyword(self):
        with self.assertRaises(ValueError):
            docs.set_status(self.root, self.root / "docs/proposals/cpu.md", "deferred", "2026-10-17")


if __name__ == "__main__":
    unittest.main()
