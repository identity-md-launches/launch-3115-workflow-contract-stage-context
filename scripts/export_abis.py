#!/usr/bin/env python3
"""Export the built application ABIs, or verify the checked-in copies. No dependencies or network."""
import argparse
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if an ABI differs from the current build")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    for name in ("SqueeklingsArt", "Squeeklings"):
        artifact = root / "out" / f"{name}.sol" / f"{name}.json"
        if not artifact.is_file():
            raise SystemExit(f"Missing {artifact.relative_to(root)}; run forge build first.")
        abi = json.loads(artifact.read_text())["abi"]
        encoded = json.dumps(abi, indent=2) + "\n"
        destination = root / "docs" / "abi" / f"{name}.json"
        if args.check:
            if not destination.is_file() or destination.read_text() != encoded:
                raise SystemExit(f"ABI mismatch: {destination.relative_to(root)}")
            print(f"Verified {destination.relative_to(root)}")
        else:
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_text(encoded)
            print(f"Exported {destination.relative_to(root)}")


if __name__ == "__main__":
    main()
