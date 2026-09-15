#!/bin/bash
set -euo pipefail

# Called before signing the standalone learning application.
# Do not copy the room animation, sleeping/reading art, or sample audio.
script_directory="$(cd "$(dirname "$0")" && pwd)"
source_directory="$script_directory/../Vendor/AvatarMotion/Assets"
resource_directory="${1:?Usage: prepare-guide-resources.sh APP_CONTENTS_RESOURCES_DIRECTORY}"
guide_directory="$resource_directory/GuideAssets"
mkdir -p "$guide_directory"
for filename in rig.json standing.png standing-front-hands.png standing-back-hands.png standing-blink.png; do
  cp "$source_directory/$filename" "$guide_directory/$filename"
done
