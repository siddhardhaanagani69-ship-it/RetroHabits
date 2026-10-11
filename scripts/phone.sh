#!/bin/zsh
# Build RetroHabits, install it on the connected iPhone and launch it.
# The assistant server token is read from backend/.env and baked into this
# build only (Info.plist AssistantToken) — it never enters the repo.
set -e
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
PHONE=$(xcrun devicectl list devices 2>/dev/null | awk '(/connected/ || /available/) && !/unavailable/ && /physical/ && /iPhone/ {for (i=1;i<=NF;i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) print $i; exit}')
[[ -n "$PHONE" ]] || { echo "No iPhone connected"; exit 1; }
TOKEN=$(backend/.venv/bin/python -c "from dotenv import dotenv_values; print(dotenv_values('backend/.env').get('API_TOKEN') or '')")
# Outside the (iCloud-synced) Desktop: synced folders add file attributes codesign rejects.
OUT=~/Library/Developer/Xcode/DerivedData/RetroHabits-phone
xcodebuild -project RetroHabits.xcodeproj -scheme RetroHabits -destination "id=$PHONE" \
  -derivedDataPath $OUT -allowProvisioningUpdates ASSISTANT_TOKEN="$TOKEN" -quiet build
xcrun devicectl device install app --device $PHONE $OUT/Build/Products/Debug-iphoneos/RetroHabits.app >/dev/null
xcrun devicectl device process launch --terminate-existing --device $PHONE com.sid.retrohabits >/dev/null \
  || echo "Installed. Unlock the phone and open RetroHabits."
echo "RetroHabits is on $PHONE"
