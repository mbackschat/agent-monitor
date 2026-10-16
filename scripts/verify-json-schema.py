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
parser.add_argument("--diagnosis", action="store_true", help="Validate finite CPU diagnosis fixtures")
parser.add_argument("--schema", help="Use a schema file instead of command discovery (diagnosis only)")
args = parser.parse_args()
if args.diagnosis:
    if not args.records:
        parser.error("--diagnosis requires --records so validation never lists real sessions")
    if args.schema:
        with open(args.schema, encoding="utf-8") as source:
            schema = json.load(source)
    else:
        result = subprocess.run([args.binary, "diagnose", "cpu", "--json-schema"],
                                capture_output=True, text=True, check=True, timeout=5)
        assert not result.stderr
        schema = json.loads(result.stdout)
    Draft202012Validator.check_schema(schema)
    validator = Draft202012Validator(schema, format_checker=FormatChecker())
    with open(args.records, encoding="utf-8") as source:
        records = [json.loads(line) for line in source if line.strip()]
    assert records
    with open("Tests/Fixtures/Diagnosis/example.json", encoding="utf-8") as source:
        validator.validate(json.load(source))
    rejected = 0

    def object_paths(value, path=()):
        if isinstance(value, dict):
            yield path
            for key, item in value.items():
                yield from object_paths(item, path + (key,))
        elif isinstance(value, list):
            for key, item in enumerate(value):
                yield from object_paths(item, path + (key,))

    for record in records:
        validator.validate(record)
        for path in object_paths(record):
            invalid = copy.deepcopy(record)
            node = invalid
            for key in path:
                node = node[key]
            node["unknownField"] = 1
            assert not validator.is_valid(invalid), f"Unknown property accepted at {path}"
            rejected += 1
        for key, bad in [("schemaVersion", 2), ("measurementIntervals", 4),
                         ("requestedIntervalSeconds", 2), ("elapsedSeconds", -1),
                         ("diagnostics", ["guessed"]), ("diagnostics", ["unmeasuredCPU"] * 2)]:
            invalid = copy.deepcopy(record)
            invalid[key] = bad
            assert not validator.is_valid(invalid), f"Invalid {key} accepted"
            rejected += 1
        for parent, key in [("host", "meanBusyPercent"), ("host", "logicalCPUCount"),
                            ("measured", "cpuSeconds"), ("measured", "windowCPUPercent")]:
            invalid = copy.deepcopy(record)
            invalid[parent][key] = None
            assert not validator.is_valid(invalid), f"Null {key} accepted"
            rejected += 1
        for key in schema["required"]:
            invalid = copy.deepcopy(record)
            del invalid[key]
            assert not validator.is_valid(invalid), f"Missing {key} accepted"
            rejected += 1
    print(f"PASS diagnosis schema, approved example, {len(records)} encoded results and {rejected} rejection checks")
    raise SystemExit(0)
if args.schema:
    parser.error("--schema is only supported with --diagnosis")
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
