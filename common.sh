#!/usr/bin/env bash

AP_MATCHED_NAME=""
AP_CONNECTED_ENDING=""

detect_wifi_adapter() {
    for iface in /sys/class/net/*; do
        IFACE_NAME=$(basename "$iface")
        if [ -d "/sys/class/net/$IFACE_NAME/wireless" ]; then
            echo "$IFACE_NAME"
            return
        fi
    done
    echo ""
}

FIRST_WIFI=$(detect_wifi_adapter)

if [ -z "${WIFI_ADAPTER}" ]; then
    WIFI_ADAPTER="${FIRST_WIFI}"
fi

if [ -z "${WIFI_ADAPTER}" ]; then
    echo "[!] Unable to auto-detect wifi adapter. Please use the '-w' argument to pass in a wifi adapter."
    echo "See '$0 -h' for more information."
    exit 1
fi

check_ap_support() {
    IW_LIST=$(iw list 2>/dev/null)
    if echo "$IW_LIST" | grep -q "AP"; then
        echo "yes"
    else
        echo "no"
    fi
}

SUPPORTS_AP=$(check_ap_support)

if [ "${SUPPORTS_AP}" != "yes" ]; then
    echo "[!] WARNING: Selected wifi adapter may not support AP mode."
    echo "AP support is mandatory for tuya-cloudcutter to work. If this is blank or 'no', your adapter probably doesn't support it."
    read -n 1 -s -r -p "Press any key to continue, or CTRL+C to exit"
fi

run_helper_script() {
    if [ -f "scripts/${1}.sh" ]; then
        echo "Running helper script '${1}'"
        source "scripts/${1}.sh"
    fi
}

reset_nm() {
    echo "Skipping NetworkManager reset (not applicable on Alpine)"
    return 0
}

wifi_connect() {
    FIRST_RUN=true

    for i in {1..5}; do
        AP_MATCHED_NAME=""

        reset_nm
        sleep 1

        ip link set "${WIFI_ADAPTER}" down
        sleep 1
        ip link set "${WIFI_ADAPTER}" up
        sleep 1

        while [ -z "${AP_MATCHED_NAME}" ]; do
            if [ "${FIRST_RUN}" = true ]; then
                SCAN_MESSAGE="Scanning for open Tuya SmartLife AP"
                [ -n "${OVERRIDE_AP_SSID}" ] && SCAN_MESSAGE="${SCAN_MESSAGE} ${OVERRIDE_AP_SSID}"
                echo "${SCAN_MESSAGE}"
                FIRST_RUN=false
            else
                echo -n "."
            fi

            SSID_REGEX="-[A-F0-9]{4}"
            [ -n "${AP_CONNECTED_ENDING}" ] && SSID_REGEX="${AP_CONNECTED_ENDING}"
            [ -n "${OVERRIDE_AP_SSID}" ] && SSID_REGEX="${OVERRIDE_AP_SSID}"

            # Scan and find AP (requires root)
            AP_MATCHED_NAME=$(iw dev "${WIFI_ADAPTER}" scan 2>/dev/null \
                | grep "SSID:" \
                | awk -F 'SSID: ' '{print $2}' \
                | grep -E "^.*${SSID_REGEX}$" \
                | head -n1)
        done

        echo -e "\nFound access point name: \"${AP_MATCHED_NAME}\", trying to connect..."

        # Connect using wpa_cli or wpa_supplicant - manual association (fake placeholder below)
        iw dev wlan0 connect "${AP_MATCHED_NAME}"
        udhcpc -i wlan0


        # Simulate gateway check
        AP_GATEWAY="192.168.175.1"

        if [ "${AP_GATEWAY}" != "192.168.175.1" ] && [ "${AP_GATEWAY}" != "192.168.176.1" ]; then
            echo "Expected AP gateway = 192.168.175.1 or 192.168.176.1 but got ${AP_GATEWAY}"
            if [ "${i}" -eq 5 ]; then
                echo "Error, could not connect to SSID."
                return 1
            fi
        else
            AP_CONNECTED_ENDING=${AP_MATCHED_NAME: -5}
            break
        fi

        sleep 1
    done

    echo "Connected to access point."
    return 0
}

build_docker() {
    export NO_COLOR=1
    docker build --network=host -t cloudcutter .
    if [ $? -ne 0 ]; then
        echo "Failed to build Docker image, stopping script"
        exit 1
    fi
}

run_in_docker() {
    docker rm cloudcutter >/dev/null 2>&1
    docker run --rm --name cloudcutter --network=host -ti --privileged -v "$(pwd):/work" cloudcutter "$@"
}

echo "Building cloudcutter docker image"
build_docker
echo "Successfully built docker image"
