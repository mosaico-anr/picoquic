#!/bin/bash

PRES="\e[1;40m$(hostname)\e[0m:\e[32m$0\e[0m"
function print_usage(){
    echo -e "$PRES: Usage: ./$0 <direction> <ECN_MODE> <port> <FLOW_TYPE> <ARGS>"
    echo -e "where:"
    echo -e "\t- <direction> is \"srv\" or \"cli\" "
    echo -e "\t- <ECN_MODE> = [ noecn | classic | l4s ]"
    echo -e "\t- <port> is the port to use"
    echo -e "\t- <FLOW_TYPE> = [ legit | unrespECN ]"
    echo -e "\t- <ARGS> depends on <direction>:"
    echo -e "\t\t- if <direction>=\"srv\": <ARGS> is \"verbose\" or \"mute\" mode. Default to \"mute\"."
    echo -e "\t\t- if <direction>=\"cli\": <ARGS> depends on <FLOW_TYPE>, it's the weight of data to request. Must be higher for unrespECN than for burst. The verbose argument can also be provided after <ARGS>"
    exit 1
}

CURR_DIR=$(pwd)

if [[ $# -gt 6 || $# -lt 4 ]]
then
    echo -e "\n\033[0;31mError arguments.\e[0m"
    print_usage
fi

if [ -z $1 ]; then
    echo -e "\n\033[0;31mError arguments.\e[0m"
    print_usage
else
    SIDE=$1
fi

if [ -z $2 ]; then
    ECN_MODE="l4s"
else
    ECN_MODE=$2
fi

case $ECN_MODE in
    "noecn")
        CCA="cubic"
        ;;
    "classic")
        CCA="cubic"
        ;;
    "l4s")
        CCA="prague"
        ;;
    *)
        CCA="prague"
        ;;
esac

if [ -z $3 ]; then
    PORT="4444"
else
    PORT=$3
fi

if [ -z $4 ]; then
    FLOW_T="legit"
else
    FLOW_T=$4
fi

if [ -z $5 ]; then
    F_SIZE="300" # Mo
else
    F_SIZE=$5
fi


# Pour lancer le telechargement d'un fichier de 300 Mo
## Côté server: ./picoquic_sample server 4433 ./ca-cert.pem ./server-key.pem ./server_files
## Côté client: ./picoquic_sample client 10.0.1.12 4433 /tmp index-300MB.htm

function launch_srv(){
    local PICODIR=$1
    local ECN=$2
    local CCA=$3
    local PORT=$4

    # A remplacer par un rebuild
    git checkout $PICODIR

    if [ $ECN == "noecn" ]; then
	ECN=""
    else
        ECN="-E"
    fi

    ### Server
    # Assuming files to serve are in ./build/server_files
    # Make sure to first create certificates for example with:
    #   openssl req -x509 -newkey rsa:2048 -days 365 -keyout ca-key.pem -out ca-cert.pem
    #   openssl req -newkey rsa:2048 -keyout server-key.pem -out server-req.pem

    CMD="./build/picoquic_sample server $PORT ./ca-cert.pem ./server-key.pem ./server_files"
    echo -e "$PRES: Launched command: $CMD \nFrom directory: $PICODIR"

    if [ $VERBOSE == "verbose" ]; then
        eval $CMD
    else
	    eval $CMD &>/dev/null
    fi
}

function launch_cli(){
    # ATTENTION
    local PICODIR=$1
    local ECN=$2
    local SRV_IP=$3
    local PORT=$4
    local WEIGHT=$5
    local TS=$(date +%Y-%m-%d-%H%M)
    
    git checkout $PICODIR
    rm output.log

    if [ $ECN == "noecn" ]; then
	ECN=""
    else
        ECN="-E"
    fi

    ### Client
    CMD="./build/picoquic_sample client $SRV_IP $PORT /tmp index-${WEIGHT}MB.htm"
    echo -e "$PRES: Launching command: $CMD \nFrom directory: $PICODIR"
    if [ $VERBOSE == "verbose" ]; then
        eval $CMD
    else
        eval $CMD &> /dev/null
    fi

}

# Besoin de fusionner launquic.sh avec rebuild-demo.sh

legitDIR="picoquic-RFC9000"
unrespECNDIR="new-unrespECN"


if [ $SIDE == "srv" ]
then
    case $FLOW_T in
    "legit")
        ARGS="$legitDIR $ECN_MODE $CCA $PORT"
        ;;
    "unrespECN")
        ARGS="$unrespECNDIR $ECN_MODE $CCA $PORT"
        ;;
    *)
        ARGS="$legitDIR $ECN_MODE $CCA $PORT"
        ;;
    esac

    if [ -z $5 ]; then
        VERBOSE="mute"
    else
        VERBOSE=$5
    fi

    launch_srv $ARGS $VERBOSE
elif [ $SIDE == "cli" ]
then
    SRV_IP=$2
    case $FLOW_T in
    "legit")
        ARGS="$legitDIR $ECN_MODE $SRV_IP $PORT $F_SIZE"
        ;;
    *)
        ARGS="$legitDIR $ECN_MODE $SRV_IP $PORT $F_SIZE"
        ;;
    esac

    if [ -z $6 ]; then
        VERBOSE="mute"
    else
        VERBOSE=$6
    fi

    launch_cli $ARGS $VERBOSE
else
    echo -e "$PRES: \033[0;31mInvalid argument $SIDE: unknown direction.\e[0m"
    print_usage
fi

