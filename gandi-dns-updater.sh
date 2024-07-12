#!/bin/bash
API_KEY="${GANDI_API_KEY}"
[ -z "${API_KEY}" ] && API_KEY=$(cat "/etc/gandi-dns-updater/api-key")

FQN_DOMAIN="${1}"

function validate_variable() {
    local VARIABLE_VALUE="${1}"
    local VARIABLE_FRIENDLY_NAME="${2}"

    if [ -z "${VARIABLE_VALUE}" ]; then
        echo "ERROR: The ${VARIABLE_FRIENDLY_NAME} is missing!"
        exit 1
    fi
}

validate_variable "${API_KEY}" "API Key"
validate_variable "${FQN_DOMAIN}" "domain name"

DOMAIN=$(rev <<< "${FQN_DOMAIN}" | cut -d '.' -f 1,2 | rev)
SUBDOMAIN=$(rev <<< "${FQN_DOMAIN}" | cut -d '.' -f 3- | rev)

function normalise_ip_address() {
    local IP_ADDRESS="${1}"
    local TRIMMED_IP_ADDRESS=""
    
    TRIMMED_IP_ADDRESS="${IP_ADDRESS#"${IP_ADDRESS%%[![:space:]]*}"}"
    TRIMMED_IP_ADDRESS="${TRIMMED_IP_ADDRESS%"${TRIMMED_IP_ADDRESS##*[![:space:]]}"}"

    echo "${TRIMMED_IP_ADDRESS}"
}

function get_current_ip_address() {
    local IP_ADDRESS=""

    if [ -f "/usr/bin/dig" ]; then
        IP_ADDRESS=$(dig +short @1.1.1.1 "${SUBDOMAIN}.${DOMAIN}")
    elif [ -f "/usr/bin/nslookup" ]; then
        IP_ADDRESS=$(nslookup "${SUBDOMAIN}.${DOMAIN}" 1.1.1.1 | grep 'Address:' | awk '{print $2}')
    else
        IP_ADDRESS=$(ping -c1 "${SUBDOMAIN}.${DOMAIN}" | awk -F'[()]' '/PING/{print $2}')
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

    IP_ADDRESS=$(curl -sS https://api.ipify.org)

    IP_ADDRESS=$(normalise_ip_address "${IP_ADDRESS}")

    if [ -z "${IP_ADDRESS}" ]; then
        echo "The new IP could not be determined."
        exit 1
    fi

    echo "${IP_ADDRESS}"
}

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
