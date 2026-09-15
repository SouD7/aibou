#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
profile_seconds="${1:-10}"
if [[ ! "$profile_seconds" =~ ^[0-9]+$ ]] || (( profile_seconds < 1 || profile_seconds > 60 )); then
  echo "Usage: $0 [seconds: 1..60]" >&2
  exit 2
fi
profile_pid="$(pgrep -x AIBOUGameLab | head -1 || true)"
if [[ -z "$profile_pid" ]]; then
  echo "Open game-lab/AIBOUGameLab.app before recording." >&2
  exit 1
fi
mkdir -p QA/profiles
profile_path="$PWD/QA/profiles/game-$(date +%Y%m%d-%H%M%S)-$$.trace"
xcrun xctrace record --template 'Time Profiler' --attach "$profile_pid" \
  --time-limit "${profile_seconds}s" --output "$profile_path"
xcrun xctrace export --input "$profile_path" --toc > "${profile_path%.trace}-toc.xml"
echo "Time Profiler trace: $profile_path"
