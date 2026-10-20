#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
name=$(python3 -c 'import json;print(json.load(open("Config/project.json"))["name"])')
bundle=$(python3 -c 'import json;print(json.load(open("Config/project.json"))["bundleIdentifier"])')
device=$(xcrun simctl list --json | python3 -c '
import json,subprocess,sys
inventory=json.load(sys.stdin)
runtimes=[r for r in inventory["runtimes"] if r.get("isAvailable") and ".iOS-" in r["identifier"]]
if not runtimes: sys.exit("No available iOS simulator runtime")
runtime=max(runtimes,key=lambda r:tuple(map(int,r["version"].split("."))))
phones=[d for d in inventory["devicetypes"] if d["name"].startswith("iPhone")]
phone=next((d for d in phones if d["name"]=="iPhone 17"),phones[-1])
print(subprocess.check_output(["xcrun","simctl","create","FlowPaste Test",phone["identifier"],runtime["identifier"]],text=True,timeout=60).strip())
')
trap 'python3 - "$device" <<"PY"
import subprocess,sys
for action in ["shutdown","delete"]:
    try: subprocess.run(["xcrun","simctl",action,sys.argv[1]],timeout=20,check=False)
    except subprocess.TimeoutExpired: pass
PY' EXIT
echo "Building for simulator $device"
xcodebuild -project "$name.xcodeproj" -scheme "$name" -configuration Debug \
 -sdk iphonesimulator -destination "id=$device" -derivedDataPath build/Simulator \
 CODE_SIGNING_ALLOWED=NO build
python3 - "$device" <<'PY'
import subprocess,sys
print('Booting fresh simulator',sys.argv[1],flush=True)
subprocess.run(['xcrun','simctl','boot',sys.argv[1]],check=True,timeout=120)
subprocess.run(['xcrun','simctl','bootstatus',sys.argv[1],'-b'],check=True,timeout=240)
PY
xcrun simctl status_bar "$device" override --time '9:41' --batteryState charged --batteryLevel 100
mkdir -p build/smoke
xcodebuild -project "$name.xcodeproj" -scheme "$name" -configuration Debug \
 -destination "id=$device" -derivedDataPath build/Simulator \
 -resultBundlePath build/smoke/WorkflowTests.xcresult -parallel-testing-enabled NO \
 -destination-timeout 60 CODE_SIGNING_ALLOWED=NO test
xcrun simctl install "$device" "build/Simulator/Build/Products/Debug-iphonesimulator/$name.app"
xcrun simctl launch "$device" "$bundle"
sleep 5
mkdir -p build/smoke
xcrun simctl io "$device" screenshot build/smoke/launch.png
xcrun simctl terminate "$device" "$bundle"
xcrun simctl launch "$device" "$bundle"
