#!/usr/bin/env python3
import argparse
import json
import re
import sys
from pathlib import Path


EXPECTED_COUNT = 267


def fail(message):
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def normalize_crc(value, source):
    value = value.lower()
    if value.startswith("0x"):
        value = value[2:]
    if not re.fullmatch(r"[0-9a-f]{8}", value):
        fail(f"invalid CRC {value!r} in {source}")
    return value


def main():
    parser = argparse.ArgumentParser(
        description="Require exact pvrsrvkm.ko CONFIG_MODVERSIONS CRC compatibility."
    )
    parser.add_argument("--expected", required=True, type=Path)
    parser.add_argument("--symvers", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    args = parser.parse_args()

    try:
        expected_doc = json.loads(args.expected.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"cannot read expected CRC manifest {args.expected}: {exc}")

    versions = expected_doc.get("versions")
    if not isinstance(versions, list):
        fail("expected manifest has no versions list")
    if expected_doc.get("count") != EXPECTED_COUNT or len(versions) != EXPECTED_COUNT:
        fail(
            f"expected manifest must contain exactly {EXPECTED_COUNT} CRCs "
            f"(declared={expected_doc.get('count')!r}, actual={len(versions)})"
        )

    source_sha = expected_doc.get("sha256", "")
    if not re.fullmatch(r"[0-9a-fA-F]{64}", source_sha):
        fail("expected manifest does not contain a valid source module SHA-256")

    expected = {}
    for entry in versions:
        if not isinstance(entry, dict) or not isinstance(entry.get("name"), str):
            fail("malformed entry in expected CRC manifest")
        name = entry["name"]
        if name in expected:
            fail(f"duplicate expected symbol: {name}")
        expected[name] = normalize_crc(str(entry.get("crc", "")), name)

    actual = {}
    try:
        lines = args.symvers.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        fail(f"cannot read Module.symvers {args.symvers}: {exc}")

    for line_number, line in enumerate(lines, start=1):
        columns = line.split()
        if len(columns) < 2:
            continue
        crc = normalize_crc(columns[0], f"{args.symvers}:{line_number}")
        symbol = columns[1]
        actual.setdefault(symbol, set()).add(crc)

    args.report.parent.mkdir(parents=True, exist_ok=True)
    matches = missing = mismatched = ambiguous = 0
    with args.report.open("w", encoding="utf-8", newline="\n") as report:
        report.write("symbol\texpected_crc\tactual_crc\tstatus\n")
        for symbol, expected_crc in expected.items():
            actual_crcs = actual.get(symbol, set())
            if not actual_crcs:
                status, actual_text = "MISSING", ""
                missing += 1
            elif len(actual_crcs) != 1:
                status, actual_text = "AMBIGUOUS", ",".join(sorted(actual_crcs))
                ambiguous += 1
            else:
                actual_text = next(iter(actual_crcs))
                if actual_text == expected_crc:
                    status = "MATCH"
                    matches += 1
                else:
                    status = "MISMATCH"
                    mismatched += 1
            report.write(
                f"{symbol}\t{expected_crc}\t{actual_text}\t{status}\n"
            )

    print(f"Source pvrsrvkm.ko SHA-256: {source_sha.lower()}")
    print(
        f"pvrsrvkm ABI: {matches}/{EXPECTED_COUNT} matched; "
        f"{missing} missing; {mismatched} mismatched; {ambiguous} ambiguous"
    )
    print(f"Full comparison: {args.report}")
    if matches != EXPECTED_COUNT or missing or mismatched or ambiguous:
        fail("vendor ABI gate failed; kernel packaging must not continue")


if __name__ == "__main__":
    main()
