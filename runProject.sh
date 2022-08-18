#!/bin/bash
 
# ProjFolder must contains Client${i}.conf and Server.conf files and
# the client/server binaries. Binary names are passed as arguments to this script.
# The script will create 'i' subfolders for each Client with 'Contents' subfolder.
# Same for the server.
# 
#
# PARAMETERS: 1 - number of virtual clients
# FIXED PARAMETER: 'numberOfContents'

#------------- Colors ------------------#
export RED="\e[0;31m"
export GREEN="\e[0;32m"
export YELLOW="\e[1;33m"
export BLUE="\e[0;34m"
export CYAN="\e[0;36m"
export Z="\e[0m"
#---------------------------------------#

IFS=$'\n'

[ $# -ne 4 ] && echo -e "${RED}Number of Clients as arg $Z" && exit

bridgeP2P="virbr1" # for P2P
bridgeCS="virbr0" # for client-server
numberOfContents=5

numberOfClients=$1
serverIP=10.1.2.$(($numberOfClients+1))
projFolder=$2
clientBIN=$3
serverBIN=$4
serverPort=5000
clientPort=5000

resetPacketCounters(){
    echo -e "${CYAN}Resetting IPTABLES packet counters$Z"
    for i in `seq 1 $numberOfClients`; do
	#sudo ip netns exec nsClient${i} iptables -I INPUT -i eth0
	#sudo ip netns exec nsClient${i} iptables -I INPUT -i eth1
	#sudo ip netns exec nsClient${i} iptables -I OUTPUT -o eth0
	#sudo ip netns exec nsClient${i} iptables -I OUTPUT -o eth1
	sudo ip netns exec nsClient${i} iptables -Z
	sudo ip netns exec nsServer iptables -Z
    done 
}

getResultsNetwork(){
    for client in `seq 1 $numberOfClients`; do
	sudo ip netns exec nsClient${client} iptables -L -vxn
    done 
    sudo ip netns exec nsServer iptables -L -vxn
}

getResultsDownload(){
    completed=0
    byteDownloaded=0
    for client in `seq 1 $numberOfClients`; do
	contentStore="$projFolder/Client${client}/Contents/"
	if [  "$(ls -A $contentStore)" ] ; then
	    for contentLine in `ls -l $contentStore | grep -v total`; do
		contentName=`echo $contentLine | awk '{print $9}'`
		contentSizeClient=`echo $contentLine | awk '{print $5}'`
		byteDownloaded=$(($byteDownloaded + $contentSizeClient))
		contentSizeServer=`ls -l $projFolder/Server/Contents | grep ${contentName}$ | awk '{print $5}'`
		[ $contentSizeClient -eq $contentSizeServer ] && completed=$(($completed+1))
	    done
	fi
    done
    echo -e "${GREEN}Download completed=$completed, byte downloaded=$byteDownloaded $Z"
    # to SHOW counters at the end: sudo ip netns exec nsClient${i} iptables -L -vxn 
}

createFolders(){
    echo -e "${CYAN}CREATING Folders$Z"
    for client in `seq 1 $numberOfClients`; do
	[ -e $projFolder/Client${client} ] && rm -r $projFolder/Client${client}
	mkdir $projFolder/Client${client}
	cp $projFolder/$clientBIN $projFolder/Client${client}/
	mkdir $projFolder/Client${client}/Contents
    done
    [ -e $projFolder/Server ] && rm -r $projFolder/Server
    mkdir $projFolder/Server
    cp $projFolder/$serverBIN $projFolder/Server/
    mkdir $projFolder/Server/Contents
}

createContents(){
    echo -e "${CYAN}CREATING Contents:$Z"
    for i in `seq -f %02g 1 $numberOfContents`; do
	dd if=/dev/zero of=${projFolder}/Server/Contents/content${i}  bs=1M  count=${i}
    done
}
 
startClientsServer(){
    echo -e "${CYAN}Starting server and clinets$Z"
    sudo ip netns exec nsServer $projFolder/Server/${serverBIN} $projFolder/Server.conf $serverPort &
    for i in `seq 1 $numberOfClients`; do
	sudo ip netns exec nsClient${i} $projFolder/Client${client}/$clientBIN $projFolder/Client${i}.conf $serverIP $clientPort &
    done 
}

stopExchange(){
    sudo killall -9 $serverBIN
    sudo killall -9 $clientBIN
}

resetPacketCounters
createFolders
createContents
startClientsServer
# WAIT FOR SOME SECONDS
sleep 10
# STOP/KILL BIN
stopExchange
# GET RESULTS
getResultsDownload
getResultsNetwork

# Example to change interface loss, rate, delay, etc
# the first time use 'add'
# sudo ip netns exec nsClient1 tc qdisc add dev tap11 root netem loss 0%
# then, change with 'change'
# sudo ip netns exec nsClient1 tc qdisc change dev tap11 root netem loss 0%
