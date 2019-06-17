#!/bin/sh


# Hypervisor checking
CMD_HY="xl dmesg  | grep -i -A 10  Speculative"
CMD_XL_INFO="xl info -n |grep -iE '(threads_per_core|xen_commandline)'"


# Filesystem checking
CMD_FSSYS="grep -H . /sys/devices/system/cpu/vulnerabilities/*"

# Dmesg checking
CMD_DMSG_SPECTRE_V2="dmesg | grep -i 'Spectre V2'"

function print()
{
	declare pre_mesg=`echo "[$1]:" | tr [a-z] [A-Z]`
	declare mesg=${2}
	echo $pre_mesg $mesg
}

function check_hy()
{
	for param in $@
	do
		#shift
		echo
		print "dash" "--------------------------------"
		if [ $param = "v" ];then
			print "info" "Checking hypervisor dmesg:"
			eval ${CMD_HY}
		elif [ $param = "xl" ];then
			print "info" "Checking hypervisor xl info:"
			eval ${CMD_XL_INFO}
		fi
	done
}

function check_filesys()
{

	print "info" "Checking file system"
	print "info" "*********************************************************"
	print "info" "---------------[Kernel CMD]------------------------------"
	print "info" "`cat  /proc/cmdline`"
	print "info" "---------------[FileSystem]------------------------------"
	eval "$CMD_FSSYS"
	print "info" "---------------[  Dmesg   ]------------------------------"
	eval "$CMD_DMSG_SPECTRE_V2"
	print "info" "---------------[ CPU flags]------------------------------"
	print "info" "`lscpu | grep 'Flags:'`"
	print "info" "*********************************************************"
}


function start_vm()
{

	declare cmd_for_network_up="/usr/share/qa/qa_test_virtualization/shared/standalone"
	declare vm_name=$1

	print "info" "Start up network"
	chmod a+x ${cmd_for_network_up}
	eval $cmd_for_network_up
	if virsh list --all | grep -i -E "${vm_name}.*running" 2>&1 > /dev/null;then
		:
	elif virsh list --all | grep -i -E "${vm_name}.*shut off" 2>&1 > /dev/null;then
		print "info" "Start up vm ${vm_name}"
		virsh start $vm_name
	fi
}


function get_vm_ip()
{
	declare vm_name=$1
	declare cmd_2_get_mac=`virsh dumpxml  ${vm_name} | xml sel -t -v "/domain/devices/interface/mac/@address"`
	if [ "${cmd_2_get_mac}x" = "x" ];then
		print "error" "Failed to get vm ${vm_name} ip address"
		exit -1
	else
		vm_ip_1="ip neigh | grep ${cmd_2_get_mac} | cut -d' ' -f1"
		vm_ip_2="journalctl --system | grep ${cmd_2_get_mac} | tail -1 | grep -Po '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}'"

		for m in ${!vm_ip*}
		do
			eval "cmd=\$$m"
			#echo "$cmd"
			vm_ip=`echo $cmd | bash `
			#vm_ip=`$cmd`
			#vm_ip=$($cmd)
			if [ "x" = "x${vm_ip}" ];then
				continue
			else
				break
			fi
		done
		echo ${vm_ip}
	fi
}


function vailidate_vm_sshd()
{
	declare vm_ip=$1
	declare port="22"

	if nc -zv ${vm_ip} 22 2>&1 | grep -q succeeded; then 
		return 0
	else 
    		return 1
	fi
}


function check_vm_sysfile()
{
	declare vm_name=$1
	declare vm_user="root"
	declare vm_password="novell"
	declare ssh_nopass="sshpass -e ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"

	declare vm_ip_address=`get_vm_ip $vm_name`
	#get_vm_ip $vm_name
	
	for t in `seq 50`
	do
		if [ "x" = "x${vm_ip_address}" ];then
			vm_ip_address=`get_vm_ip $vm_name`
		fi
		if vailidate_vm_sshd ${vm_ip_address} ;then
			export SSHPASS=$vm_password; $ssh_nopass $vm_user@$vm_ip_address "$(declare -p CMD_FSSYS CMD_DMSG_SPECTRE_V2); $(declare -f check_filesys print); check_filesys 2>&1"
			break

		else
			sleep 3
		fi
	done
	export SSHPASS=$vm_password; $ssh_nopass $vm_user@$vm_ip_address 
	print "error" "Failed to connect to vm ${vm_name}"
}


function main()
{
	declare hvm_guest=sles-15-sp1-64-fv-def-net
        declare pv_guest=sles-15-sp1-64-pv-def-net

        if [ -n "$2" ];then
                hvm_guest=$2
                pv_guest=$2
        fi


	if [ $1 = "hy" ];then
		check_hy "v" "xl"
	elif [ $1 = "pv" ];then
		check_vm_sysfile $pv_guest
	elif [ $1 = "hvm" ];then
		check_vm_sysfile $hvm_guest
	elif [ $1 = "start" ];then
		start_vm $hvm_guest
		start_vm $pv_guest
		
	fi


}

main $1 $2

#check_vm_sysfile "sles-15-sp1-64-fv-def-net"
