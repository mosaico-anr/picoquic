#!/bin/bash

legitDIR="picoquic-RFC9000"
unrespECNDIR="new-unrespECN"

PRES="\e[1;40m$(hostname)\e[0m:\e[32m$0\e[0m"
function print_usage(){
    echo -e "$PRES: Usage: ./$0 <direction> <ECN_MODE> <FLOW_TYPE>"
    echo -e "where:"
    echo -e "\t- <direction> is \"srv\" or \"cli\" "
    echo -e "\t- <ECN_MODE> = [ noecn | classic | l4s ]"
    echo -e "\t- <FLOW_TYPE> = [ legit | unrespECN | burst | nopacing ]"
    exit 1
}


if [ -z $1 ]
then 
    echo -e "$PRES: \033[0;31mInvalid arguments. Rebuilding aborted.\e[0m"
    print_usage
elif [ $1 == "cli" ]
then
    SIDE="cli"
    case $3 in
    "legit")
        PICODIR=$legitDIR
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
    *)
        PICODIR=$legitDIR
        ;;
    esac
else 
    echo -e "$PRES: \033[0;31mInvalid argument: $1. Rebuilding aborted.\e[0m"
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
        sed -i 's/#define PICOQUIC_L4S_CONF PICOQUIC_ECN_ECT_1/#define PICOQUIC_L4S_CONF PICOQUIC_ECN_ECT_0/' ./picoquic/picosocks.h
    else
        sed -i 's/#define PICOQUIC_L4S_CONF PICOQUIC_ECN_ECT_0/#define PICOQUIC_L4S_CONF PICOQUIC_ECN_ECT_1/' ./picoquic/picosocks.h
    fi
    
    mkdir -p ./build/
    cd ./build/
    cmake ..
    make
    cd ..
    
    if [ $SIDE == "srv" ]
    then         
        echo -e "\n$PRES: Prague configuration for reduction:\n"
        sed -n '268,287p' ./picoquic/prague.c
    fi 
    
    echo -e "\n$PRES: ECN configuration: \n"
    sed -n '112,115p' ./picoquic/picosocks.h
}

echo -e "$PRES: Rebuild Picoquic on $SIDE side from $PICODIR with ECN MODE=$ECN_MODE"
rebuild $SIDE $ECN_MODE $PICODIR
