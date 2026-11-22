#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
archive="$(mktemp -t buie-llama.XXXXXX)"
trap 'rm -f "$archive"' EXIT
curl -fL --retry 3 -o "$archive" "https://github.com/ggml-org/llama.cpp/releases/download/b6500/llama-b6500-xcframework.zip"
echo "00e8636fdb02a2cbfec5612d8835b1cc33a1a23242195db331933ce7d4514975  $archive" | shasum -a 256 -c -
mkdir -p build-apple
unzip -qo "$archive" 'build-apple/llama.xcframework/*' -d .
xcodegen generate
