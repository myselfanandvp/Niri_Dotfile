#!/bin/bash

# Battery Daemon - Monitors battery and charging status
# Author: Your setup

CRITICAL=15
LOW=30
COOLDOWN=300
LAST_LOW_ALERT=0
PREV_STATUS=""

# Ensure notify-send works with systemd
export DISPLAY=:0
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

get_battery_info() {
    BATTERY=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -n1)
    STATUS=$(cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -n1)
}

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> ~/.local/log/battery-daemon.log
}

while true; do
    get_battery_info
    CURRENT_TIME=$(date +%s)
    
    # Detect status changes (plug/unplug)
    if [[ "$STATUS" != "$PREV_STATUS" ]] && [[ -n "$PREV_STATUS" ]]; then
        if [[ "$STATUS" == "Charging" ]]; then
            notify-send -u normal "⚡ Power Connected" \
                "Battery: ${BATTERY}% - Charging..." \
                -i battery-charging -t 3000
            paplay /usr/share/sounds/freedesktop/stereo/power-plug.oga 2>/dev/null &
            log_message "Power connected - Battery: ${BATTERY}%"
            
        elif [[ "$STATUS" == "Discharging" ]]; then
            notify-send -u normal "🔌 Power Disconnected" \
                "Battery: ${BATTERY}% - On battery power" \
                -i battery -t 3000
            paplay /usr/share/sounds/freedesktop/stereo/power-unplug.oga 2>/dev/null &
            log_message "Power disconnected - Battery: ${BATTERY}%"
            
        elif [[ "$STATUS" == "Full" ]]; then
            notify-send -u low "🔋 Battery Full" \
                "Battery fully charged (100%)" \
                -i battery-full-charged -t 3000
            paplay /usr/share/sounds/freedesktop/stereo/complete.oga 2>/dev/null &
            log_message "Battery full"
        fi
    fi
    
    # Low battery alerts (only when discharging)
    if [[ "$STATUS" == "Discharging" ]]; then
        TIME_SINCE_ALERT=$((CURRENT_TIME - LAST_LOW_ALERT))
        
        if [ "$BATTERY" -le "$CRITICAL" ] && [ $TIME_SINCE_ALERT -ge $COOLDOWN ]; then
            notify-send -u critical "🔋 BATTERY CRITICAL!" \
                "Only ${BATTERY}% remaining!\n⚠️  PLUG IN CHARGER NOW!" \
                -i battery-caution -t 0
            paplay /usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga 2>/dev/null &
            log_message "CRITICAL: Battery at ${BATTERY}%"
            LAST_LOW_ALERT=$CURRENT_TIME
            
        elif [ "$BATTERY" -le "$LOW" ] && [ $TIME_SINCE_ALERT -ge $COOLDOWN ]; then
            notify-send -u normal "🔋 Battery Low" \
                "${BATTERY}% remaining - Consider charging soon" \
                -i battery-low -t 5000
            paplay /usr/share/sounds/freedesktop/stereo/dialog-warning.oga 2>/dev/null &
            log_message "LOW: Battery at ${BATTERY}%"
            LAST_LOW_ALERT=$CURRENT_TIME
        fi
    fi
    
    PREV_STATUS="$STATUS"
    sleep 5
done
