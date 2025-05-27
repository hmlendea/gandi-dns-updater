#!/bin/bash

set -o nounset
set -o pipefail

API_KEY="${GANDI_API_KEY}"
FQN_DOMAIN="${1}"

[ -z "${API_KEY}" ] && API_KEY=$(<"/etc/gandi-dns-updater/api-key")

[ -z "${API_KEY}" ] && echo "ERROR: The API Key is missing!" && exit 1
[ -z "${FQN_DOMAIN}" ] && echo "ERROR: The domain name is missing!" && exit 1

if ! [[ "${FQN_DOMAIN}" =~ ^([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}$ ]]; then
    echo "ERROR: Invalid domain format: ${FQN_DOMAIN}"
    exit 1
fi

for COMMAND_DEPENDENCY in curl jq; do
    if ! command -v "${COMMAND_DEPENDENCY}" &>/dev/null; then
        echo "ERROR: Required command '${COMMAND_DEPENDENCY}' not found."
        exit 2
    fi
done

function normalise_ip_address() {
    local IP_ADDRESS="${1}"

    # Trim leading and trailing whitespace
    IP_ADDRESS="${IP_ADDRESS#"${IP_ADDRESS%%[![:space:]]*}"}"
    IP_ADDRESS="${IP_ADDRESS%"${IP_ADDRESS##*[![:space:]]}"}"

    echo "${IP_ADDRESS}"
}

function get_current_ip_address() {
    local IP_ADDRESS=""

    if command -v dig &>/dev/null; then
        IP_ADDRESS=$(dig +short @1.1.1.1 "${SUBDOMAIN}.${DOMAIN}")
    elif command -v nslookup &>/dev/null; then
        IP_ADDRESS=$(nslookup "${SUBDOMAIN}.${DOMAIN}" 1.1.1.1 | awk '/^Address: / { print $2 }')
    else
        IP_ADDRESS=$(ping -c1 "${SUBDOMAIN}.${DOMAIN}" | awk -F'[()]' '/PING/ { print $2 }')
    fi

    IP_ADDRESS=$(normalise_ip_address "${IP_ADDRESS}")

    if [ -z "${IP_ADDRESS}" ]; then
        echo "The current IP could not be determined."
        exit 1
    fi

    echo "${IP_ADDRESS}"
}

function get_new_ip_address() {
    local IP_ADDRESS=""
    local MAX_ATTEMPTS=5
    local RETRY_DELAY=2

    for ((ATTEMPT=1; ATTEMPT<=MAX_ATTEMPTS; ATTEMPT++)); do
        IP_ADDRESS=$(curl -sS https://api.ipify.org)
        IP_ADDRESS=$(normalise_ip_address "${IP_ADDRESS}")

        [ -n "${IP_ADDRESS}" ] && break
        sleep "${RETRY_DELAY}"
    done

    if [ -z "${IP_ADDRESS}" ]; then
        echo "The new IP could not be determined after ${MAX_ATTEMPTS} attempts."
        exit 3
    fi

    echo "${IP_ADDRESS}"
}

DOMAIN=$(rev <<< "${FQN_DOMAIN}" | cut -d '.' -f 1,2 | rev)
SUBDOMAIN=$(rev <<< "${FQN_DOMAIN}" | cut -d '.' -f 3- | rev)

CURRENT_IP=$(get_current_ip_address)
NEW_IP=$(get_new_ip_address)

if [[ "${CURRENT_IP}" == "${NEW_IP}" ]]; then
    echo "The IP address is already up to date (${CURRENT_IP})."
    exit 0
fi

echo "Updating the '${FQN_DOMAIN}' LiveDNS Record's IP address from '${CURRENT_IP}' to '${NEW_IP}'..."

RESPONSE=$(curl -s -X PUT \
    -H "Content-Type: application/json" \
    -H "Authorization: Apikey ${API_KEY}" \
    -d '{"rrset_type": "A", "rrset_ttl": 300, "rrset_values": ["'"${NEW_IP}"'"]}' \
    "https://api.gandi.net/v5/livedns/domains/${DOMAIN}/records/${SUBDOMAIN}/A")

RESPONSE_MESSAGE=$(echo "${RESPONSE}" | jq -r ".message")
echo "${RESPONSE_MESSAGE}"
