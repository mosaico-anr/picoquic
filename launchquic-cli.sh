#!/bin/bash

PICODIR="./"

SRV_IP="127.0.0.1"
SRV_NAME="picoserv"
PORT="4661"

if [ ! -z "$1" ]
then
	PORT=$1
else
	echo "Warning: Port number not provided in arg 1, picoquicdemo will use $PORT"
fi

if [ ! -z "$2" ]
then
	SRV_IP=$2
else
	echo "Warning: Server IP not provided in arg 2, picoquicdemo will use $SRV_IP"
fi

# -E for ECN, -C to set CCA implementation, -p to indicate port
# See: ./picoquicdemo -h
./picoquicdemo -E -C prague -l output.log -n $SRV_NAME $SRV_IP $PORT

echo "Picoquic client demo launched with: ./picoquicdemo -E -C prague -l output.log -n $SRV_NAME $SRV_IP $PORT"

