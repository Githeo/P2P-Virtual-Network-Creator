#!/bin/bash
 
# This script creates a virtual network with Linux namespace facilities.
# A number of Client namespaces are created as long as a Server namespace.
# Clients have 2 interfaces:
#   - eth1: to comunicate in a P2P fashion among them. The other side of 
#           the virtual link is called brp2p-cX (where X is the client number)
#           and it is connected to a virtual bridge for the P2P communication
#           called 'virbr1'. eth1 has the IP addr. 10.1.1.X/24
#   - eth0: to communicate to the Server. Its IP addr. is 10.1.2.X/24
#           The other side of the virtual link is called 'brcs-cX' and
#           is connected to a new virtual bridge called 'virbr0' 
#           for the Client-Server communication
#
# The Server has only one interface eth0, IP addr. 10.1.2.(n+1)/24
# where n is the total number of clients. This interface is connected
# to the interface 'brcs-server' of the virbr0 bridge
#
# PARAMETERS: 1 - number of virtual clients

#------------- Colors ------------------#
export RED="\e[0;31m"
export GREEN="\e[0;32m"
export YELLOW="\e[1;33m"
export BLUE="\e[0;34m"
export CYAN="\e[0;36m"
export Z="\e[0m"
#---------------------------------------#

IFS=$'\n'

[ $# -ne 1 ] && echo -e "${RED}Number of Clients as arg $Z" && exit

numberOfClients=$1
bridgeP2P="virbr1" # for P2P
bridgeCS="virbr0" # for client-server

showConfig(){
    ip netns list
    brctl show $bridgeP2P
    brctl show $bridgeCS
}

addPacketCounters(){
    # Assign packet counters virtual interfaces in namespace
    for i in `seq 1 $numberOfClients`; do
	sudo ip netns exec nsClient${i} iptables -I INPUT -i eth0
	sudo ip netns exec nsClient${i} iptables -I INPUT -i eth1
	sudo ip netns exec nsClient${i} iptables -I OUTPUT -o eth0
	sudo ip netns exec nsClient${i} iptables -I OUTPUT -o eth1
    done 
    sudo ip netns exec nsServer iptables -I INPUT -i eth0
    sudo ip netns exec nsServer iptables -I OUTPUT -o eth0
    # to SHOW counters at the end: sudo ip netns exec nsClient${i} iptables -L -vxn 
    # to RESET counters at the end: sudo ip netns exec nsClient${i} iptables -Z 
}

createBridges() {
    echo -e "${CYAN}Creating bridges... $Z"
    sudo brctl addbr ${bridgeCS} # for server connection
    sudo brctl addbr ${bridgeP2P} # for P2P
    sudo brctl stp ${bridgeCS} off # disable spanning tree
    sudo brctl stp ${bridgeP2P} off
    sudo ip link set dev ${bridgeCS} up # Bring up the bridge interface
    sudo ip link set dev ${bridgeP2P} up
}

# CREATING BRIDGES
createBridges # bridges are already created

echo -e "${CYAN}CREATING NS...$Z"
for client in `seq 1 $numberOfClients`; do
    sudo ip netns add nsClient${client} # adding ns for clients
    # 'sudo ip netns list' to list all namespaces
done
sudo ip netns add nsServer  # adding ns for server

# CREATING eth1-bridgeP2P links
for client in `seq 1 $numberOfClients`; do
    clientTAPTemp="footap${client}"
    clientTAP="eth1"
    bridgeTAP="brp2p-c${client}"
    iaddress="10.1.1.${client}"

    sudo ip link add ${clientTAPTemp} type veth peer name ${bridgeTAP}
    
    # Move "eth1" interface from global namespace to the "nsClientx" namespace
    sudo ip link set ${clientTAPTemp} netns nsClient${client}
    
    # Rename now the clientTap interface to eth1
    sudo ip netns exec nsClient${client} ip link set ${clientTAPTemp} name ${clientTAP}

    # Move "br-tap1" interface from global namespace to the Linux Bridge "br-test".
    sudo brctl addif ${bridgeP2P} $bridgeTAP
    
    # Set interfaces "clientTAP" and "bridgeTAP" to UP
    sudo ip netns exec nsClient${client} ip link set dev ${clientTAP} up
    sudo ip link set dev ${bridgeTAP} up
    
    # Assign IP address to the interface "tap1" in the namespace "ns1".
    sudo ip netns exec nsClient${client} ip addr add ${iaddress}/24 dev $clientTAP
 
done

echo -e "${CYAN}CREATING eth0-bridgeClientServer links$Z"
for client in `seq 1 $numberOfClients`; do
    clientTAPTemp="foocs${client}"
    clientTAP="eth0"
    bridgeTAP="brcs-c${client}"
    iaddress="10.1.2.${client}"

    sudo ip link add ${clientTAPTemp} type veth peer name ${bridgeTAP}
    
    # Move "eth1" interface from global namespace to the "nsClientx" namespace
    sudo ip link set ${clientTAPTemp} netns nsClient${client}

    # Rename now the clientTap interface to eth0
    sudo ip netns exec nsClient${client} ip link set ${clientTAPTemp} name ${clientTAP}
    
    # Move "br-tap1" interface from global namespace to the Linux Bridge "br-test".
    sudo brctl addif ${bridgeCS} $bridgeTAP
    
    # Set interfaces "tap1" and "br-tap1" to UP
    sudo ip netns exec nsClient${client} ip link set dev ${clientTAP} up
    sudo ip link set dev ${bridgeTAP} up
    
    # Assign IP address to the interface "tap1" in the namespace "ns1".
    sudo ip netns exec nsClient${client} ip addr add ${iaddress}/24 dev $clientTAP

done

echo -e "${CYAN}CREATING link Server-bridgeClientServer${Z}"
sudo ip link add serverTap type veth peer name brcs-server
sudo ip link set serverTap netns nsServer
sudo ip netns exec nsServer ip link set serverTap name eth0
sudo brctl addif ${bridgeCS} brcs-server
sudo ip netns exec nsServer ip link set dev eth0 up
sudo ip link set dev brcs-server up
sudo ip netns exec nsServer ip addr add 10.1.2.$(($numberOfClients+1))/24 dev eth0
# set the max rate from the server
sudo ip netns exec nsServer tc qdisc add dev eth0 root tbf rate 5mbit burst 64kb latency 1ms

showConfig

addPacketCounters

# Example to change interface loss, rate, delay, etc
# the first time use 'add'
# sudo ip netns exec nsClient1 tc qdisc add dev tap11 root netem loss 0%
# then, change with 'change'
# sudo ip netns exec nsClient1 tc qdisc change dev tap11 root netem loss 0%
