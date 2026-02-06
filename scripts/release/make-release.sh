#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 /path/to/Quick AI.app <version>"
  exit 1
fi

APP_PATH="$1"
VERSION="$2"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found: $APP_PATH"
  exit 1
fi

mkdir -p dist
ZIP_PATH="dist/Quick-AI-${VERSION}-macos.zip"

rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

if command -v shasum >/dev/null 2>&1; then
  SHA256="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
else
  SHA256="$(openssl dgst -sha256 "$ZIP_PATH" | awk '{print $NF}')"
fi

echo "Created: $ZIP_PATH"
echo "SHA256:  $SHA256"
