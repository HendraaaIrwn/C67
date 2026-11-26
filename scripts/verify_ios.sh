#!/usr/bin/env bash
# Run the same app verification locally and in promotion CI.
set -euo pipefail
cd "$(dirname "$0")/.."

C67_IOS_MODE=${1:-ios-smoke}
case "$C67_IOS_MODE" in
  check|ios-smoke|ios-full) ;;
  *) echo 'Usage: bash scripts/verify_ios.sh [check|ios-smoke|ios-full]' >&2; exit 2 ;;
esac

C67_XCODE_VERSION=$(xcodebuild -version)
printf '%s\n' "$C67_XCODE_VERSION"
if [[ -n ${C67_VERIFY_XCODE_VERSION:-} && ${C67_XCODE_VERSION%%$'\n'*} != "Xcode $C67_VERIFY_XCODE_VERSION" ]]; then
  echo "Expected Xcode $C67_VERIFY_XCODE_VERSION. Set DEVELOPER_DIR to that Xcode installation." >&2
  exit 2
fi
xcrun swift --version
echo "Simulator SDK: $(xcrun --sdk iphonesimulator --show-sdk-version)"
echo "Host architecture: $(uname -m)"

C67_DESTINATION_ARGS=()
if [[ -n ${C67_VERIFY_IOS_VERSION:-} ]]; then
  C67_DESTINATION_ARGS=(--ios-version "$C67_VERIFY_IOS_VERSION")
fi
if [[ -n ${C67_SIMULATOR_DESTINATION:-} && ${#C67_DESTINATION_ARGS[@]} -eq 0 ]]; then
  C67_DESTINATION=$C67_SIMULATOR_DESTINATION
elif [[ ${#C67_DESTINATION_ARGS[@]} -gt 0 ]]; then
  C67_DESTINATION=$(python3 scripts/simulator_destination.py "${C67_DESTINATION_ARGS[@]}")
else
  C67_DESTINATION=$(python3 scripts/simulator_destination.py)
fi
echo "Simulator destination: $C67_DESTINATION"
if [[ "$C67_IOS_MODE" == check ]]; then exit 0; fi

C67_XCODE_ARGS=(
  -project apps/ios/C67.xcodeproj -scheme C67 -destination "$C67_DESTINATION"
  -derivedDataPath "${C67_VERIFY_DERIVED_DATA:-/tmp/c67-local-checks}"
)
if [[ -n ${C67_VERIFY_RESULT_BUNDLE:-} ]]; then
  C67_XCODE_ARGS+=(-resultBundlePath "$C67_VERIFY_RESULT_BUNDLE")
fi
if [[ "$C67_IOS_MODE" == ios-smoke ]]; then
  C67_XCODE_ARGS+=(
    -only-testing:C67AppTests
    -only-testing:C67UITests/TripHomeUITests/testEmptyHomeNavigationAndPlanningEntry
    -only-testing:C67UITests/TripHomeUITests/testSavingMockProposalOpensTripAndReturnsHome
  )
fi
xcodebuild "${C67_XCODE_ARGS[@]}" CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- C67_DATA_MODE=mock test
