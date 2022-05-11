#!/bin/bash

# TODO changer par des git checkout
oldDIR="/home/$USER/MOSAICO/picoquic/picoquic-quic-prague/"
vanillaDIR="/home/$USER/MOSAICO/picoquic/picoquic-vanilla-private-octopus/"
l4sTeamDIR="/home/$USER/MOSAICO/picoquic/picoquic-prague-L4STeam/"
legitDIR="/home/$USER/MOSAICO/picoquic/picoquic-prague-legit/"
burstDIR="/home/$USER/MOSAICO/picoquic/picoquic-prague-burst/"
#unrespECNDIR="/home/$USER/MOSAICO/picoquic/picoquic-quic-prague_atk/"
nopacingDIR="/home/$USER/MOSAICO/picoquic/picoquic-prague-nopacing/"
unrespECNDIR="/home/$USER/MOSAICO/picoquic/picoquic-prague-unrespECN/"

DEF_PORT="4444"
PRES="\e[1;40m$(hostname)\e[0m:\e[32m$0\e[0m"

function print_usage(){
    echo -e "$PRES: \n\033[0;31mError aguments. Usage: ./$0 <direction> <ECN_MODE> <port> <FLOW_TYPE> <ARGS>"
    echo -e "where:"
    echo -e "\t- <direction> is \"srv\" or \"cli\" "
    echo -e "\t- <ECN_MODE> = [ noecn | classic | l4s ]"
    echo -e "\t- <port> is the port to use"
    echo -e "\t- <FLOW_TYPE> = [ legit | unrespECN | bursts | nopacing ]"
    echo -e "\t- <ARGS> depends of <FLOW_TYPE>, it's the weight of data to request. Must be higher for unrespECN than for burst."
    exit 1
}

# pour lancer le telechargement d'un fichier d'1Mo
## ./picoquicdemo -E -C prague -l output.log -n serv1 10.35.1.79 4444 "doc-1234567.html"

function launch_srv(){
    local PICODIR=$1
    local ECN=$2
    local CCA=$3
    local PORT=$4

    cd $PICODIR
    
    ### Server
    # -E            Utilisation d'ECN
    # -C prague     Utilisation de prague pour le CCA
    # -p 4444       Précision du port d'écoute
    # Plus d'infos sur ./picoquicdemo -h
    CMD="./picoquicdemo $ECN -C $CCA -p $PORT"
    echo -e "$PRES: Launched command: $CMD \nFrom directory: $PICODIR"

    if [ $VERBOSE == "mute" ]; then
        eval $CMD &>/dev/null
    else
	    eval $CMD
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
    
    cd $PICODIR
    rm output.log
    
    if [ $PICODIR != $burstDIR ]; then
        ### Client
        # -n SRV_NAME SRV_IP        Nom et IP du serveur
        # -l output.log             Fichier de log
        CMD="./picoquicdemo $ECN -C $CCA -l output-$TS.log -n $SRV_NAME $SRV_IP $PORT doc-$WEIGHT.html"
        echo -e "$PRES: Launching command: $CMD \nFrom directory: $PICODIR"
        if [ $VERBOSE == "verbose" ]; then
            eval $CMD
        else
            eval $CMD &> /dev/null
        fi
    else
        local cpt=0
        CMD="./picoquicdemo $ECN -C $CCA -l output.tmp -n $SRV_NAME $SRV_IP $PORT doc-$WEIGHT.html"
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

if [[ $# -gt 6 || $# -lt 4 ]]
then
    print_usage
fi

if [ -z $1 ]; then
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
        ECN=""
        ;;
    "classic")
        CCA="cubic"
        ECN="-E"
        ;;
    "l4s")
        CCA="prague"
        ECN="-E"
        ;;
    *)
        CCA="prague"
        ECN="-E"
        ;;
esac

if [ -z $3 ]; then
    PORT=$DEF_PORT
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


#
# srv: # Pour unrespECN, simplement toggle la "reduction"
#     flow-type = [ legit | unrespECN ]
#     ECN_mode = [ noecn | classic | l4s ]
#
# cli: # Pour burst, faire une boucle avec 5 lancement de picoquicdemo et collecter l'output dans un fichier central output.log en prenant soin d'ajouter les timestamps à chaque nouveau lancement. Formater le tout directement en format .csv avec le parser
#     flow-type = [ legit | unrespECN | burst ]
#     ECN_mode = [ noecn | classic | l4s ]
# Peut-être besoin de fusionner launquic.sh avec rebuild-demo.sh

if [ $SIDE == "srv" ]
then
    case $FLOW_T in
    "legit")
        ARGS="$legitDIR $ECN $CCA $PORT"
        ;;
    "unrespECN")
        ARGS="$unrespECNDIR $ECN $CCA $PORT"
        ;;
    "nopacing")
        ARGS="$nopacingDIR $ECN $CCA $PORT"
        ;;
    "vanilla")
        ARGS="$l4sTeamDIR $ECN $CCA $PORT"
        ;;
    *)
        ARGS="$legitDIR $ECN $CCA $PORT"
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
        ARGS="$legitDIR $ECN $CCA $PORT $F_SIZE"
        ;;
    "burst")
        ARGS="$burstDIR $ECN $CCA $PORT $F_SIZE"
        ;;
    "vanilla")
        ARGS="$l4sTeamDIR $ECN $CCA $PORT $F_SIZE"
        ;;
    *)
        ARGS="$legitDIR $ECN $CCA $PORT $F_SIZE"
        ;;
    esac

    if [ -z $6 ]; then
        VERBOSE="mute"
    else
        VERBOSE=$6
    fi

    launch_cli $ARGS $VERBOSE
fi

