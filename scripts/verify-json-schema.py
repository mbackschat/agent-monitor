#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["jsonschema==4.26.0"]
# ///
"""Validate schema discovery and encoded JSONL output with an independent validator."""

import argparse
import copy
import json
import subprocess

from jsonschema import Draft202012Validator, FormatChecker

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("binary")
parser.add_argument("--records", help="Validate encoded synthetic JSONL instead of collecting live processes")
args = parser.parse_args()
binary = args.binary
schema_result = subprocess.run(
    [binary, "--json-schema", "--interval", "60"], capture_output=True, text=True, check=True, timeout=5
)
schema = json.loads(schema_result.stdout)
Draft202012Validator.check_schema(schema)
validator = Draft202012Validator(schema, format_checker=FormatChecker())
if args.records:
    with open(args.records, encoding="utf-8") as source:
        records = [json.loads(line) for line in source if line.strip()]
else:
    result = subprocess.run(
        [binary, "--json", "--all-processes", "--cpu", "0", "--memory-gb", "0", "--samples", "2", "--interval", "0.1"],
        capture_output=True, text=True, check=True, timeout=15,
    )
    records = [json.loads(line) for line in result.stdout.splitlines()]
    assert len(records) == 2
    assert all(record["findings"] for record in records), "Live validation must include process records"
assert records
for record in records:
    validator.validate(record)

invalid_records = []
for field, value in [("hostBusyPercent", -1), ("hostBusyPercent", None), ("logicalCPUCount", 0),
                     ("measuredUserPercent", "large"), ("unmeasuredLifetimeCount", -1),
                     ("previousScanSeconds", -1), ("unknownField", 1)]:
    invalid = copy.deepcopy(records[0])
    invalid["cpuAccounting"][field] = value
    invalid_records.append(invalid)
for field in ["cpuAccounting", "schemaVersion"]:
    invalid = copy.deepcopy(records[0])
    del invalid[field]
    invalid_records.append(invalid)
for field in ["logicalCPUCount", "measuredUserPercent", "unmeasuredLifetimeCount"]:
    invalid = copy.deepcopy(records[0])
    del invalid["cpuAccounting"][field]
    invalid_records.append(invalid)
for field, value in [("unknownField", 1), ("schemaVersion", 2)]:
    invalid = copy.deepcopy(records[0])
    invalid[field] = value
    invalid_records.append(invalid)
with_findings = next((record for record in records if record["findings"]), None)
if with_findings:
    for field, value in [("cpuPercent", -1), ("footprintBytes", "large"), ("process", {"pid": 1})]:
        invalid = copy.deepcopy(with_findings)
        invalid["findings"][0][field] = value
        invalid_records.append(invalid)
    invalid = copy.deepcopy(with_findings)
    invalid["findings"][0]["attribution"]["evidence"] = "guessed"
    invalid_records.append(invalid)
for invalid in invalid_records:
    assert not validator.is_valid(invalid), "Schema accepted a malformed report"
print(f"PASS schema discovery, {len(records)} JSONL reports, and {len(invalid_records)} rejection checks")
