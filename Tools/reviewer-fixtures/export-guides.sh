#!/bin/bash
set -euo pipefail
task_repo_root="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
task_sdk_root="$(xcrun --sdk macosx --show-sdk-path)"
cd "$task_repo_root"
mkdir -p Tools/reviewer-fixtures/runtime Tools/reviewer-fixtures/generated/assets
task_exporter="$task_repo_root/Tools/reviewer-fixtures/runtime/export-guides"
trap 'rm -f "$task_exporter"' EXIT
xcrun --sdk macosx swiftc -target arm64-apple-ios26.0-macabi \
  -F "$task_sdk_root/System/iOSSupport/System/Library/Frameworks" \
  -I "$task_sdk_root/System/iOSSupport/usr/include" -D SUMI \
  Aidoku/Features/Bookshelf/Services/HonbakoGuideBook.swift \
  Aidoku/Features/Bookshelf/Services/HonbakoGuideRenderer.swift \
  Aidoku/Features/Bookshelf/Services/HonbakoJapanesePracticePage.swift \
  Tools/reviewer-fixtures/export-guides.swift -o "$task_exporter"
"$task_exporter" "$task_repo_root/Tools/reviewer-fixtures/generated/assets" "$task_repo_root"
