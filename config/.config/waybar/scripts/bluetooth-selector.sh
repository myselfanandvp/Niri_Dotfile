#!/bin/bash

# Enhanced Rofi Bluetooth Device Selector for Waybar
# Save this as ~/.config/waybar/scripts/bluetooth-selector.sh

# File to store last connected device
LAST_DEVICE_FILE="$HOME/.cache/bluetooth-last-device"

# Function to check if bluetooth is powered on
is_powered_on() {
    bluetoothctl show | grep -q "Powered: yes"
}

# Function to check if a device is connected
is_connected() {
    local mac=$1
    bluetoothctl info "$mac" | grep -q "Connected: yes"
}

# Function to get device status
get_device_status() {
    local mac=$1
    if is_connected "$mac"; then
        echo "connected"
    else
        echo "disconnected"
    fi
}

# Function to save last connected device
save_last_device() {
    local mac=$1
    echo "$mac" > "$LAST_DEVICE_FILE"
}

# Function to get last connected device
get_last_device() {
    if [ -f "$LAST_DEVICE_FILE" ]; then
        cat "$LAST_DEVICE_FILE"
    fi
}

# Function to auto-connect to last device
auto_connect_last() {
    if ! is_powered_on; then
        return 1
    fi
    
    local last_mac=$(get_last_device)
    if [ -z "$last_mac" ]; then
        return 1
    fi
    
    # Check if device is available
    if bluetoothctl devices | grep -q "$last_mac"; then
        if ! is_connected "$last_mac"; then
            local device_name=$(bluetoothctl devices | grep "$last_mac" | awk '{for(i=3;i<=NF;i++) printf $i" "; print ""}' | sed 's/ $//')
            bluetoothctl connect "$last_mac" &>/dev/null
            if command -v notify-send &> /dev/null; then
                notify-send "Bluetooth" "Auto-connecting to $device_name"
            fi
        fi
    fi
}

# Main logic based on argument
case "$1" in
    "toggle")
        # Toggle bluetooth power (for left-click)
        if is_powered_on; then
            # Turn off
            rfkill unblock bluetooth 2>/dev/null
            bluetoothctl power off 2>/dev/null
            if command -v notify-send &> /dev/null; then
                notify-send "Bluetooth" "Powered off"
            fi
        else
            # Turn on - use rfkill first to unblock
            rfkill unblock bluetooth 2>/dev/null
            sleep 0.5
            bluetoothctl power on 2>/dev/null
            sleep 0.5
            if is_powered_on; then
                if command -v notify-send &> /dev/null; then
                    notify-send "Bluetooth" "Powered on"
                fi
                # Auto-connect to last device
                auto_connect_last
            else
                # Try using systemctl if bluetoothctl fails
                sudo systemctl restart bluetooth 2>/dev/null
                sleep 1
                bluetoothctl power on 2>/dev/null
                if command -v notify-send &> /dev/null; then
                    notify-send "Bluetooth" "Attempting to power on..."
                fi
            fi
        fi
        ;;
        
    "menu")
        # Show device menu (for right-click)
        if ! is_powered_on; then
            choice=$(echo -e "Power On Bluetooth" | rofi -dmenu -i -p "Bluetooth is OFF")
            if [ "$choice" = "Power On Bluetooth" ]; then
                bluetoothctl power on
                sleep 1
            else
                exit 0
            fi
        fi
        
        # Start scanning in background
        if command -v notify-send &> /dev/null; then
            notify-send "Bluetooth" "Scanning for devices..."
        fi
        bluetoothctl --timeout 5 scan on &>/dev/null &
        sleep 2
        
        # Get all known devices (paired + discovered)
        devices_list=$(bluetoothctl devices | sort -u)
        
        if [ -z "$devices_list" ]; then
            echo "No devices found" | rofi -dmenu -p "Bluetooth"
            exit 0
        fi
        
        # Build menu with device status and add rescan option
        menu_items="🔄 Rescan Devices\n"
        while IFS= read -r device; do
            mac=$(echo "$device" | awk '{print $2}')
            name=$(echo "$device" | awk '{for(i=3;i<=NF;i++) printf $i" "; print ""}' | sed 's/ $//')
            
            status=$(get_device_status "$mac")
            
            if [ "$status" = "connected" ]; then
                menu_items+="[●] $name\n"
            else
                menu_items+="[ ] $name\n"
            fi
        done <<< "$devices_list"
        
        # Show menu
        selected=$(echo -e "$menu_items" | rofi -dmenu -i -p "Bluetooth Devices")
        
        # Handle rescan option
        if [ "$selected" = "🔄 Rescan Devices" ]; then
            if command -v notify-send &> /dev/null; then
                notify-send "Bluetooth" "Rescanning for devices..."
            fi
            
            # Clear old scan results and start fresh scan
            bluetoothctl scan on &
            scan_pid=$!
            sleep 5
            kill $scan_pid 2>/dev/null
            
            if command -v notify-send &> /dev/null; then
                notify-send "Bluetooth" "Scan complete, refreshing list..."
            fi
            
            # Reopen menu after scan with updated list
            exec "$0" menu
            exit 0
        fi
        
        if [ -n "$selected" ]; then
            # Extract device name (remove status prefix)
            device_name=$(echo "$selected" | sed 's/^\[.\] //')
            
            # Get MAC address
            mac=$(bluetoothctl devices | grep "$device_name" | awk '{print $2}')
            
            if [ -z "$mac" ]; then
                echo "Device not found" | rofi -dmenu -p "Error"
                exit 1
            fi
            
            # Show action menu for the selected device
            if is_connected "$mac"; then
                action=$(echo -e "Disconnect\nForget Device" | rofi -dmenu -i -p "$device_name")
            else
                action=$(echo -e "Connect\nForget Device" | rofi -dmenu -i -p "$device_name")
            fi
            
            case "$action" in
                "Connect")
                    # Connect (pair first if not paired)
                    if ! bluetoothctl info "$mac" | grep -q "Paired: yes"; then
                        bluetoothctl pair "$mac"
                        bluetoothctl trust "$mac"
                    fi
                    bluetoothctl connect "$mac"
                    if command -v notify-send &> /dev/null; then
                        notify-send "Bluetooth" "Connecting to $device_name"
                    fi
                    # Save as last connected device
                    save_last_device "$mac"
                    ;;
                    
                "Disconnect")
                    bluetoothctl disconnect "$mac"
                    if command -v notify-send &> /dev/null; then
                        notify-send "Bluetooth" "Disconnected from $device_name"
                    fi
                    ;;
                    
                "Forget Device")
                    # Confirm before forgetting
                    confirm=$(echo -e "Yes\nNo" | rofi -dmenu -i -p "Forget $device_name?")
                    if [ "$confirm" = "Yes" ]; then
                        # Disconnect first if connected
                        if is_connected "$mac"; then
                            bluetoothctl disconnect "$mac" &>/dev/null
                        fi
                        # Remove device
                        bluetoothctl remove "$mac"
                        if command -v notify-send &> /dev/null; then
                            notify-send "Bluetooth" "Forgot $device_name"
                        fi
                        # Clear from last device if it was the last one
                        if [ "$(get_last_device)" = "$mac" ]; then
                            rm -f "$LAST_DEVICE_FILE"
                        fi
                    fi
                    ;;
            esac
        fi
        ;;
        
    *)
        echo "Usage: $0 {toggle|menu}"
        echo "  toggle - Toggle bluetooth power on/off"
        echo "  menu   - Show device selection menu"
        exit 1
        ;;
esac