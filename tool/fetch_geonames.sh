#!/usr/bin/env bash
# Fetches the GeoNames export files the generator needs into build/geonames/,
# which is gitignored. Usage: tool/fetch_geonames.sh [cities15000|cities1000 ...]
# With no arguments it fetches cities15000.
set -euo pipefail
dir="$(cd "$(dirname "$0")/.." && pwd)/build/geonames"
base="https://download.geonames.org/export/dump"
mkdir -p "$dir"
sets=("$@")
[ ${#sets[@]} -eq 0 ] && sets=(cities15000)
for s in "${sets[@]}"; do
  curl -fsSL --retry 3 -o "$dir/$s.zip" "$base/$s.zip"
  unzip -oq "$dir/$s.zip" -d "$dir"
done
curl -fsSL --retry 3 -o "$dir/admin1CodesASCII.txt" "$base/admin1CodesASCII.txt"
curl -fsSL --retry 3 -o "$dir/countryInfo.txt" "$base/countryInfo.txt"
ls -l "$dir"
