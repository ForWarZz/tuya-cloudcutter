#!/bin/bash

check_port () {
    protocol="$1"
    port="$2"
    reason="$3"
    echo -n "Checking ${protocol^^} port $port... "
    process_info=$(ss -lnp -A "$protocol" "sport = :$port" 2>/dev/null | grep -oE "pid=[0-9]+," | head -n1)

    if [ -n "$process_info" ]; then
        process_pid=$(echo "$process_info" | grep -oE "[0-9]+")
        process_name=$(ps -p "$process_pid" | awk 'NR==2 {print $5}')
        echo "Occupied by $process_name with PID $process_pid."
        echo "Port $port is needed to $reason"
        read -p "Do you wish to terminate $process_name? [y/N] " -n 1 -r
        echo
        if [[ "$REPLY" =~ ^[Ss]$ ]]; then
            echo "Skipping..."
            return
        fi
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Aborting due to occupied port"
            exit 1
        else
            echo "Attempting to terminate $process_name (PID $process_pid)"
            kill "$process_pid"
            sleep 1
            if kill -0 "$process_pid" 2>/dev/null; then
                echo "$process_name is still running, sending SIGKILL"
                kill -9 "$process_pid"
            fi
            sleep 1
        fi
    else
        echo "Available."
    fi
}

check_firewall () {
    if service iptables status &>/dev/null; then
        echo "Detected iptables rules. Attempting to flush..."
        iptables -F
        echo "Flushed iptables rules."
    fi
}

check_blacklist () {
    if [ -e /etc/modprobe.d/blacklist-rtl8192cu.conf ]; then
        echo "Detected /etc/modprobe.d/blacklist-rtl8192cu.conf"
        echo "This has been known to cause kernel panic in hostapd"
        echo "See https://github.com/ct-Open-Source/tuya-convert/issues/373"
        read -p "Do you wish to remove this file? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm /etc/modprobe.d/blacklist-rtl8192cu.conf
        fi
    fi
}

check_app_armor () {
    # AppArmor is not available under Alpine by default
    echo "Skipping AppArmor check (not applicable on Alpine)"
}

echo ""
echo "Performing safety checks to make sure all required ports are available"
check_port udp 53 "resolve DNS queries"
check_port udp 67 "offer DHCP leases"
check_port tcp 80 "answer HTTP requests"
check_port tcp 443 "answer HTTPS requests"
#check_port udp 6666 "detect unencrypted Tuya firmware"
#check_port udp 6667 "detect encrypted Tuya firmware"
check_port tcp 1883 "run MQTT"
check_port tcp 8886 "run MQTTS"
check_firewall
check_blacklist
check_app_armor
echo "Safety checks complete."
echo ""
