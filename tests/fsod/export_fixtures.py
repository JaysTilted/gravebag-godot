#!/usr/bin/env python3
"""Export pinned source contracts (stdlib only); writes only tests/fsod/*.json.
Upstream AGPL-3.0 provenance is embedded in each fixture; see source_contract.py.
"""
import argparse
import json
from source_contract import (BACKEND_ROOTS, FIXTURES, REVISION, URL, binary_fixtures,
                             client_responsibilities, golden_stats, inventory, protocol_catalog, source_path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", help="Pinned upstream checkout; default references/fsod then /home/jay/fsod-ref")
    args = parser.parse_args()
    source = source_path(args.source)
    entries = inventory(source)
    exports = {
        "source-inventory.json": {"url": URL, "revision": REVISION, "license": "AGPL-3.0", "date": "2026-10-06",
                                  "entries": entries,
                                  "backend_counts": {root: sum(entry["path"].startswith(root) for entry in entries) for root in BACKEND_ROOTS}},
        "stats-golden.json": golden_stats(source),
        "client-responsibilities.json": client_responsibilities(source),
        "binary-stats.json": binary_fixtures(source),
        "protocol-catalog.json": {"revision": REVISION, "license": "AGPL-3.0", "url": URL,
                                  "meaning": "All concrete packet serializers, including unused/asymmetric readers/writers. Direction determines authority.",
                                  "packets": protocol_catalog(source)},
    }
    for name, data in exports.items():
        destination = FIXTURES / name
        destination.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        json.loads(destination.read_text(encoding="utf-8"))
        print(name)


if __name__ == "__main__":
    main()
