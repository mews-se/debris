#!/bin/bash
# Builds a notarized Developer ID release of Debris.
#
#   scripts/release.sh             archive, export, notarize, staple, zip into build/release
#   scripts/release.sh bump 1.1    set the version in project.yml and regenerate the project
#
# Needs a "Developer ID Application" certificate in the keychain and notarytool credentials
# saved as a keychain profile:  xcrun notarytool store-credentials debris
set -euo pipefail
cd "$(dirname "$0")/.."

profile=${NOTARY_PROFILE:-debris}
out=build/release

version() { sed -n 's/^ *MARKETING_VERSION: "\(.*\)"$/\1/p' project.yml; }
build_number() { sed -n 's/^ *CURRENT_PROJECT_VERSION: "\(.*\)"$/\1/p' project.yml; }

if [ "${1:-}" = "bump" ]; then
  [ -n "${2:-}" ] || { echo "usage: $0 bump <version>" >&2; exit 2; }
  next=$(( $(build_number) + 1 ))
  sed -i '' -e "s/^\( *MARKETING_VERSION: \)\".*\"$/\1\"$2\"/" \
            -e "s/^\( *CURRENT_PROJECT_VERSION: \)\".*\"$/\1\"$next\"/" project.yml
  xcodegen generate >/dev/null
  echo "Debris $2 ($next)"
  exit 0
fi

security find-identity -v -p codesigning | grep -q "Developer ID Application" \
  || { echo "No Developer ID Application certificate in the keychain" >&2; exit 1; }

ver=$(version)
rm -rf "$out"
mkdir -p "$out"
xcodegen generate >/dev/null

xcodebuild -project Debris.xcodeproj -scheme Debris -configuration Release \
  -derivedDataPath build/DerivedData -archivePath "$out/Debris.xcarchive" archive | tail -2
xcodebuild -exportArchive -archivePath "$out/Debris.xcarchive" \
  -exportOptionsPlist scripts/ExportOptions.plist -exportPath "$out/export" | tail -2

app="$out/export/Debris.app"
zip="$out/Debris-$ver.zip"
ditto -c -k --keepParent "$app" "$zip"
xcrun notarytool submit "$zip" --keychain-profile "$profile" --wait
xcrun stapler staple "$app"
# the zip is rebuilt so the stapled ticket travels with it
rm "$zip"
ditto -c -k --keepParent "$app" "$zip"

spctl -a -vv "$app"
shasum -a 256 "$zip"
