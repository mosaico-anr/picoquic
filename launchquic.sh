#!/bin/bash

PRES="\e[1;40m$(hostname)\e[0m:\e[32m$0\e[0m"
function print_usage(){
    echo -e "$PRES: Usage: ./$0 <direction> <ECN_MODE> <port> <FLOW_TYPE> <ARGS>"
    echo -e "where:"
    echo -e "\t- <direction> is \"srv\" or \"cli\" "
    echo -e "\t- <ECN_MODE> = [ noecn | classic | l4s ]"
    echo -e "\t- <port> is the port to use"
    echo -e "\t- <FLOW_TYPE> = [ legit | unrespECN | burst | nopacing ]"
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
    F_SIZE="10000000" # 10 Mo
else
    F_SIZE=$5
fi


# pour lancer le telechargement d'un fichier d'1Mo
## ./picoquicdemo -E -C prague -l output.log -n serv1 10.35.1.79 4444 "doc-1234567.html"

function launch_srv(){
    local PICODIR=$1
    local ECN=$2
    local CCA=$3
    local PORT=$4

    git checkout $PICODIR

    if [ $ECN == "noecn" ]; then
	ECN=""
    else
        ECN="-E"
    fi

    ### Server
    # -E            Utilisation d'ECN
    # -C prague     Utilisation de prague pour le CCA
    # -p 4444       Précision du port d'écoute
    # Plus d'infos sur ./picoquicdemo -h
    CMD="./build/picoquicdemo $ECN -C $CCA -p $PORT"
    echo -e "$PRES: Launched command: $CMD \nFrom directory: $PICODIR"

    if [ $VERBOSE == "verbose" ]; then
        eval $CMD
    else
	    eval $CMD &>/dev/null
    fi
}

function launch_cli(){
    local SRV_IP="10.35.1.79"
    local SRV_NAME="quicsrv"
    local PICODIR=$1
    local ECN=$2
    local CCA=$3
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

    if [ $PICODIR != $burstDIR ]; then
        ### Client
        # -n SRV_NAME SRV_IP        Nom et IP du serveur
        # -l output.log             Fichier de log
        CMD="./build/picoquicdemo $ECN -C $CCA -l output-$TS.log -n $SRV_NAME $SRV_IP $PORT doc-$WEIGHT.html"
        echo -e "$PRES: Launching command: $CMD \nFrom directory: $PICODIR"
        if [ $VERBOSE == "verbose" ]; then
            eval $CMD
        else
            eval $CMD &> /dev/null
        fi
    else
        local cpt=0
        CMD="./build/picoquicdemo $ECN -C $CCA -l output.tmp -n $SRV_NAME $SRV_IP $PORT doc-$WEIGHT.html"
        echo -e "$PRES: Launching command: $CMD \nFrom directory: $PICODIR"
        
        until [ $cpt -eq 5 ]
        do
            CURR_TS=$(date +%s%6N)
            if [ $VERBOSE == "verbose" ]; then
                eval $CMD
            else
                eval $CMD &> /dev/null
            fi
            sed -i "1 s/^/Timestamp=$CURR_TS,\n/" output.tmp
            cat output.tmp >> output.log
            rm output.tmp
            ((cpt++))
        done
    fi
}


#
# srv: # Pour unrespECN, simplement toggle la "reduction"
#     flow-type = [ legit | unrespECN ]
#     ECN_mode = [ noecn | classic | l4s ]
#
# cli: # Pour burst, faire une boucle avec 5 lancement de picoquicdemo et collecter l'output dans un fichier central output.log en prenant soin d'ajouter les timestamps à chaque nouveau lancement. Formater le tout directement en format .csv avec le parser
#     flow-type = [ legit | unrespECN | burst ]
#     ECN_mode = [ noecn | classic | l4s ]
# Peut-être besoin de fusionner launquic.sh avec rebuild-demo.sh


oldDIR="/home/$USER/MOSAICO/picoquic/picoquic-quic-prague/"
#unrespECNDIR="/home/$USER/MOSAICO/picoquic/picoquic-quic-prague_atk/"
vanillaDIR="picoquic-RFC9000"
l4sTeamDIR="quic-prague-L4STeam"
legitDIR="xp-legit"
burstDIR="xp-burst"
nopacingDIR="xp-nopacing"
unrespECNDIR="xp-unrespECN"


if [ $SIDE == "srv" ]
then
    case $FLOW_T in
    "legit")
        ARGS="$legitDIR $ECN_MODE $CCA $PORT"
        ;;
    "unrespECN")
        ARGS="$unrespECNDIR $ECN_MODE $CCA $PORT"
        ;;
    "nopacing")
        ARGS="$nopacingDIR $ECN_MODE $CCA $PORT"
        ;;
    "vanilla")
        ARGS="$vanillaDIR $ECN_MODE $CCA $PORT"
        ;;
    "L4STeam")
        ARGS="$l4sTeamDIR $ECN_MODE $CCA $PORT"
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
    case $FLOW_T in
    "legit")
        ARGS="$legitDIR $ECN_MODE $CCA $PORT $F_SIZE"
        ;;
    "burst")
        ARGS="$burstDIR $ECN_MODE $CCA $PORT $F_SIZE"
        ;;
    "vanilla")
        ARGS="$vanillaDIR $ECN_MODE $CCA $PORT"
        ;;
    "L4STeam")
        ARGS="$l4sTeamDIR $ECN_MODE $CCA $PORT $F_SIZE"
        ;;
    *)
        ARGS="$legitDIR $ECN_MODE $CCA $PORT $F_SIZE"
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

