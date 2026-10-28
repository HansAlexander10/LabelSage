#!/bin/bash
# Archive LabelSage and upload it to TestFlight (App Store Connect).
# Needs: a paid Apple Developer team, an App Store Connect app record with the same bundle ID,
# and that team's account signed in to Xcode (Settings > Accounts), or an App Store Connect API key.
#
# Usage, from app/frontend/ios:
#   TEAM_ID=ABCDE12345 ./testflight.sh                     # archive + upload, signed with the Xcode account
#   TEAM_ID=ABCDE12345 BUNDLE_ID=com.example.labelsage ./testflight.sh
#   TEAM_ID=... ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_KEY_PATH=~/AuthKey_XXXX.p8 ./testflight.sh   # CI, no Xcode login
#   TEAM_ID=... UPLOAD=0 ./testflight.sh                   # archive and export an .ipa only, no upload
set -euo pipefail

: "${TEAM_ID:?set TEAM_ID to your Apple Developer team ID (developer.apple.com > Membership)}"
BUNDLE_ID=${BUNDLE_ID:-app.labelsage.ios}
BUILD_NUMBER=${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}   # must grow with every upload
UPLOAD=${UPLOAD:-1}
OUT=${OUT:-build/testflight}
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}

cd "$(dirname "$0")"
xcodegen generate

AUTH=()
if [ -n "${ASC_KEY_ID:-}" ]; then
  AUTH=(-authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID" -authenticationKeyPath "$ASC_KEY_PATH")
fi

rm -rf "$OUT"
xcodebuild -project LabelSage.xcodeproj -scheme LabelSage -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$OUT/LabelSage.xcarchive" \
  -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"} \
  DEVELOPMENT_TEAM="$TEAM_ID" PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  archive

OPTIONS="$OUT/ExportOptions.plist"
cp ExportOptions.plist "$OPTIONS"
/usr/libexec/PlistBuddy -c "Add :teamID string $TEAM_ID" "$OPTIONS"
[ "$UPLOAD" = 1 ] || /usr/libexec/PlistBuddy -c "Set :destination export" "$OPTIONS"

xcodebuild -exportArchive -archivePath "$OUT/LabelSage.xcarchive" -exportPath "$OUT/export" \
  -exportOptionsPlist "$OPTIONS" -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"}

if [ "$UPLOAD" = 1 ]; then
  echo "Uploaded build $BUILD_NUMBER. It shows in App Store Connect > TestFlight after processing (about 5-30 min)."
else
  echo "Exported $OUT/export/LabelSage.ipa (build $BUILD_NUMBER); upload it with Transporter."
fi
