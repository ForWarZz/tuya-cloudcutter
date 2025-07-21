#!/usr/bin/env bash

# ✅ Alpine OK : 'date' est disponible via coreutils
TIMESTAMP=$(date +%s)
LOGFILE="logs/log-${TIMESTAMP}.log"
FLASH_TIMEOUT=15

# ✅ Fonction auxiliaire inchangée (compatible bash)
function getopts-extra () {
    declare i=1
    while [[ ${OPTIND} -le $# && ${!OPTIND:0:1} != '-' ]]; do
        OPTARG[i]=${!OPTIND}
        let i++ OPTIND++
    done
}

# ✅ Parsing des arguments : inchangé
while getopts "hrntvw:p:f:d:l:s::a:k:u:o:" flag; do
    case "$flag" in
        r)	RESETNM="true" ;;
        n)  DISABLE_RESCAN="true" ;;
        v)  VERBOSE_OUTPUT="true" ;;
        w)	WIFI_ADAPTER=${OPTARG} ;;
        p)	PROFILE=${OPTARG} ;;
        f)	FIRMWARE=${OPTARG}
            METHOD_FLASH="true"
            ;;
        t)  FLASH_TIMEOUT=${OPTARG} ;;
        d)	DEVICEID=${OPTARG} ;;
        l)	LOCALKEY=${OPTARG} ;;
        a)  AUTHKEY=${OPTARG} ;;
        k)  PSKKEY=${OPTARG} ;;
        u)  UUID=${OPTARG} ;;
        o)  OVERRIDE_AP_SSID=${OPTARG} ;;
        s)	getopts-extra "$@"
            METHOD_DETACH="true"
            HAVE_SSID="true"
            SSID_ARGS=( "${OPTARG[@]}" )
            SSID=${SSID_ARGS[0]}
            SSID_PASS=${SSID_ARGS[1]}
            ;;
        h)
            echo "usage: $0 [OPTION]..."
            echo "  -h                Show this message"
            echo "  -r                Reset NetworkManager"
            echo "  -n                No Rescan (for older versions of nmcli that don't support it)"
            echo "  -o TEXT           Override specific device AP name to connect to"
            echo "  -v                Verbose log output"
            echo "  -w TEXT           WiFi adapter name (optional)"
            echo "  -p TEXT           Device profile name"
            echo "  -a TEXT           AuthKey (requires UUID + PSKKey)"
            echo "  -k TEXT           PSKKey (requires UUID + AuthKey)"
            echo "  -u TEXT           UUID (requires PSKKey + AuthKey)"
            echo "==== Detaching Only ===="
            echo "  -s SSID PASSWORD  Wifi SSID and Password for detaching"
            echo "  -d TEXT           New device id"
            echo "  -l TEXT           New local key"
            echo "==== Flashing Only ===="
            echo "  -f TEXT           Firmware filename in /custom-firmware/"
            echo "  -t SECONDS        Timeout (default: 15)"
            exit 0
    esac
done

# ❌ Incompatible combinaison
if [ "$METHOD_DETACH" ] && [ "$METHOD_FLASH" ]; then
    echo "You can't detach and flash at the same time."
    exit 1
fi

source common.sh
run_helper_script "pre-setup"

# 🧠 Choix de méthode si rien passé
if [ -z "$METHOD_DETACH" ] && [ -z "$METHOD_FLASH" ]; then
    PS3="[?] Select your desired operation [1/2]: "
    select method in "Detach from the cloud" "Flash 3rd Party Firmware"; do
        case $REPLY in
            1) METHOD_DETACH="true"; break ;;
            2) METHOD_FLASH="true"; break ;;
        esac
    done
fi

# 🧠 Récupération interactive des identifiants WiFi
if [ "$METHOD_DETACH" ] && [ -z "$HAVE_SSID" ]; then
    echo "Detaching requires an SSID and Password."
    read -p "Please enter your SSID: " SSID
    read -s -p "Please enter your Password: " SSID_PASS
    echo ""
fi

echo "Loading options, please wait..."

source common_run.sh

if [ "$METHOD_DETACH" ]; then
    echo "Cutting device off from cloud..."

    # ✅ REMPLACEMENT : pas de systemd sous Alpine
    nmcli device set "$WIFI_ADAPTER" managed no
    rc-service NetworkManager stop 2>/dev/null || service NetworkManager stop

    trap 'service NetworkManager start; nmcli device set "$WIFI_ADAPTER" managed yes' EXIT

    INNER_SCRIPT=$(xargs -0 <<- EOF
        SSID='${SSID//\'/\'\"\'\"\'}'
        SSID_PASS='${SSID_PASS//\'/\'\"\'\"\'}'
        bash /src/setup_apmode.sh ${WIFI_ADAPTER} ${VERBOSE_OUTPUT}
        pipenv run python3 -m cloudcutter configure_local_device --ssid "\${SSID}" --password "\${SSID_PASS}" "${PROFILE}" "/work/device-profiles/schema" "${CONFIG_DIR}" ${FLASH_TIMEOUT} "${VERBOSE_OUTPUT}"
EOF
    )
    run_in_docker bash -c "$INNER_SCRIPT"

    if [ $? -ne 0 ]; then
        echo "Something went wrong detaching from the cloud."
        [ -z "$VERBOSE_OUTPUT" ] && echo "Try with -v to get more logs."
        exit 1
    fi
fi

if [ "$METHOD_FLASH" ]; then
    echo "Flashing custom firmware..."

    nmcli device set "$WIFI_ADAPTER" managed no
    trap 'nmcli device set "$WIFI_ADAPTER" managed yes' EXIT

    run_in_docker bash -c "
        bash /src/setup_apmode.sh ${WIFI_ADAPTER} ${VERBOSE_OUTPUT} &&
        pipenv run python3 -m cloudcutter update_firmware \
            \"${PROFILE}\" \"/work/device-profiles/schema\" \
            \"${CONFIG_DIR}\" \"/work/custom-firmware/\" \
            \"${FIRMWARE}\" \"${FLASH_TIMEOUT}\" \"${VERBOSE_OUTPUT}\""

    if [ $? -ne 0 ]; then
        echo "Firmware flashing failed."
        [ -z "$VERBOSE_OUTPUT" ] && echo "Try again with -v for logs."
        exit 1
    fi
fi

run_helper_script "post-flash"
