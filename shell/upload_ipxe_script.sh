#!/bin/bash
HOST_IP=$1
IPXE_SCRIPT=$2

curl -0 -v -X post -H "Content-Type: text/plain" http://10.200.128.10:8080/v1/bootscript/script.ipxe/${HOST_IP}  --data-binary @${IPXE_SCRIPT}

