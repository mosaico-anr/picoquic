#!/bin/bash

oldDIR="/home/$USER/MOSAICO/picoquic/picoquic-quic-prague/"
#unrespECNDIR="/home/$USER/MOSAICO/picoquic/picoquic-quic-prague_atk/"
vanillaDIR="picoquic-RFC9000"
l4sTeamDIR="quic-prague-L4STeam"
legitDIR="xp-legit"
burstDIR="xp-burst"
nopacingDIR="xp-nopacing"
unrespECNDIR="xp-unrespECN"

PRES="\e[1;40m$(hostname)\e[0m:\e[32m$0\e[0m"
function print_usage(){
    echo -e "$PRES: \n\033[0;31mError arguments. Usage: ./$0 <direction> <ECN_MODE> <FLOW_TYPE>"
    echo -e "where:"
    echo -e "\t- <direction> is \"srv\" or \"cli\" "
    echo -e "\t- <ECN_MODE> = [ noecn | classic | l4s ]"
    echo -e "\t- <FLOW_TYPE> = [ legit | unrespECN | bursts | nopacing ]"
    exit 1
}


if [ -z $1 ]
then 
    echo -e "$PRES: Invalid arguments. Rebuilding aborted."
    print_usage
elif [ $1 == "cli" ]
then
    SIDE="cli"
    case $3 in
    "legit")
        PICODIR=$legitDIR
        ;;
    "burst")
        PICODIR=$burstDIR
        ;;
    "vanilla")
        PICODIR=$vanillaDIR
        ;;
    "L4STeam")
        PICODIR=$l4sTeamDIR
        ;;
    *)
        PICODIR=$legitDIR
        ;;
    esac
elif [ $1 == "srv" ]
then
    SIDE="srv"
    case $3 in
    "legit")
        PICODIR=$legitDIR
        ;;
    "unrespECN")
        PICODIR=$unrespECNDIR
        ;;
    "nopacing")
        PICODIR=$nopacingDIR
        ;;
    "vanilla")
        PICODIR=$vanillaDIR
        ;;
    "L4STeam")
        PICODIR=$l4sTeamDIR
        ;;
    *)
        PICODIR=$legitDIR
        ;;
    esac
else 
    echo -e "$PRES: Invalid $1 argument. Rebuilding aborted."
    print_usage
fi

if [ -z $2 ]
then 
    ECN_MODE="l4s"
else
    ECN_MODE=$2
fi
    

function rebuild() {    
    local SIDE=$1
    local ECN=$2
    local PICODIR=$3
    git checkout $PICODIR
    
    if [[ $ECN == "classic" ]]
    then
        sed -i 's/#define PICOQUIC_ECN 1/#define PICOQUIC_ECN 2/' ./picoquic/picosocks.h
    else
        sed -i 's/#define PICOQUIC_ECN 2/#define PICOQUIC_ECN 1/' ./picoquic/picosocks.h
    fi
    
    mkdir -p ./build/
    cmake -B ./build/
    make -C ./build/

    if [ $SIDE == "srv" ]
    then         
        echo -e "\n$PRES: Prague configuration for reduction:\n"
        sed -n '111,155p' ./picoquic/prague.c
    fi 
    
    echo -e "\n$PRES: ECN configuration: \n"
    sed -n '107,113p' ./picoquic/picosocks.h
}

echo -e "$PRES: Rebuild Picoquic on $SIDE side from $PICODIR with ECN MODE=$ECN_MODE"
rebuild $SIDE $ECN_MODE $PICODIR
