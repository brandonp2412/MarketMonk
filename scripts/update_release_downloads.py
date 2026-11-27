#!/usr/bin/env python3
"""Generate a release asset download badge from GitHub's API."""
import json
import os
from pathlib import Path
import subprocess

repo = os.environ.get("GITHUB_REPOSITORY", "brandonp2412/MarketMonk")
pages = json.loads(subprocess.check_output([
    "gh", "api", f"repos/{repo}/releases?per_page=100",
    "--paginate", "--slurp",
], text=True))
total = sum(asset["download_count"] for page in pages
            for release in page if not release["draft"]
            for asset in release["assets"])
value = f"{total:,}"
left = 142
right = max(56, len(value) * 9 + 20)
width = left + right
svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="28" role="img" aria-label="Release downloads: {value}">
  <title>Release downloads: {value}</title>
  <rect width="{left}" height="28" fill="#FFB52E"/>
  <rect x="{left}" width="{right}" height="28" fill="#151218"/>
  <g font-family="Verdana,DejaVu Sans,sans-serif" font-size="10" font-weight="bold" letter-spacing="1" text-anchor="middle">
    <text x="{left/2}" y="18" fill="#151218">RELEASE DOWNLOADS</text>
    <text x="{left+right/2}" y="18" fill="#fff">{value}</text>
  </g>
</svg>
'''
Path("docs/release-downloads.svg").write_text(svg)
print(f"Release downloads: {value}")
