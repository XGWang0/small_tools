#!/bin/sh


function create_br_on_host() {
	local interface=$1
	local bridgeip=$2
	local bridgename=$3

	if [ -z ${bridgename} ];then
		bridgename=brN
	fi

	if ip a | grep -i ${bridgename} > /dev/null;then
		ip link delete brN
	fi

	ip link add name ${bridgename} type bridge

	ip link set ${bridgename} up 
	ip link set ${interface} up

	ip link set ${interface} master ${bridgename}

	ip address add dev ${bridgename} ${bridgeip}/24	

}

function attach_br_2guest() {
	local guestname=$1
	local bridgename=brN

	local ifmode_options=
	if ! virsh domiflist ${guestname} | grep -i ${bridgename} > /dev/null;then
		if echo ${guestname} | grep -i "hvm" >/dev/null;then
			local model="e1000"
			ifmode_options=" --model ${model}"
		fi
		virsh destroy  ${guestname}
		virsh attach-interface  ${guestname} ${ifmode_options} --type bridge --source brN --persistent
		virsh start ${guestname}
	fi

}

function usage() {

	echo "$0 
		 -g GUESTNAME, 
                 -i LOCAL INTERFACE,
		 -a IP ADDRESS"
	exit 
}

while getopts "g:i:a:" arg; do
  case $arg in
    g)
      guestname=$OPTARG
      ;;
    i)
      interface=$OPTARG
      ;;
    a)
      networkip=$OPTARG
      ;;
    *)
      usage
      ;;
  esac
done


create_br_on_host $interface $networkip
attach_br_2guest $guestname

