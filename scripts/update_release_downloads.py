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
# Match the adjacent Shields for-the-badge geometry and typography.
left = 93.5
value_length = len(value.replace(",", "")) * 7.4 + value.count(",") * 3.5
right = max(56, value_length + 24)
width = left + right
svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{width:g}" height="28" role="img" aria-label="DOWNLOADS: {value}">
  <title>DOWNLOADS: {value}</title>
  <g shape-rendering="crispEdges">
    <rect width="{left:g}" height="28" fill="#ffb52e"/>
    <rect x="{left:g}" width="{right:g}" height="28" fill="#151218"/>
  </g>
  <g fill="#fff" text-anchor="middle" font-family="Verdana,Geneva,DejaVu Sans,sans-serif" text-rendering="geometricPrecision" font-size="100">
    <text transform="scale(.1)" x="{left*5:g}" y="175" textLength="695" fill="#333">DOWNLOADS</text>
    <text transform="scale(.1)" x="{(left+right/2)*10:g}" y="175" textLength="{value_length*10:g}" font-weight="bold">{value}</text>
  </g>
</svg>
'''
Path("docs/release-downloads.svg").write_text(svg)
print(f"Release downloads: {value}")
