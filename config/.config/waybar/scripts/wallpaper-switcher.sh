#!/bin/bash

# Wallpaper Switcher for Niri with swaybg
# Usage: ./wallpaper-switcher.sh [next|prev|random|set <path>]

WALLPAPER_DIR="${HOME}/.config/niri/wallpaper"
STATE_FILE="${HOME}/.config/niri/current_wallpaper"
SWAYBG_PID_FILE="/tmp/swaybg.pid"

# Create wallpaper directory if it doesn't exist
mkdir -p "$WALLPAPER_DIR"
mkdir -p "$(dirname "$STATE_FILE")"

# Function to kill existing swaybg instance
kill_swaybg() {
    if [ -f "$SWAYBG_PID_FILE" ]; then
        kill $(cat "$SWAYBG_PID_FILE") 2>/dev/null
        rm -f "$SWAYBG_PID_FILE"
    fi
    # Fallback: kill any remaining swaybg processes
    pkill -9 swaybg 2>/dev/null
}

# Function to set wallpaper
set_wallpaper() {
    local wallpaper="$1"
    
    if [ ! -f "$wallpaper" ]; then
        echo "Error: Wallpaper file not found: $wallpaper"
        return 1
    fi
    
    # Kill existing swaybg
    kill_swaybg
    
    # Start new swaybg instance
    swaybg -i "$wallpaper" -m fill &
    echo $! > "$SWAYBG_PID_FILE"
    
    # Save current wallpaper to state file
    echo "$wallpaper" > "$STATE_FILE"
    
    echo "Wallpaper set to: $wallpaper"
}

# Function to get list of wallpapers
get_wallpapers() {
    find "$WALLPAPER_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) | sort
}

# Function to get current wallpaper index
get_current_index() {
    local current_wallpaper="$1"
    local wallpapers=("${@:2}")
    
    for i in "${!wallpapers[@]}"; do
        if [ "${wallpapers[$i]}" = "$current_wallpaper" ]; then
            echo "$i"
            return
        fi
    done
    echo "0"
}

# Main logic
case "${1:-next}" in
    next)
        wallpapers=($(get_wallpapers))
        if [ ${#wallpapers[@]} -eq 0 ]; then
            echo "No wallpapers found in $WALLPAPER_DIR"
            exit 1
        fi
        
        current_wallpaper=$(cat "$STATE_FILE" 2>/dev/null)
        current_index=$(get_current_index "$current_wallpaper" "${wallpapers[@]}")
        next_index=$(( (current_index + 1) % ${#wallpapers[@]} ))
        
        set_wallpaper "${wallpapers[$next_index]}"
        ;;
        
    prev)
        wallpapers=($(get_wallpapers))
        if [ ${#wallpapers[@]} -eq 0 ]; then
            echo "No wallpapers found in $WALLPAPER_DIR"
            exit 1
        fi
        
        current_wallpaper=$(cat "$STATE_FILE" 2>/dev/null)
        current_index=$(get_current_index "$current_wallpaper" "${wallpapers[@]}")
        prev_index=$(( (current_index - 1 + ${#wallpapers[@]}) % ${#wallpapers[@]} ))
        
        set_wallpaper "${wallpapers[$prev_index]}"
        ;;
        
    random)
        wallpapers=($(get_wallpapers))
        if [ ${#wallpapers[@]} -eq 0 ]; then
            echo "No wallpapers found in $WALLPAPER_DIR"
            exit 1
        fi
        
        random_index=$((RANDOM % ${#wallpapers[@]}))
        set_wallpaper "${wallpapers[$random_index]}"
        ;;
        
    set)
        if [ -z "$2" ]; then
            echo "Usage: $0 set <wallpaper_path>"
            exit 1
        fi
        set_wallpaper "$2"
        ;;
        
    restore)
        # Restore last wallpaper (use this in your Niri startup)
        if [ -f "$STATE_FILE" ]; then
            wallpaper=$(cat "$STATE_FILE")
            if [ -f "$wallpaper" ]; then
                set_wallpaper "$wallpaper"
            else
                echo "Saved wallpaper not found, selecting first available"
                wallpapers=($(get_wallpapers))
                if [ ${#wallpapers[@]} -gt 0 ]; then
                    set_wallpaper "${wallpapers[0]}"
                fi
            fi
        else
            echo "No saved wallpaper, selecting first available"
            wallpapers=($(get_wallpapers))
            if [ ${#wallpapers[@]} -gt 0 ]; then
                set_wallpaper "${wallpapers[0]}"
            fi
        fi
        ;;
        
    *)
        echo "Usage: $0 [next|prev|random|set <path>|restore]"
        exit 1
        ;;
esac