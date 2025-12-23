#!/bin/bash

# Enhanced WiFi Selector Script with Rofi
# Save this as ~/.config/waybar/scripts/wifi-selector.sh

# File to store last connected network
LAST_NETWORK_FILE="$HOME/.cache/wifi-last-network"

# Function to check if WiFi is powered on
is_powered_on() {
    nmcli radio wifi | grep -q "enabled"
}

# Function to check if a network is connected
is_connected() {
    local ssid=$1
    nmcli -t -f active,ssid dev wifi | grep "^yes:${ssid}$" &>/dev/null
}

# Function to get network status
get_network_status() {
    local ssid=$1
    if is_connected "$ssid"; then
        echo "connected"
    else
        echo "disconnected"
    fi
}

# Function to save last connected network
save_last_network() {
    local ssid=$1
    echo "$ssid" > "$LAST_NETWORK_FILE"
}

# Function to get last connected network
get_last_network() {
    if [ -f "$LAST_NETWORK_FILE" ]; then
        cat "$LAST_NETWORK_FILE"
    fi
}

# Function to check if network is saved
is_saved_network() {
    local ssid=$1
    nmcli -t -f NAME connection show | grep -q "^${ssid}$"
}

# Function to auto-connect to last network
auto_connect_last() {
    if ! is_powered_on; then
        return 1
    fi
    
    local last_ssid=$(get_last_network)
    if [ -z "$last_ssid" ]; then
        return 1
    fi
    
    # Check if network is saved and available
    if is_saved_network "$last_ssid"; then
        if ! is_connected "$last_ssid"; then
            # Check if network is in range
            if nmcli -f SSID device wifi list | grep -q "^${last_ssid}$"; then
                nmcli connection up "$last_ssid" &>/dev/null
                if command -v notify-send &> /dev/null; then
                    notify-send "📶 WiFi" "Auto-connecting to $last_ssid"
                fi
            fi
        fi
    fi
}

# Main logic based on argument
case "$1" in
    "toggle")
        # Toggle WiFi power (for left-click)
        if is_powered_on; then
            # Turn off
            nmcli radio wifi off
            if command -v notify-send &> /dev/null; then
                notify-send "📡 WiFi" "WiFi turned OFF"
            fi
        else
            # Turn on
            nmcli radio wifi on
            sleep 1
            if is_powered_on; then
                if command -v notify-send &> /dev/null; then
                    notify-send "📶 WiFi" "WiFi turned ON"
                fi
                # Auto-connect to last network
                auto_connect_last
            else
                if command -v notify-send &> /dev/null; then
                    notify-send "❌ WiFi" "Failed to turn on WiFi"
                fi
            fi
        fi
        ;;
        
    "menu")
        # Show network menu (for right-click)
        if ! is_powered_on; then
            choice=$(echo -e "Power On WiFi" | rofi -dmenu -i -p "WiFi is OFF" -theme-str 'window {width: 300px;}')
            if [ "$choice" = "Power On WiFi" ]; then
                nmcli radio wifi on
                sleep 1
            else
                exit 0
            fi
        fi
        
        # Get current connection
        current_ssid=$(nmcli -t -f active,ssid dev wifi | grep '^yes' | cut -d: -f2)
        
        # Main menu if already connected
        if [ -n "$current_ssid" ]; then
            # current_signal=$(nmcli -f SSID,SIGNAL dev wifi list | grep "^$current_ssid" | awk '{print $NF}')
            # current_speed=$(nmcli -f SSID,RATE dev wifi list | grep "^$current_ssid" | awk '{print $NF}')
            
            # main_menu=$(echo -e "📡 Disconnect from $current_ssid\n🗑️ Forget $current_ssid\n🔄 Rescan Networks\n📶 Connect to Different Network" | \
            #     rofi -dmenu -p "Connected: $current_ssid (${current_signal}%, ${current_speed})" \
            #     -theme-str 'window {width: 550px;}')
            
             main_menu=$(echo -e "📡 Disconnect from $current_ssid\n🗑️ Forget $current_ssid\n🔄 Rescan Networks\n📶 Connect to Different Network" | \
                rofi -dmenu -p "Connected: $current_ssid" -theme-str 'window {width: 550px;}')
                
            if [ -z "$main_menu" ]; then
                exit 0
            fi
            
            if [[ "$main_menu" =~ "Disconnect" ]]; then
                nmcli connection down "$current_ssid"
                if command -v notify-send &> /dev/null; then
                    notify-send "📡 Disconnected" "Disconnected from $current_ssid"
                fi
                exit 0
            elif [[ "$main_menu" =~ "Forget" ]]; then
                # Confirm before forgetting
                confirm=$(echo -e "Yes\nNo" | rofi -dmenu -i -p "Forget $current_ssid?" -theme-str 'window {width: 350px;}')
                if [ "$confirm" = "Yes" ]; then
                    nmcli connection delete "$current_ssid"
                    if command -v notify-send &> /dev/null; then
                        notify-send "🗑️ Forgotten" "Removed $current_ssid from saved networks"
                    fi
                    # Clear from last network if it was the last one
                    if [ "$(get_last_network)" = "$current_ssid" ]; then
                        rm -f "$LAST_NETWORK_FILE"
                    fi
                fi
                exit 0
            elif [[ "$main_menu" =~ "Rescan" ]]; then
                if command -v notify-send &> /dev/null; then
                    notify-send "🔄 Rescanning" "Searching for WiFi networks..." -t 2000
                fi
                nmcli device wifi rescan
                sleep 2
                # Restart the script to show updated list
                exec "$0" menu
            fi
        fi
        
        # Scan for networks automatically
        if command -v notify-send &> /dev/null; then
            notify-send "📶 Scanning" "Looking for WiFi networks..." -t 1500
        fi
        nmcli device wifi rescan
        
        # Wait for scan to complete
        for i in {1..3}; do
            sleep 0.5
            network_count=$(nmcli -f SSID device wifi list | tail -n +2 | grep -v '^$' | wc -l)
            if [ $network_count -gt 0 ]; then
                break
            fi
        done
        
        # Get saved connections
        saved_networks=$(nmcli -t -f NAME connection show | grep -v "lo\|Wired")
        
        # Build formatted network list with real-time data
        wifi_raw=$(nmcli -f SSID,SIGNAL,RATE,SECURITY device wifi list | tail -n +2)
        menu_items="🔄 Rescan Networks\n"
        network_count=0
        
        while IFS= read -r line; do
            ssid=$(echo "$line" | awk '{print $1}')
            signal=$(echo "$line" | awk '{print $2}')
            speed=$(echo "$line" | awk '{print $3, $4}')
            security=$(echo "$line" | awk '{for(i=5;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ *$//')
            
            # Skip empty SSIDs
            [ -z "$ssid" ] && continue
            
            network_count=$((network_count + 1))
            
            # Check if saved
            saved_mark=""
            if echo "$saved_networks" | grep -q "^${ssid}$"; then
                saved_mark="💾"
            fi
            
            # Format signal strength
            if [ "$signal" -ge 75 ]; then
                signal_icon="▰▰▰▰"
            elif [ "$signal" -ge 50 ]; then
                signal_icon="▰▰▰▱"
            elif [ "$signal" -ge 25 ]; then
                signal_icon="▰▰▱▱"
            else
                signal_icon="▰▱▱▱"
            fi
            
            # Format security
            if [ -z "$security" ] || [ "$security" == "--" ]; then
                sec_icon="🔓"
                security="Open"
            else
                sec_icon="🔒"
            fi
            
            # Build formatted line
            menu_items+="${saved_mark} ${signal_icon} ${ssid}  |  ${signal}%  |  ${speed}  |  ${sec_icon} ${security}\n"
        done <<< "$wifi_raw"
        
        # Update notification with scan results
        if command -v notify-send &> /dev/null; then
            notify-send "✅ Scan Complete" "Found $network_count WiFi networks" -t 2000
        fi
        
        # Show network selection menu
        selected=$(echo -e "$menu_items" | rofi -dmenu -i -p "Select WiFi Network" \
            -theme-str 'window {width: 700px;} listview {lines: 12;}' \
            -mesg "💾=Saved | Signal | SSID | Speed | Security")
        
        # Handle rescan option
        if [ "$selected" = "🔄 Rescan Networks" ]; then
            if command -v notify-send &> /dev/null; then
                notify-send "🔄 Rescanning" "Searching for WiFi networks..." -t 2000
            fi
            nmcli device wifi rescan
            sleep 2
            # Reopen menu after scan
            exec "$0" menu
            exit 0
        fi
        
        # Handle selection
        if [ -z "$selected" ]; then
            exit 0
        fi
        
        # Extract SSID from selection
        chosen_ssid=$(echo "$selected" | awk -F'|' '{print $1}' | sed 's/.*▱ //;s/.*▰ //;s/💾 //;s/^ *//;s/ *$//')
        
        # Check if network is saved (known)
        is_saved=0
        if is_saved_network "$chosen_ssid"; then
            is_saved=1
        fi
        
        # If network is saved, show connect/forget menu
        if [ $is_saved -eq 1 ]; then
            if is_connected "$chosen_ssid"; then
                action=$(echo -e "📡 Disconnect\n🗑️ Forget Network" | rofi -dmenu -p "$chosen_ssid (Connected)" \
                    -theme-str 'window {width: 400px;}')
            else
                action=$(echo -e "📶 Connect\n🗑️ Forget Network" | rofi -dmenu -p "$chosen_ssid (Saved)" \
                    -theme-str 'window {width: 400px;}')
            fi
            
            if [ -z "$action" ]; then
                exit 0
            fi
            
            case "$action" in
                *"Connect"*)
                    # Connect to saved network (no password needed)
                    if nmcli connection up "$chosen_ssid"; then
                        speed=$(nmcli -f SSID,RATE dev wifi list | grep "^$chosen_ssid" | awk '{print $NF}')
                        if command -v notify-send &> /dev/null; then
                            notify-send "📶 Connected" "Successfully connected to $chosen_ssid\nSpeed: $speed"
                        fi
                        # Save as last connected network
                        save_last_network "$chosen_ssid"
                    else
                        if command -v notify-send &> /dev/null; then
                            notify-send "❌ Connection Failed" "Could not connect to $chosen_ssid"
                        fi
                    fi
                    ;;
                    
                *"Disconnect"*)
                    nmcli connection down "$chosen_ssid"
                    if command -v notify-send &> /dev/null; then
                        notify-send "📡 Disconnected" "Disconnected from $chosen_ssid"
                    fi
                    ;;
                    
                *"Forget"*)
                    # Confirm before forgetting
                    confirm=$(echo -e "Yes\nNo" | rofi -dmenu -i -p "Forget $chosen_ssid?" -theme-str 'window {width: 350px;}')
                    if [ "$confirm" = "Yes" ]; then
                        # Disconnect first if connected
                        if is_connected "$chosen_ssid"; then
                            nmcli connection down "$chosen_ssid" &>/dev/null
                        fi
                        # Remove network
                        nmcli connection delete "$chosen_ssid"
                        if command -v notify-send &> /dev/null; then
                            notify-send "🗑️ Forgotten" "Removed $chosen_ssid from saved networks"
                        fi
                        # Clear from last network if it was the last one
                        if [ "$(get_last_network)" = "$chosen_ssid" ]; then
                            rm -f "$LAST_NETWORK_FILE"
                        fi
                    fi
                    ;;
            esac
        else
            # New network - check if password is needed
            security=$(echo "$selected" | awk -F'|' '{print $NF}' | sed 's/^ *//;s/ *$//')
            
            if [[ "$security" =~ "Open" ]]; then
                # Open network - connect directly
                if nmcli device wifi connect "$chosen_ssid"; then
                    speed=$(nmcli -f SSID,RATE dev wifi list | grep "^$chosen_ssid" | awk '{print $NF}')
                    if command -v notify-send &> /dev/null; then
                        notify-send "📶 Connected" "Successfully connected to $chosen_ssid\nSpeed: $speed"
                    fi
                    # Save as last connected network
                    save_last_network "$chosen_ssid"
                else
                    if command -v notify-send &> /dev/null; then
                        notify-send "❌ Connection Failed" "Could not connect to $chosen_ssid"
                    fi
                fi
            else
                # Secured network - ask for password
                password=$(rofi -dmenu -p "Password for $chosen_ssid" -password \
                    -theme-str 'window {width: 600px; height: 120px;} entry {placeholder: "Enter WiFi password";}')
                
                if [ -n "$password" ]; then
                    if nmcli device wifi connect "$chosen_ssid" password "$password"; then
                        speed=$(nmcli -f SSID,RATE dev wifi list | grep "^$chosen_ssid" | awk '{print $NF}')
                        if command -v notify-send &> /dev/null; then
                            notify-send "📶 Connected" "Successfully connected to $chosen_ssid\nSpeed: $speed"
                        fi
                        # Save as last connected network
                        save_last_network "$chosen_ssid"
                    else
                        if command -v notify-send &> /dev/null; then
                            notify-send "❌ Connection Failed" "Wrong password or connection error"
                        fi
                    fi
                fi
            fi
        fi
        ;;
        
    *)
        echo "Usage: $0 {toggle|menu}"
        echo "  toggle - Toggle WiFi power on/off"
        echo "  menu   - Show network selection menu"
        exit 1
        ;;
esac