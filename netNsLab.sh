#!/bin/bash

# Program:
#   net namespace lab script
# History:
# 2026/05/26	kary	First release

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

HOST_IP=$(hostname -I | awk '{print $1}')
SELF_127_IP="127.0.0.1"
NS_LIST=()
LINK_LIST=()
DEBUG=true

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%dT%H:%M:%S')]${NC} $1"
}

run_cmd() {
    log "run: $*"
    if ! "$@" > /dev/null 2>&1; then
        echo -e "${RED}[ERROR] failed: $*${NC}"
        exit 1
    fi
}

clean_up_ns() {
    log "chean up ns."
    for ns in "${NS_LIST[@]}"; do
        if ip netns list | grep -q "$ns"; then
            log "delete NS: $ns"
            sudo ip netns delete "$ns"
        fi
    log "cleared."
    done
}

clean_up_link() {
    log "chean up link."
    for link in "${LINK_LIST[@]}"; do
        if ip link show | grep -q "$link"; then
            log "delete link: $link"
            ip link set "$link" down || true
            ip link delete "link" 2>/dev/null || true
        fi
    log "cleared."
    done
}

clean_up(){
    clean_up_link
    clean_up_ns
}

create_ns(){
    local ns_name=$1
    sudo ip netns add "$ns_name"
    NS_LIST+=("$ns_name") # 将名字存入数组
    log "created successful: $ns_name"
}

debug_pause() {
    if [[ "$DEBUG" == "true" ]]; then
        echo "$*"
        echo -e "\033[1;33m[DEBUG]${NC} Debug pause, enter to continue."
        echo -ne "ip a | ping | ip rout | ip link show | bridge fdb show"
        read -r
    fi
}

trap clean_up EXIT

#varify namespace speration then link to host VM
main1() {
    echo "check current namspace folder"
    ip netns list
    create_ns ns1
    debug_pause created single namespace
    run_cmd ip netns exec ns1 ip link set lo up
    local link1="veth-client" | run_cmd ip link add "$link1" type veth peer name veth-server | LINK_LIST+=("$link1")
   
    run_cmd ip addr add 172.18.0.11/16 dev veth-client
    run_cmd ip link set veth-client up
    run_cmd ip addr add 172.18.0.12/16 dev veth-server
    run_cmd ip link set veth-server up
    debug_pause veth linked created, both peer in host
}

main1 "$@"

