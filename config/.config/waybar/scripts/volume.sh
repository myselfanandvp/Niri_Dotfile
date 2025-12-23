#!/bin/bash
# ~/.config/waybar/scripts/volume.sh
# Optimized version with locking and efficient commands

# Prevent multiple simultaneous instances
exec 200>/tmp/waybar-volume.lock
flock -n 200 || exit 0

case "$1" in
  up)
    wpctl set-volume -l 1.0 @DEFAULTAUDIO_SINK@ 5%+
swayosd-client --output-volume raise
    ;;
  down)
    wpctl  set-volume @DEFAULT_AUDIO_SINK@ 5%-
swayosd-client --output-volume lower
    ;;
  mute)
    wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
swayosd-client --output-volume mute
    ;;
esac

# Release lock automatically when script exits
