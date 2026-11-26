"""Print an available iPhone Simulator destination for xcodebuild."""

import argparse
import json
import re
import subprocess


def ios_destination(devices_by_runtime, ios_version=None):
    for runtime, devices in devices_by_runtime.items():
        match = re.search(r"\.iOS-([0-9]+(?:-[0-9]+)*)", runtime)
        if not match:
            continue
        version = match[1].replace("-", ".")
        if ios_version and version != ios_version and not version.startswith(ios_version + "."):
            continue
        for device in devices:
            if device["name"].startswith("iPhone") and device.get("isAvailable"):
                return "platform=iOS Simulator,id=" + device["udid"]
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ios-version", help="iOS version or version prefix, for example 18 or 18.6")
    args = parser.parse_args()
    state = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "--json"]))
    destination = ios_destination(state["devices"], args.ios_version)
    if not destination:
        version = f" {args.ios_version}" if args.ios_version else ""
        raise SystemExit(f"No available iPhone Simulator with iOS{version}; install a matching runtime in Xcode Settings.")
    print(destination)


if __name__ == "__main__":
    main()
