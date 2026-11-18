#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

FW="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
SW="/Library/Developer/CommandLineTools/Library/Developer/usr/lib"

swift build
DYLD_FRAMEWORK_PATH="${FW}" DYLD_LIBRARY_PATH="${SW}" swift test \
  -Xswiftc -F -Xswiftc "${FW}" \
  -Xlinker -F -Xlinker "${FW}" \
  -Xlinker -rpath -Xlinker "${FW}" \
  -Xlinker -rpath -Xlinker "${SW}"
