#!/usr/bin/env python3
"""Sync/check the small set of duplicated Sigma authentication runtimes."""

import argparse
import os
import shutil
import sys


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAIRS = (
    (
        "sigma-api/scripts/get_token.py",
        "custom-sql-to-data-model/scripts/get_token.py",
    ),
    (
        "sigma-api/scripts/get-token.sh",
        "custom-sql-to-data-model/scripts/get-token.sh",
    ),
    (
        "custom-sql-to-data-model/scripts/lib/sigma_rest.rb",
        "sigma-plugin-authoring/scripts/lib/sigma_rest.rb",
    ),
)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check", action="store_true", help="fail instead of updating drift"
    )
    args = parser.parse_args()
    drift = []

    for source_rel, target_rel in PAIRS:
        source = os.path.join(ROOT, source_rel)
        target = os.path.join(ROOT, target_rel)
        if not os.path.isfile(source):
            parser.error(f"missing canonical auth runtime: {source_rel}")

        if args.check:
            try:
                with open(source, "rb") as left, open(target, "rb") as right:
                    matches = left.read() == right.read()
            except FileNotFoundError:
                matches = False
            if not matches:
                drift.append(f"{target_rel} differs from {source_rel}")
        else:
            os.makedirs(os.path.dirname(target), exist_ok=True)
            shutil.copy2(source, target)
            print(f"synced {source_rel} -> {target_rel}")

    if drift:
        print("\n".join(drift), file=sys.stderr)
        print("run: python3 scripts/sync_auth_runtime.py", file=sys.stderr)
        return 1
    if args.check:
        print("auth runtime copies are in sync")
    return 0


if __name__ == "__main__":
    sys.exit(main())
