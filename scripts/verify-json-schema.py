#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["jsonschema==4.26.0"]
# ///
"""Validate schema discovery and live JSONL output with an independent validator."""

import copy
import json
import subprocess
import sys

from jsonschema import Draft202012Validator, FormatChecker

binary = sys.argv[1]
schema_result = subprocess.run(
    [binary, "--json-schema", "--interval", "60"], capture_output=True, text=True, check=True, timeout=5
)
schema = json.loads(schema_result.stdout)
Draft202012Validator.check_schema(schema)
validator = Draft202012Validator(schema, format_checker=FormatChecker())
result = subprocess.run(
    [binary, "--json", "--all-processes", "--cpu", "0", "--memory-gb", "0", "--samples", "2", "--interval", "0.1"],
    capture_output=True, text=True, check=True, timeout=15,
)
records = [json.loads(line) for line in result.stdout.splitlines()]
assert len(records) == 2
assert all(record["findings"] for record in records), "Validation must include real process records"
for record in records:
    validator.validate(record)

invalid_records = []
missing_version = copy.deepcopy(records[0])
del missing_version["schemaVersion"]
invalid_records.append(missing_version)
for field, value in [("cpuPercent", -1), ("footprintBytes", "large"), ("process", {"pid": 1})]:
    invalid = copy.deepcopy(records[0])
    invalid["findings"][0][field] = value
    invalid_records.append(invalid)
invalid_evidence = copy.deepcopy(records[0])
invalid_evidence["findings"][0]["attribution"]["evidence"] = "guessed"
invalid_records.append(invalid_evidence)
for invalid in invalid_records:
    assert not validator.is_valid(invalid), "Schema accepted a malformed report"
print(f"PASS schema discovery, {len(records)} live JSONL reports, and {len(invalid_records)} rejection checks")
