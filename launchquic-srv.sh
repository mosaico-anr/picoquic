#!/bin/bash

PICODIR="./"

PORT="4661"

if [ ! -z "$1" ]
then
	PORT=$1
else
	echo "Warning: Port number not provided in arg 1, picoquicdemo will use $PORT"
fi

# -E for ECN, -C to set CCA implementation, -p to indicate port
# See: ./picoquicdemo -h
./picoquicdemo -E -C prague -p $PORT

echo "Picoquic demo launched with: ./picoquicdemo -E -C prague -p $PORT"

