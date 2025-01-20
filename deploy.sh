#!/bin/bash

# Read the current version from pubspec.yaml
current_version=$(grep '^version:' pubspec.yaml | awk '{print $2}')
IFS='.' read -r major minor patch <<< "$current_version"

# Bump the patch version
new_patch=$((patch + 1))
new_version="$major.$minor.$new_patch"

# Update the version in pubspec.yaml
sed -i '' "s/^version: .*/version: $new_version/" pubspec.yaml

# Commit the changes and create a Git tag
git add pubspec.yaml
git commit -m "Bump version to $new_version"
git tag "$new_version"

# Push the changes and the tag
git push origin main
git push origin "$new_version"