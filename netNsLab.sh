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
BR_LIST=()

DEBUG=true

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%dT%H:%M:%S')]${NC} $1"
}

run_cmd() {
    log "run: $*"
    local output
    if ! output=$("$@" 2>&1); then
        echo -e "\n${RED}[ERROR] $*${NC}"
        echo -e "${RED}[DEBUG] $output${NC}\n"
        exit 1
    fi
}

clean_up_ns() {
    # log "chean up ns."
    for ns in "${NS_LIST[@]}"; do
        if ip netns list | grep -q "$ns"; then
            log "delete NS: $ns"
            sudo ip netns delete "$ns"
        fi
    done
    log "cleared namespaces."
}

clean_up_link() {
    # log "chean up link."
    for link in "${LINK_LIST[@]}"; do
        if ip link show | grep -q "$link"; then
            log "delete link: $link"
            ip link set "$link" down || true
            ip link delete "$link" 2>/dev/null || true
        fi
    done
    log "cleared veth links"
}

clean_up_br(){
    for br in "${BR_LIST[@]}"; do
        if ip a | grep -q "$br"; then
            ip link del "$br" 2>/dev/null || true
        fi
    done
    log "cleared created bridge."
}

clean_up_snat(){
    if  iptables -t nat -C POSTROUTING -s 172.18.0.0/24 -o eth0 -j MASQUERADE 2>/dev/null; then
        # echo "SNAT rule exists, ready to clean up."
        iptables -t nat -D POSTROUTING -s 172.18.0.0/24 -o eth0 -j MASQUERADE
    fi
    log "cleared created SNAT"
}

ipns() { ip netns exec "$@"; }

clean_up(){
    clean_up_link
    clean_up_ns
    clean_up_br
    clean_up_snat
    # clear global variable when sublab finished
    NS_LIST=(); LINK_LIST=(); BR_LIST=();
}

create_ns(){
    local ns_name=$1
    ip netns add "$ns_name"
    NS_LIST+=("$ns_name") # 将名字存入数组
    log "created successful: $ns_name"
}

add_veth(){
    local link_name=$1
    ip link add "$link_name" type veth peer name "$2" 
    LINK_LIST+=("$link_name")
    log "created successful: $link_name"
}

add_br_ip(){
    local br_name="$2"
    ip address add "$1" dev "$2"
    BR_LIST+=("$br_name")
    log "created bridge $br_name"
}

debug_pause() {
    if [[ "$DEBUG" == "true" ]]; then
        echo "$*"
        echo -e "\033[1;33m[DEBUG]${NC} Enter to continue."
        echo -ne "ip a | ping | ip rout | ip link show | bridge fdb show"
        read -r
    fi
}

trap clean_up EXIT

#varify namespace speration then link to host VM
main1() {
    # echo "check current namspace folder"
    create_ns ns1
    # debug_pause created single namespace
    run_cmd ip netns exec ns1 ip link set lo up
    add_veth veth-12 veth-12p
   
    run_cmd ip addr add 172.18.0.11/24 dev veth-12
    run_cmd ip link set veth-12 up
    run_cmd ip addr add 172.18.0.12/24 dev veth-12p
    run_cmd ip link set veth-12p up
    # debug_pause veth linked created, both peer in host

    create_ns ns2
    run_cmd ip netns exec ns2 ip link set lo up
    run_cmd ip link set veth-12 netns ns1
    run_cmd ip link set veth-12p netns ns2
    run_cmd ipns ns1 ip addr add 172.18.0.11/24 dev veth-12
    run_cmd ipns ns2 ip addr add 172.18.0.12/24 dev veth-12p
    run_cmd ipns ns1 ip link set veth-12 up
    run_cmd ipns ns2 ip link set veth-12p up
    #debug_pause created ns2, ns1 \& ns2 connected using veth-12

    add_veth veth-s1 veth-s1p
    run_cmd ip addr add 172.18.1.11/24 dev veth-s1
    run_cmd ip link set veth-s1p netns ns1
    run_cmd ipns ns1 ip addr add 172.18.1.12/24 dev veth-s1p
    run_cmd ip link set veth-s1 up
    run_cmd ipns ns1 ip link set veth-s1p up
    # debug_pause host <-veth-> ns1 <-veth-> ns2

    # set ns2 route table out via ns1
    run_cmd ip netns exec ns2 ip route add default via 172.18.0.11
    # set host route table to 172.18.0.0/24 via ns1
    run_cmd ip route add 172.18.0.0/24 via 172.18.1.12
    # debug_pause check route
    clean_up
}

main2(){
    echo ""
    log "started 2nd lab focus on bridge"
    create_ns ns1
    create_ns ns2
    create_ns ns3
    # created bridge br0
    run_cmd ip link add br0 type bridge
    add_br_ip 172.18.0.1/24 br0
    run_cmd ip link set br0 up
    # debug_pause confirm host ip link has bridge up

    add_veth v-b1 v-b1p
    run_cmd ip link set v-b1p netns ns1
    run_cmd ipns ns1 ip a add 172.18.0.17/28 dev v-b1p
    run_cmd ip link set v-b1 master br0
    run_cmd ipns ns1 ip link set lo up
    run_cmd ipns ns1 ip link set v-b1p up

    add_veth v-b2 v-b2p
    run_cmd ip link set v-b2p netns ns2
    run_cmd ipns ns2 ip a add 172.18.0.18/28 dev v-b2p
    run_cmd ip link set v-b2 master br0
    run_cmd ipns ns2 ip link set lo up
    run_cmd ipns ns2 ip link set v-b2p up

    run_cmd ip link set v-b1 up
    run_cmd ip link set v-b2 up
    # debug_pause n1, n2 linked to bridge b0\; n1 \& n2 connected, but cannot ping bridge IP.

    run_cmd ipns ns2 ip route add 172.18.0.0/24 dev v-b2p
    # check kenel IP forward switch and turn it on
    run_cmd sysctl net.ipv4.ip_forward | grep -q "= 1" || sudo sysctl -w net.ipv4.ip_forward=1
    # debug_pause ns2 can ping bridge IP, but cannot ping host 192.xxx IP
    run_cmd ipns ns2 ip route add default via 172.18.0.1 dev v-b2p
    # debug_pause ns2 can ping host 192.xxx IP, but ping 8.8.8.8 fail, because SNAT unactive

    # do the same for ns1
    run_cmd ipns ns1 ip route add 172.18.0.0/24 dev v-b1p
    run_cmd ipns ns1 ip route add default via 172.18.0.1 dev v-b1p


    add_veth v-b3 v-b3p
    run_cmd ip link set v-b3p netns ns3
    run_cmd ipns ns3 ip a add 172.18.0.55/28 dev v-b3p
    run_cmd ip link set v-b3 master br0
    run_cmd ipns ns3 ip link set lo up
    run_cmd ipns ns3 ip link set v-b3p up
    run_cmd ip link set v-b3 up
    run_cmd ipns ns3 ip route add 172.18.0.0/24 dev v-b3p
    run_cmd ipns ns3 ip route add default via 172.18.0.1 dev v-b3p
    debug_pause connect ns3 and bridge in ns1,ns2 different subnet
    # n1, n2, n3, host are connected, inter ping successful. 
    # hostname -I | awk '{print $1}' | xargs ip netns exec ns-name ping
}


# lab 3 connected to outter IP
main3() {
    # n1, n2, n3, host are connected, inter ping successful. 
    echo "SNAT lab: connect to outter IP"
    run_cmd iptables -t nat -A POSTROUTING -s 172.18.0.0/24 -o eth0 -j MASQUERADE
    debug_pause n1, n2, n3, bridge can all ping outer IP now

}


main1 "$@"
main2 "$@"
main3 "$@"

