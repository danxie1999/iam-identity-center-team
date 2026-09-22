#!/usr/bin/env python3
"""Post-export partition normalization.

The GraphQL transformer and other Amplify CLI generators emit hardcoded
`arn:aws:` prefixes in the export output (~230 occurrences in generated
templates and resolver pipelines) that do not exist in any checked-in source.
In non-default partitions (aws-cn, aws-us-gov) these must be rewritten to the
deployment partition before the exported backend is deployed.

Mechanical and idempotent; a no-op in the `aws` partition.

Usage: normalize-partition.py <export-dir>   (region from AWS_REGION)
"""
import glob
import os
import sys

export_dir = sys.argv[1]
region = os.environ.get("AWS_REGION", "us-east-1")
partition = "aws-cn" if region.startswith("cn-") else \
            "aws-us-gov" if region.startswith("us-gov-") else "aws"

if partition == "aws":
    print("aws partition — no normalization needed")
    sys.exit(0)

changed = 0
for pattern in ("**/*.json", "**/*.vtl", "**/*.yaml", "**/*.yml"):
    for f in glob.glob(os.path.join(export_dir, pattern), recursive=True):
        s = open(f, encoding="utf-8").read()
        s2 = s.replace("arn:aws:", f"arn:{partition}:")
        if s2 != s:
            open(f, "w", encoding="utf-8").write(s2)
            changed += 1

print(f"partition={partition}: normalized {changed} files")
