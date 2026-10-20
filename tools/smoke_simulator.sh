#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
name=$(python3 -c 'import json;print(json.load(open("Config/project.json"))["name"])')
bundle=$(python3 -c 'import json;print(json.load(open("Config/project.json"))["bundleIdentifier"])')
device=$(xcrun simctl list devices available --json | python3 -c '
import json,sys
devices=json.load(sys.stdin)["devices"]
phones=[d for runtime,items in devices.items() if "iOS" in runtime for d in items if d["name"].startswith("iPhone")]
if not phones: sys.exit("No available iPhone simulator")
print(phones[0]["udid"])
')
xcodebuild -project "$name.xcodeproj" -scheme "$name" -configuration Debug \
 -sdk iphonesimulator -destination "id=$device" -derivedDataPath build/Simulator \
 CODE_SIGNING_ALLOWED=NO build
xcrun simctl boot "$device"
trap 'xcrun simctl shutdown "$device"' EXIT
xcrun simctl bootstatus "$device" -b
xcrun simctl status_bar "$device" override --time '9:41' --batteryState charged --batteryLevel 100
mkdir -p build/smoke
xcodebuild -project "$name.xcodeproj" -scheme "$name" -configuration Debug \
 -destination "id=$device" -derivedDataPath build/Simulator \
 -resultBundlePath build/smoke/WorkflowTests.xcresult CODE_SIGNING_ALLOWED=NO test
xcrun simctl install "$device" "build/Simulator/Build/Products/Debug-iphonesimulator/$name.app"
xcrun simctl launch "$device" "$bundle"
sleep 5
mkdir -p build/smoke
xcrun simctl io "$device" screenshot build/smoke/launch.png
xcrun simctl terminate "$device" "$bundle"
xcrun simctl launch "$device" "$bundle"
