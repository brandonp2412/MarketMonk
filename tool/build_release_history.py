from collections import Counter
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets" / "release_history.json"
REPOSITORY_URL = "https://github.com/brandonp2412/MarketMonk"
VERSION_PATTERN = re.compile(r"^v?1\.0\.(\d+)(?:\+\d+)?$")
RELEASE_COMMIT = re.compile(
    r"^(?:Bump version to |Release version |\d+\.\d+\.\d+ 🚀)",
    re.IGNORECASE,
)
COMMIT_PREFIX = re.compile(
    r"^(?:feat|fix|perf|refactor|style|test|docs|chore|ci|ui)"
    r"(?:\([^)]+\))?:\s*",
    re.IGNORECASE,
)
UNTAGGED_RELEASE = re.compile(r"^(1\.0\.(\d+)) 🚀")


def git(*args):
    return subprocess.check_output(
        ["git", *args], cwd=ROOT, text=True
    ).strip()


def notes_between(start, end):
    revision = f"{start}..{end}" if start else end
    subjects = git("log", "--no-merges", "--format=%s", revision).splitlines()
    cleaned = []
    for subject in subjects:
        if RELEASE_COMMIT.match(subject):
            continue
        text = COMMIT_PREFIX.sub("", subject)
        text = re.sub(r"\s*\[skip ci\]\s*", "", text, flags=re.IGNORECASE)
        text = text.strip()
        if text:
            cleaned.append(text[0].upper() + text[1:])

    counts = Counter(cleaned)
    seen = set()
    notes = []
    for item in cleaned:
        if item in seen:
            continue
        seen.add(item)
        count = counts[item]
        notes.append(f"{item} ({count} commits)" if count > 1 else item)
    return notes


def build_history():
    refs = git(
        "for-each-ref",
        "--format=%(refname:short)\t%(creatordate:short)",
        "refs/tags",
    ).splitlines()
    releases = []
    for row in refs:
        tag, released_on = row.split("\t", 1)
        match = VERSION_PATTERN.fullmatch(tag)
        if match:
            releases.append({
                "number": int(match.group(1)),
                "ref": tag,
                "version": tag.removeprefix("v"),
                "date": released_on,
            })

    tagged_numbers = {release["number"] for release in releases}
    for row in git("log", "--format=%H\t%cs\t%s", "HEAD").splitlines():
        sha, released_on, subject = row.split("\t", 2)
        match = UNTAGGED_RELEASE.match(subject)
        if not match:
            continue
        number = int(match.group(2))
        if number not in tagged_numbers:
            releases.append({
                "number": number,
                "ref": sha,
                "version": match.group(1),
                "date": released_on,
            })

    releases.sort(key=lambda entry: entry["number"])
    history = []
    for index, release in enumerate(releases):
        previous = releases[index - 1]["ref"] if index else None
        ref = release["ref"]
        history.append({
            "version": release["version"],
            "date": release["date"],
            "sourceUrl": (
                f"{REPOSITORY_URL}/compare/{previous}...{ref}"
                if previous
                else f"{REPOSITORY_URL}/tree/{ref}"
            ),
            "changes": notes_between(previous, ref),
        })

    last_tag = releases[-1]["ref"]
    current_version = next(
        line.partition("version:")[2].strip().split("+", 1)[0]
        for line in (ROOT / "pubspec.yaml").read_text().splitlines()
        if line.startswith("version:")
    )
    development = notes_between(last_tag, "HEAD")
    if development:
        history.append({
            "version": f"Unreleased (app {current_version})",
            "date": git("log", "-1", "--format=%cs", "HEAD"),
            "sourceUrl": f"{REPOSITORY_URL}/compare/{last_tag}...main",
            "changes": development,
        })

    return list(reversed(history))


if __name__ == "__main__":
    OUTPUT.write_text(
        json.dumps(build_history(), indent=2, ensure_ascii=False) + "\n"
    )
    print(f"Wrote {OUTPUT}")
