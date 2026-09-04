#!/usr/bin/env bash
# Regenerates the bundled dataset from the current GeoNames export and shows
# whether it changed. Usage: tool/regenerate.sh
set -euo pipefail
cd "$(dirname "$0")/.."
tool/fetch_geonames.sh cities15000 >/dev/null
dart run bin/generate.dart \
  --cities build/geonames/cities15000.txt \
  --admin1 build/geonames/admin1CodesASCII.txt \
  --country-info build/geonames/countryInfo.txt \
  --dart lib/src/data/cities15000.dart
git status --short lib/src/data/
