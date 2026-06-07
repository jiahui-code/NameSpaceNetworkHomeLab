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
        if ip link show "$link"; then
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
    for ns in "$@"; do
        if ! ip netns list | grep -q "^$ns$"; then
            ip netns add "$ns" #save created ns name to global
            ipns "$ns" ip link set lo up
            NS_LIST+=("$ns")
        fi
    done
    log "created successful: $*, netns lo set up"
}

add_veth(){
    for lk in "$@"; do
        if ! ip link show "$lk" > /dev/null 2>&1; then 
            run_cmd ip link add "$lk" type veth peer name "$lk"_p
            LINK_LIST+=("$lk")
        fi
    done
    log "created successful: $lk"
    echo "${LINK_LIST[@]}"
}

add_br_ip(){
    local br_name="$2"
    ip address add "$1" dev "$2"
    BR_LIST+=("$br_name")
    log "created bridge $br_name"
}

br_link_set(){
    # br_link_set <namespace> <bridge_id> <link_id...>
    local ns="$1"
    local bridge="$2"
    shift 2
    for link in "$@"; do
        ipns "$ns" ip link set "$link" master "$bridge"
    done
}

observe_pause() {
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
    # observe_pause created single namespace
    run_cmd ip netns exec ns1 ip link set lo up
    add_veth veth-12 veth-12p
   
    run_cmd ip addr add 172.18.0.11/24 dev veth-12
    run_cmd ip link set veth-12 up
    run_cmd ip addr add 172.18.0.12/24 dev veth-12p
    run_cmd ip link set veth-12p up
    # observe_pause veth linked created, both peer in host

    create_ns ns2
    run_cmd ip netns exec ns2 ip link set lo up
    run_cmd ip link set veth-12 netns ns1
    run_cmd ip link set veth-12p netns ns2
    run_cmd ipns ns1 ip addr add 172.18.0.11/24 dev veth-12
    run_cmd ipns ns2 ip addr add 172.18.0.12/24 dev veth-12p
    run_cmd ipns ns1 ip link set veth-12 up
    run_cmd ipns ns2 ip link set veth-12p up
    # observe_pause created ns2, ns1 \& ns2 connected using veth-12

    add_veth veth-s1 veth-s1p
    run_cmd ip addr add 172.18.1.11/24 dev veth-s1
    run_cmd ip link set veth-s1p netns ns1
    run_cmd ipns ns1 ip addr add 172.18.1.12/24 dev veth-s1p
    run_cmd ip link set veth-s1 up
    run_cmd ipns ns1 ip link set veth-s1p up
    #  observe_pause host <-veth-> ns1 <-veth-> ns2

    # set ns2 route table out via ns1
    run_cmd ip netns exec ns2 ip route add default via 172.18.0.11
    # set host route table to 172.18.0.0/24 via ns1
    run_cmd ip route add 172.18.0.0/24 via 172.18.1.12
    #  observe_pause check route
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
    #  observe_pause confirm host ip link has bridge up

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
    # observe_pause n1, n2 linked to bridge b0\; n1 \& n2 connected, but cannot ping bridge IP.

    run_cmd ipns ns2 ip route add 172.18.0.0/24 dev v-b2p
    # check kenel IP forward switch and turn it on
    run_cmd sysctl net.ipv4.ip_forward | grep -q "= 1" || sudo sysctl -w net.ipv4.ip_forward=1
    # observe_pause ns2 can ping bridge IP, but cannot ping host 192.xxx IP
    run_cmd ipns ns2 ip route add default via 172.18.0.1 dev v-b2p
    # observe_pause ns2 can ping host 192.xxx IP, but ping 8.8.8.8 fail, because SNAT unactive

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
    observe_pause connect ns3 and bridge in ns1,ns2 different subnet
    # n1, n2, n3, host are connected, inter ping successful. 
    # hostname -I | awk '{print $1}' | xargs ip netns exec ns-name ping
}

# lab 3 connected to outter IP
main3() {
    # n1, n2, n3, host are connected, inter ping successful. 
    echo "SNAT lab: connect to outter IP"
    run_cmd iptables -t nat -A POSTROUTING -s 172.18.0.0/24 -o eth0 -j MASQUERADE
    observe_pause n1, n2, n3, bridge can all ping outer IP now
    clean_up
}

# lab 4 isolate router namespace, add in firewall filter
main4(){
    create_ns fw rt ns1 ns2 ns3
    # create firewall, router ns. seperate bridges from host to router ns
    add_veth v-hf v-fr v-b1 v-b2 v-b3
    # observe_pause create namespaces and veths
    
    # create bridge in ns
    # create veth in host, set veth ports into ns
    # activate bridge 
    # link veth ports to bridge, master
    # activate veth port  
    # set bridge IP, set port IP
    run_cmd ip link set v-hf_p netns fw 
    run_cmd ip link set v-fr netns fw
    run_cmd ip link set v-fr_p netns rt
    run_cmd ip link set v-b1_p netns ns1
    run_cmd ip link set v-b2_p netns ns2
    run_cmd ip link set v-b3_p netns ns3

    run_cmd ipns rt ip link add br-r type bridge
    
    run_cmd ip link set v-b1 netns rt
    run_cmd ip link set v-b2 netns rt
    run_cmd ip link set v-b3 netns rt
    
    ipns rt ip link set v-b1 master br-r
    ipns rt ip link set v-b2 master br-r
    ipns rt ip link set v-b3 master br-r

    run_cmd ipns rt ip link set br-r up

    observe_pause 
    
    run_cmd ip a add 172.18.0.17/28 dev v-b2_p
    run_cmd ip link set v- netns ns 
    run_cmd ip link set v-fw_p netns fwns
    run_cmd ip link set v-fw-r netns fwns
    run_cmd ip link set v-fw-r_p netns rt_ns
    ip link set 
    observe_pause
}


# main1 "$@"
# main2 "$@"
# main3 "$@"
main4 "$@"

