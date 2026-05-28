#!/bin/bash

# Program:
#   net namespace lab script
# History:
# 2026/05/26	kary	First release

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

HOST_IP=$(hostname -I | awk '{print $1}')
SELF_127_IP="127.0.0.1"
NS_LIST=()

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

clean_up() {
    log "chear up namespaces."
    for ns in "${NS_LIST[@]}"; do
        if ip netns list | grep -q "$ns"; then
            log "delete NS: $ns"
            sudo ip netns delete "$ns"
        fi
    log "cleared created namespaces."
    done
}

create_ns(){
    local ns_name=$1
    sudo ip netns add "$ns_name"
    NS_LIST+=("$ns_name") # 将名字存入数组
    log "created successful: $ns_name"
}

main() {
    echo "check current namspace folder"
    ip netns list
    create_ns ns1
    clean_up
}

main

