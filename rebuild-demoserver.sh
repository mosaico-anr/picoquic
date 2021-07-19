#!/bin/bash

PICODIR="./"

function rebuild() {
    local PICODIR=$1

    cd $PICODIR
    cmake .
    make

    echo "Re-make done with the following segment size and memory buffer:"

    sed -n '666,684p' $PICODIR"picoquic/demoserver.c"

    echo -e "\nPrague configuration for reduction:\n"
    sed -n '111,152p' $PICODIR"picoquic/prague.c"
}

rebuild $PICODIR
