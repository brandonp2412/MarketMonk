import argparse
from collections import Counter
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets" / "release_history.json"
REPOSITORY_URL = "https://github.com/brandonp2412/MarketMonk"
VERSION_PATTERN = re.compile(r"^v?(\d+)\.(\d+)\.(\d+)(?:\+\d+)?$")
PREFIX = re.compile(r"^(?:feat|fix|perf|refactor|style|test|docs|chore|ci|build|ui)(?:\([^)]+\))?:\s*", re.IGNORECASE)
NOISE = re.compile(
    r"^(?:Bump version|Release version|Merge |chore(?:\(|:)|ci(?:\(|:)|"
    r"docs(?:\(|:)|test(?:\(|:)|style(?:\(|:)|build(?:\(|:)|"
    r"refactor(?:\(|:)|Revert |Fix tests|Format |Update screenshots)",
    re.IGNORECASE,
)


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def version_key(version):
    match = VERSION_PATTERN.fullmatch(version)
    if not match:
        raise ValueError(f"Invalid release version: {version}")
    return tuple(map(int, match.groups()))


def notes_between(start, end):
    commits = git("log", "--no-merges", "--format=%s", f"{start}..{end}" if start else end)
    cleaned = []
    for subject in commits.splitlines():
        if NOISE.match(subject):
            continue
        subject = PREFIX.sub("", subject)
        subject = re.sub(r"\s*\[skip ci\]\s*", "", subject, flags=re.IGNORECASE).strip()
        if subject:
            cleaned.append(subject[0].upper() + subject[1:])
    counts = Counter(cleaned)
    seen = set()
    notes = []
    for item in cleaned:
        if item not in seen:
            seen.add(item)
            notes.append(f"{item} ({counts[item]} commits)" if counts[item] > 1 else item)
    return notes[:12] or ["Bug fixes and improvements"]


def build_history(candidate=None, release_notes=None):
    current = json.loads(OUTPUT.read_text()) if OUTPUT.exists() else []
    entries = {item["version"]: item for item in current}
    tags = {}
    refs = git("for-each-ref", "--format=%(refname:short)\t%(creatordate:short)", "refs/tags")
    for line in refs.splitlines():
        ref, date = line.split("\t", 1)
        if VERSION_PATTERN.fullmatch(ref):
            tags[ref.removeprefix("v")] = (ref, date)

    ordered = sorted(tags, key=version_key)
    previous = None
    for version in ordered:
        ref, date = tags[version]
        if version not in entries:
            entries[version] = {
                "version": version,
                "date": date,
                "sourceUrl": (
                    f"{REPOSITORY_URL}/compare/{previous}...{ref}"
                    if previous else f"{REPOSITORY_URL}/tree/{ref}"
                ),
                "changes": notes_between(previous, ref),
            }
        previous = ref

    if candidate is not None:
        if release_notes is None:
            raise ValueError("Handwritten release notes are required for a new release")
        version_key(candidate)
        if ordered and version_key(candidate) <= version_key(ordered[-1]):
            raise ValueError("Candidate must be newer than the latest tagged release")
        ref = f"v{candidate}"
        entries[candidate] = {
            "version": candidate,
            "date": datetime.now(timezone.utc).date().isoformat(),
            "sourceUrl": (
                f"{REPOSITORY_URL}/compare/{previous}...{ref}"
                if previous else f"{REPOSITORY_URL}/tree/{ref}"
            ),
            "changes": [release_notes.strip()],
        }
    return sorted(entries.values(), key=lambda item: version_key(item["version"]), reverse=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--version", help="Prepare history for a version about to be tagged")
    parser.add_argument("--notes", type=Path, help="Handwritten release notes for the candidate version")
    args = parser.parse_args()
    content = json.dumps(build_history(candidate=args.version, release_notes=args.notes.read_text(encoding="utf-8") if args.notes else None), indent=2, ensure_ascii=False) + "\n"
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text() != content:
            print("Release history is out of date; run python3 tool/build_release_history.py", file=sys.stderr)
            return 1
        return 0
    OUTPUT.write_text(content)
    print(f"Updated {OUTPUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
