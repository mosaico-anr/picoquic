#!/usr/bin/expect

set PORT [lindex $argv 0]

spawn ./build/picoquic_sample server $PORT ./ca-cert.pem ./server-key.pem ./server_files

# send passcode
expect "Enter PEM pass phrase:"
send -- "0000\n\r"

sleep 60
expect eof
