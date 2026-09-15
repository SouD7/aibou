#!/bin/bash
set -euo pipefail
EXHIBITION_SOURCE="$(cd "$(dirname "$0")/../Art/Exhibition" && pwd)"
EXHIBITION_DESTINATION="$1/ExhibitionArt"
mkdir -p "$EXHIBITION_DESTINATION"
for artwork in lobby area-a area-b area-c area-d area-e circuit-entry guide-notebook; do
  if [[ ! -s "$EXHIBITION_SOURCE/$artwork.png" ]]; then
    echo "Missing exhibition artwork: $artwork.png" >&2
    exit 1
  fi
  cp "$EXHIBITION_SOURCE/$artwork.png" "$EXHIBITION_DESTINATION/"
done
LESSON_SOURCE="$EXHIBITION_SOURCE/../Lessons"
mkdir -p "$1/LessonArt"
for artwork in welcome explaining celebrating; do
  if [[ ! -s "$LESSON_SOURCE/$artwork.png" ]]; then
    echo "Missing lesson artwork: $artwork.png" >&2
    exit 1
  fi
  cp "$LESSON_SOURCE/$artwork.png" "$1/LessonArt/"
done
mkdir -p "$EXHIBITION_DESTINATION/LobbyMotion"
for artwork in background blink; do
  if [[ ! -s "$EXHIBITION_SOURCE/LobbyMotion/$artwork.png" ]]; then
    echo "Missing lobby animation artwork: $artwork.png" >&2
    exit 1
  fi
  cp "$EXHIBITION_SOURCE/LobbyMotion/$artwork.png" "$EXHIBITION_DESTINATION/LobbyMotion/"
done
