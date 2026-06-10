#!/usr/bin/env python3
"""Gate CI on new Aderyn findings vs the triaged baseline.

Usage: python3 ci/check_aderyn.py <aderyn-report.json> [baseline.json]

Fails (exit 1) when:
  - any high-severity issue is reported, or
  - a low-severity detector reports more instances than the baseline allows
    (new detectors count as baseline 0).

Shrinking counts are reported as a hint to tighten the baseline but do not fail.
"""

import json
import sys

DEFAULT_BASELINE = "ci/aderyn-baseline.json"


def instance_counts(report: dict, bucket: str) -> dict:
    issues = report.get(bucket, {}).get("issues", [])
    return {i["detector_name"]: len(i["instances"]) for i in issues}


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__.strip())
        return 2

    with open(sys.argv[1]) as f:
        report = json.load(f)
    baseline_path = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_BASELINE
    with open(baseline_path) as f:
        baseline = json.load(f)

    failures = []

    high = instance_counts(report, "high_issues")
    if sum(high.values()) > baseline.get("high", 0):
        failures.append(f"high-severity findings present: {high}")

    allowed_low = baseline.get("low", {})
    low = instance_counts(report, "low_issues")
    for detector, count in sorted(low.items()):
        allowed = allowed_low.get(detector, 0)
        if count > allowed:
            failures.append(f"low '{detector}': {count} instances > baseline {allowed}")
        elif count < allowed:
            print(f"hint: low '{detector}' shrank to {count} (baseline {allowed}) — consider tightening {baseline_path}")

    for detector in sorted(set(allowed_low) - set(low)):
        print(f"hint: low '{detector}' no longer reported — consider removing it from {baseline_path}")

    if failures:
        print("\nAderyn baseline check FAILED:")
        for f_ in failures:
            print(f"  - {f_}")
        print("\nEither fix the finding or (if triaged as accepted) update ci/aderyn-baseline.json with justification.")
        return 1

    print("Aderyn baseline check passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
