#!/usr/bin/env bash
set -euo pipefail

# Run once after authorizing GitHub workflow scope:
#   gh auth refresh -h github.com -s workflow

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

mkdir -p .github/workflows
cp ci/ios-release.yml .github/workflows/ios-release.yml
git add .github/workflows/ios-release.yml
git commit -m "ci: enable macos-26 Xcode 26 unsigned IPA & simulator workflow"
git push origin main
gh workflow run ios-release.yml || true
