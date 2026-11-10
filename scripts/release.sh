#!/bin/bash
# Builds a notarized Developer ID release of Debris.
#
#   scripts/release.sh             archive, export, notarize, staple, zip and dmg into build/release
#   scripts/release.sh finish      staple, zip and dmg an export whose notarization finished later
#   scripts/release.sh image       rebuild, sign, notarize and staple only the dmg
#   scripts/release.sh bump 1.1    set the version in project.yml and regenerate the project
#
# Needs a "Developer ID Application" certificate in the keychain, notarytool credentials
# saved as a keychain profile (xcrun notarytool store-credentials debris) and create-dmg
# from Homebrew.
set -euo pipefail
cd "$(dirname "$0")/.."

profile=${NOTARY_PROFILE:-debris}
identity=${CODESIGN_IDENTITY:-Developer ID Application}
out=build/release

version() { sed -n 's/^ *MARKETING_VERSION: "\(.*\)"$/\1/p' project.yml; }
build_number() { sed -n 's/^ *CURRENT_PROJECT_VERSION: "\(.*\)"$/\1/p' project.yml; }

app="$out/export/Debris.app"
zip="$out/Debris-$(version).zip"
dmg="$out/Debris-$(version).dmg"

# the zip is rebuilt so the stapled ticket travels with it
finish() {
  xcrun stapler staple "$app"
  rm -f "$zip"
  ditto -c -k --keepParent "$app" "$zip"
  spctl -a -vv "$app"
  shasum -a 256 "$zip"
}

# a drag-to-Applications image around the stapled app, notarized on its own
image() {
  local stage
  stage=$(mktemp -d)
  cp -R "$app" "$stage/"
  rm -f "$dmg"
  create-dmg --volname "Debris $(version)" --window-pos 200 120 --window-size 540 380 \
    --icon-size 128 --icon Debris.app 140 190 --app-drop-link 400 190 \
    --hide-extension Debris.app --no-internet-enable --hdiutil-quiet "$dmg" "$stage"
  rm -rf "$stage"
  codesign --sign "$identity" --timestamp "$dmg"
  xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait
  xcrun stapler staple "$dmg"
  spctl -a -vv -t open --context context:primary-signature "$dmg"
  shasum -a 256 "$dmg"
}

need_export() { [ -d "$app" ] || { echo "No export in $out, run a full release first" >&2; exit 1; }; }

# certificates from the original Developer ID sub-CA stop working on 1 Feb 2027, and an
# expiry close ahead is worth knowing before a release rather than after
check_certificate() {
  local pem
  pem=$(security find-certificate -c "$identity" -p) \
    || { echo "No certificate named \"$identity\" in the keychain" >&2; exit 1; }
  openssl x509 -noout -issuer <<<"$pem" | grep -Eq 'OU ?= ?G2([,/]|$)' \
    || { echo "The signing certificate is not from the G2 sub-CA, create a new one" >&2; exit 1; }
  openssl x509 -noout -checkend 0 <<<"$pem" >/dev/null \
    || { echo "The signing certificate has expired" >&2; exit 1; }
  openssl x509 -noout -checkend $((30 * 86400)) <<<"$pem" >/dev/null \
    || echo "warning: the signing certificate expires soon ($(openssl x509 -noout -enddate <<<"$pem"))" >&2
}

if [ "${1:-}" = "finish" ]; then
  need_export
  check_certificate
  finish
  image
  exit 0
fi

if [ "${1:-}" = "image" ]; then
  need_export
  check_certificate
  image
  exit 0
fi

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
check_certificate
command -v create-dmg >/dev/null \
  || { echo "create-dmg is not installed (brew install create-dmg)" >&2; exit 1; }

rm -rf "$out"
mkdir -p "$out"
xcodegen generate >/dev/null

xcodebuild -project Debris.xcodeproj -scheme Debris -configuration Release \
  -derivedDataPath build/DerivedData -archivePath "$out/Debris.xcarchive" archive | tail -2
xcodebuild -exportArchive -archivePath "$out/Debris.xcarchive" \
  -exportOptionsPlist scripts/ExportOptions.plist -exportPath "$out/export" | tail -2

ditto -c -k --keepParent "$app" "$zip"
xcrun notarytool submit "$zip" --keychain-profile "$profile" --wait
finish
image
