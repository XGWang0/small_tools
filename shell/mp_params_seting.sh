#!/bin/sh



#GRUB_FILE="/etc/default/grub"
#GRUB_FILE="/tmp/grub"
GRUB_FILE="/etc/default/grub"
XL_PARAMS="xl info | grep  xen_commandline"
KERNEL_PARAMS=`cat /proc/cmdline`

MAX_VCPUS_FLAG=0
DOM0_MEM_FLAG=0
UCODE_FLAG=0


#######################################HYpervisor Setting################################
SPEC_CTRL_L1D_FLUSH_NO_FLAG=0
SPEC_CTRL_L1D_FLUSH_NO="spec-ctrl=l1d-flush=no"

SPEC_CTRL_NO_FLAG=0
SPEC_CTRL_NO="spec-ctrl=no"

XPTI_OFF_FLAG=0
XPTI_OFF="xpti=off"

PV_L1TF_OFF_FLAG=0
PV_L1TF_OFF="pv-l1tf=off"

PV_L1TF_ON_FLAG=0
PV_L1TF_ON="pv-l1tf=on"

SMT_OFF_FLAG=0
SMT_OFF="smt=off"

CPUID_ALL_OFF_FLAG=0
CPUID_ALL_OFF="cpuid=no-ibrsb,no-ibpb,no-stibp,no-ssbd,no-l1d-flush"

DOM0_PARAMS="dom0_max_vcpus=8 dom0_mem=8192M,max:8192M ucode=scan"

#############################################################################

RED='\033[0;31m'
NC='\033[0m'
BLUE='\033[0;34m'

function PRINT() {

	local itype=$1
	shift
	local msg=$*

	if [ ${itype} = "ERROR" ];then
		echo -e "${RED}ERROR: $msg${NC}"
	elif [ ${itype} = "INFO" ];then
		echo -e "${BLUE}INFO: $msg${NC}"
	fi


}


function parse_xl_params() {
	PARM="dom0_max_vcpus=8 dom0_mem=8192M,max:8192M ucode=scan spec-ctrl=l1d-flush=no vga=gfx-1024x768x16 crashkernel=243M<4G"

	for param in $PARM
	do
		case $param in
			dom0_max_vcpus?*)
			echo "---------------dom0_max_vcpu"
			;;
		esac
		echo $param, "-------------"
	done
	
}


function _get_ip_by_expect {

local guestname=$1

expect -c " 
set timeout 200

#hide echo
log_user 0
spawn -noecho virsh console ${guestname}

#wait connection
sleep 3
send \"\r\n\r\n\r\n\"

#condition expect
expect {
        \"*login:\" {
                send \"root\r\"
		exp_continue
        }
        \"*assword\" {
                send \"nots3cr3t\r\"
		exp_continue
        }
        \"*:~ #\" {
                send -- \"ip route get 1\r\"
        }

	\"error: The domain is not running\" {
		puts \"The domain $guestname is not running\"
		exit 8
	}
        timeout {
                puts \"The guest $guestname is broken during installation\"
                exit 9
        }
}

#submatch for output
expect -re {dev.*\s([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})\s}

if {![info exists expect_out(1,string)]} {
        puts \"Match did not happen :(\"
        exit 1
}

# assign submatch to variable
set output \$expect_out(1,string)
#clear terminal, no work for current situation
#puts \033\[2J
unset expect_out(buffer)
# echo submatch 
send \"\\035\\r\"
expect eof
puts \"\$output\"

"
}

function get_guest_ip_addr() {
	local guestname=$1
	local gip
	local ret
	gip=$(_get_ip_by_expect $guestname)
	ret=$?
	if [ $ret != 0 ];then
		if [ $ret -eq 8 ];then
			echo "Error: Domian $guestname is not running,"  $w
			exit -1
		fi
	fi

	echo $gip

}




function set_parse_xl_params() {
	local catagoary=$1
	local sub_options=""

	case ${catagoary} in
		HVM_FULL_DISABLE)
			sub_options=" ${CPUID_ALL_OFF} ${XPTI_OFF} ${SPEC_CTRL_NO} "
			;;
		PV_FULL_DISABLE)
			sub_options=" ${CPUID_ALL_OFF} ${XPTI_OFF} ${SPEC_CTRL_NO} ${PV_L1TF_OFF} "
			;;
		DEFAULT|HVM_DEFAULT|PV_DEFAULT|HVM_L1TF_ENABLE)
			;;
		HVM_PTI_ENABLE|HVM_SPEC2_ENABLE|HVM_SPEC2_USER_ENABLE|HVM_SPEC4_ENABLE)
			sub_options=" ${SPEC_CTRL_L1D_FLUSH_NO} "
			;;
		HVM_L1TF_FULL_ENABLE)
			sub_options=" ${SMT_OFF} "
			;;
		PV_PTI_ENABLE)
			sub_options=" ${PV_L1TF_OFF} "
			;;
		PV_SPEC2_ENABLE|PV_SPEC2_USER_ENABLE|PV_SPEC4_ENABLE)
			sub_options=" ${XPTI_OFF} ${PV_L1TF_OFF} "
			;;
		PV_L1TF_FULL_ENABLE)
			sub_options=" ${XPTI_OFF} ${PV_L1TF_ON} ${SMT_OFF} "
			;;
		PV_L1TF_ENABLE)
			sub_options=" ${XPTI_OFF} ${PV_L1TF_ON}  "
			;;
		default)
			PRINT ERROR  "Input WORD ${catagoary} is in-available" && exit 1
			;;
	esac
	cp ${GRUB_FILE} ${GRUB_FILE}.`date +%Y%m%d%H%M`
	if grep "GRUB_CMDLINE_XEN=" ${GRUB_FILE} > /dev/null;then
		if grep "GRUB_CMDLINE_XEN=.*ucode=scan" ${GRUB_FILE} > /dev/null;then
			sed  -i "/GRUB_CMDLINE_XEN=/{s/\(.*ucode=scan\).*/\1 ${sub_options}\"/g}" ${GRUB_FILE}
		else
			sed -i "/GRUB_CMDLINE_XEN=/d" ${GRUB_FILE}
			sed -i "\$a GRUB_CMDLINE_XEN=\"${DOM0_PARAMS} ${sub_options} \"" ${GRUB_FILE}
		fi
	else
		sed -i "\$a GRUB_CMDLINE_XEN=\"${DOM0_PARAMS} ${sub_options} \"" ${GRUB_FILE}
	fi
	cp /boot/grub2/grub.cfg /boot/grub2/grub.cfg.`date +%Y%m%d%H%M`
	grub2-mkconfig -o  /boot/grub2/grub.cfg
}


HY_XL_FILE=hy_xl_file.log
HY_XL_LIST_FILE=hy_xl_list_file.log
HY_XL_DMESG_FILE=hy_xl_dmesg_file.log
GUEST_QEMU_CMD_FILE=guest_qemu_cmd.log
HY_LSMOD_FILE=hy_lsmod.log


function collect_hy_files() {
	local guestname=$1
	local tempdir=$2

	mkdir -p $tempdir
	xl info -n > ${tempdir}/${HY_XL_FILE}
	xl list --long > ${tempdir}/${HY_XL_LIST_FILE}
	xl dmesg > ${tempdir}/${HY_XL_DMESG_FILE}
	cp /etc/xen/xl.conf  ${tempdir}
	virsh dumpxml ${guestname} > ${tempdir}/${guestname}.xml
	find /boot -iregex ".*/xen.*config\|.*/config.*-default" -exec cp {} ${tempdir} \;
	cp /boot/grub2/grub.cfg  ${tempdir}
	ps -ef | grep [q]emu > ${tempdir}/${GUEST_QEMU_CMD_FILE}
	lsmod > ${tempdir}/${HY_LSMOD_FILE}
	cp -r /etc/modprobe.d ${tempdir}
	cat /proc/cmdline > ${tempdir}/dom0_cmdline.log
	cat /proc/meminfo > ${tempdir}/dom0_meminfo.log
	zypper -n se -s -i > ${tempdir}/installed_pkgs.log


}

function start_vm() {
	local guestname=$1
	if virsh list | grep $guestname >/dev/null;then
		:
	else
		virsh start $guestname
		[ $? -ne 0 ] && exit -1
	fi

}

function stop_vm() {
	local guestname=$1
	if virsh list | grep $guestname > /dev/null;then
		virsh destroy $guestname
		[ $? -ne 0 ] && exit -1
	fi
}

GUEST_UPLOAD_DIR=/tmp/HY_INFO_DIR

function transfer_file2_guest() {
	local guestname=$1
	local password=$2
	local transfered_dir=`mktemp -d -t hy_folder.XXXXXX`

	start_vm ${guestname}
	collect_hy_files ${guestname} ${transfered_dir}/hypervisor

	local guestip=$(get_guest_ip_addr ${guestname}) 

	sshpass -p ${password} ssh root@${guestip} "rm -rf ${GUEST_UPLOAD_DIR}"
	sshpass -p ${password} scp -r ${transfered_dir} root@${guestip}:${GUEST_UPLOAD_DIR}
	
	sshpass -p ${password} ssh root@${guestip} "sed -i \"/SQ_TEST_EXTLOG_DIR=/d\" /root/qaset/config"
	sshpass -p ${password} ssh root@${guestip} "echo SQ_TEST_EXTLOG_DIR=${GUEST_UPLOAD_DIR} >>/root/qaset/config"

	
	sshpass -p ${password} ssh root@${guestip} "grep NETWORK_RIP /root/qaset/config > /dev/null || echo  -e \"NETWORK_RIP=\nNETWORK_INF=\nNETWORK_PINF=\n\" >> /root/qaset/config"
}



function set_kernel_params() {
	local param=$1
	cp /etc/default/grub /etc/default/grub.bak
	sed -ie "/^GRUB_CMDLINE_LINUX=/s/\".*\"/\" loglevel=0 $param \"/g" /etc/default/grub
	grub2-mkconfig -o /boot/grub2/grub.cfg
	echo "Finished kernel setting for [$param]"
	reboot
}


function set_mitigation_params {
	local param=$1


##################################Mitigation Options#######################
	MITIGATION_AUTO="mitigations=auto"
	MITIGATION_OFF="mitigations=off"
	MITIGATION_AUTO_NOSMT="mitigations=auto,nosmt"
	
	MELTDOWN_ON="pti=on"
	MELTDOWN_OFF="pti=off"
	MELTDOWN_NO="nopti"
	
	SPECTRE_V2_ON="spectre_v2=on"
	SPECTRE_V2_OFF="spectre_v2=off"
	SPECTRE_V2_NO="nospectre_v2"
	SPECTRE_V2_RETPOLINE="spectre_v2=retpoline"
	SPECTRE_V2_IBRS="spectre_v2=ibrs"
	
	SPECTRE_V2_USER_PRCTL="spectre_v2_user=prctl"
	SPECTRE_V2_USER_ON="spectre_v2_user=on"
	SPECTRE_V2_USER_OFF="spectre_v2_user=off"
	SPECTRE_V2_USER_PRCTLIBPB="spectre_v2_user=prctl,ibpb"
	SPECTRE_V2_USER_SECCOMP="spectre_v2_user=seccomp"
	SPECTRE_V2_USER_SECCOMPIBPB="spectre_v2_user=seccomp,ibpb"
	
	SPECTRE_V4_ON="spec_store_bypass_disable=on"
	SPECTRE_V4_OFF="spec_store_bypass_disable=off"
	SPECTRE_V4_NO="nospec_store_bypass_disable"
	SPECTRE_V4_SECCOMP="spec_store_bypass_disable=seccomp"
	SPECTRE_V4_PRCTL="spec_store_bypass_disable=prctl"
	
	MDS_ON="mds=full"
	MDS_OFF="mds=off"
	MDS_ON_NOSMT="mds=full,nosmt"
################################################################################

	echo '################################################################'
	PRINT INFO "Run Test Case [$param]"
	case ${param} in 
		MITIGATION_AUTO)
		set_kernel_params ${MITIGATION_AUTO}
		;;
		MITIGATION_OFF)
		set_kernel_params ${MITIGATION_OFF}
		;;
		MITIGATION_AUTO_NOSMT)
		set_kernel_params ${MITIGATION_AUTO_NOSMT}
		;;
		POSITIVE_ALL_OPTS)
		set_kernel_params " ${MELTDOWN_ON}  ${SPECTRE_V2_ON} ${SPECTRE_V2_USER_ON} ${SPECTRE_V4_ON} ${MDS_ON} "
		;;
		NAGATIVE_ALL_OPTS_OFF)
		set_kernel_params " ${MELTDOWN_OFF} ${SPECTRE_V2_OFF} ${SPECTRE_V2_USER_OFF} ${SPECTRE_V4_OFF} ${MDS_OFF} "
		;;
		NAGATIVE_ALL_OPTS_NO)
		set_kernel_params " ${MELTDOWN_NO} ${SPECTRE_V2_NO} ${SPECTRE_V2_USER_ON} ${SPECTRE_V4_NO} ${MDS_OFF} "
		;;
		RANDOM_SETTING1)
		#SPECTRE_V2_RETPOLINE="spectre_v2=retpoline"
		#SPECTRE_V4_PRCTL="spec_store_bypass_disable=prctl"
		#SPECTRE_V2_USER_PRCTL="spectre_v2_user=prctl"
		#MDS_ON_NOSMT="mds=full,nosmt"
		set_kernel_params " ${SPECTRE_V2_RETPOLINE} ${SPECTRE_V2_USER_PRCTL} ${SPECTRE_V4_PRCTL} ${MDS_ON_NOSMT} "
		;;
		RANDOM_SETTING2)
		#SPECTRE_V4_SECCOMP="spec_store_bypass_disable=seccomp"
		#SPECTRE_V2_USER_SECCOMP="spectre_v2_user=seccomp"
		set_kernel_params " ${SPECTRE_V2_USER_SECCOMP} ${SPECTRE_V4_SECCOMP} "
		;;
		SPECTRE_V2_PRCTL_IBPB)
		set_kernel_params " ${SPECTRE_V2_USER_PRCTLIBPB} "
		;;

		SPECTRE_V2_SECCOMP_IBPB)
		set_kernel_params " ${SPECTRE_V2_USER_SECCOMPIBPB} "
		;;
		*)
		PRINT ERROR  "No kernel setting for [$param]"
		return 1
		;;
	esac

}

function set_guest_kernel() {
	local guestname=$1
	local param=$2

	[ -z "${password}" ] && password=nots3cr3t

	start_vm ${guestname}

	local guestip=$(get_guest_ip_addr ${guestname})

	PRINT INFO "Guest IP: [ ${guestip}]"

	sshpass -p ${password} ssh root@${guestip} "$(typeset -f); set_mitigation_params ${param}"

}



function verify_result() {
	local ver_obj=$1
	shift

	local vul_value_cmd="grep . -H /sys/devices/system/cpu/vulnerabilities/*"
        local vul_value_dmesg_cmd="dmesg | grep -i spect "


	if [ ${ver_obj} == "sys" ];then
		output=`$vul_value_cmd`
	elif [ ${ver_obj} == "dmesg" ];then
		output=`echo $vul_value_dmesg_cmd | bash`
	fi


	echo "=================================================="
	for value in "$@"
	do
		if echo $output | grep -i "$value" > /dev/null;then
			PRINT INFO "Pass"
		else
			PRINT INFO  "Fail; Execpted Value:${value}, Actual Value:${output}"
		fi

	done
	echo "=================================================="
	echo
}


function verify_mitigation_result(){
	local guestname=$1
	local param=$2

	[ -z "${password}" ] && password=nots3cr3t
	sleep 10
	if virsh list | grep -i ${guestname} > /dev/null;then
		:
	else
		start_vm ${guestname}
	fi
	local guestip=$(get_guest_ip_addr ${guestname}) 


	MELTDOWN_ON_VALUE="/sys/devices/system/cpu/vulnerabilities/meltdown:Mitigation: PTI"
	MELTDOWN_OFF_VALUE="/sys/devices/system/cpu/vulnerabilities/meltdown:Vulnerable"

	SPECTRE_V2_ON_VALUE="/sys/devices/system/cpu/vulnerabilities/spectre_v2:Mitigation: Full generic retpoline, IBPB: conditional, IBRS_FW, RSB filling"
	SPECTRE_V2_OFF_VALUE="/sys/devices/system/cpu/vulnerabilities/spectre_v2:Vulnerable, IBPB: disabled, STIBP: disabled"

	SPECTRE_V2_ON_USER_VALUE="/sys/devices/system/cpu/vulnerabilities/spectre_v2:Mitigation: Full generic retpoline, IBPB: always-on, IBRS_FW, RSB filling"
	SPECTRE_V2_USER_PRCTL_VALUE="Spectre V2 : User space: Mitigation: STIBP via prctl"
	SPECTRE_V2_USER_SECCOMP_VALUE="Spectre V2 : User space: Mitigation: STIBP via seccomp and prctl"


	SPECTRE_V4_ON_VALUE="/sys/devices/system/cpu/vulnerabilities/spec_store_bypass:Mitigation: Speculative Store Bypass disabled via prctl and seccomp"
	SPECTRE_V4_OFF_VALUE="/sys/devices/system/cpu/vulnerabilities/spec_store_bypass:Vulnerable"
	SPECTRE_V4_PRCTL_VALUE="/sys/devices/system/cpu/vulnerabilities/spec_store_bypass:Mitigation: Speculative Store Bypass disabled via prctl"
	SPECTRE_V4_SECCOMP_VALUE=${SPECTRE_V4_ON_VALUE}


	SPECTRE_MDS_ON_VALUE="/sys/devices/system/cpu/vulnerabilities/mds:Mitigation: Clear CPU buffers; SMT Host state unknown"
	SPECTRE_MDS_OFF_VALUE="/sys/devices/system/cpu/vulnerabilities/mds:Vulnerable; SMT Host state unknown"


	PRINT INFO "Verify Test Case [$param]"
	PRINT INFO "Current Kernl Param:"
	sshpass -p ${password} ssh root@${guestip} "cat /proc/cmdline"
	echo
	case ${param} in 
		MITIGATION_AUTO)
		sshpass -p ${password} ssh root@${guestip} "$(typeset -f ); verify_result \"sys\" \"${MELTDOWN_ON_VALUE}\" \"${SPECTRE_V2_ON_VALUE}\" \"${SPECTRE_V4_ON_VALUE}\" \"${SPECTRE_MDS_ON_VALUE}\" "
		sshpass -p ${password} ssh root@${guestip} "$(typeset -f ); verify_result \"dmesg\"   \"${SPECTRE_V2_USER_SECCOMP_VALUE}\"  "

		;;
		MITIGATION_OFF)
		sshpass -p ${password} ssh root@${guestip} "$(typeset -f ); verify_result \"sys\" \"${MELTDOWN_OFF_VALUE}\"  \"${SPECTRE_V2_OFF_VALUE}\" \"${SPECTRE_V4_OFF_VALUE}\" \"${SPECTRE_MDS_OFF_VALUE}\" "
		;;
		MITIGATION_AUTO_NOSMT)
		sshpass -p ${password} ssh root@${guestip} "$(typeset -f ); verify_result \"sys\" \"${MELTDOWN_ON_VALUE}\" \"${SPECTRE_V2_ON_VALUE}\"  \"${SPECTRE_V4_ON_VALUE}\" \"${SPECTRE_MDS_ON_VALUE}\" "
		sshpass -p ${password} ssh root@${guestip} "$(typeset -f ); verify_result \"dmesg\"   \"${SPECTRE_V2_USER_SECCOMP_VALUE}\"  "
		;;
		POSITIVE_ALL_OPTS)
		sshpass -p ${password} ssh root@${guestip} "$(typeset -f ); verify_result \"sys\" \"${MELTDOWN_ON_VALUE}\" \"${SPECTRE_V2_ON_USER_VALUE}\"  \"${SPECTRE_V4_ON_VALUE}\" \"${SPECTRE_MDS_ON_VALUE}\" "
		sshpass -p ${password} ssh root@${guestip} "$(typeset -f ); verify_result \"dmesg\"   \"${SPECTRE_V2_USER_SECCOMP_VALUE}\"  "
		;;
		NAGATIVE_ALL_OPTS_OFF)
		sshpass -p ${password} ssh root@${guestip} "$(typeset -f ); verify_result \"sys\" \"${MELTDOWN_OFF_VALUE}\"  \"${SPECTRE_V2_OFF_VALUE}\" \"${SPECTRE_V4_OFF_VALUE}\" \"${SPECTRE_MDS_OFF_VALUE}\" "
		;;
		NAGATIVE_ALL_OPTS_NO)
		sshpass -p ${password} ssh root@${guestip} "$(typeset -f ); verify_result \"sys\" \"${MELTDOWN_OFF_VALUE}\"  \"${SPECTRE_V2_OFF_VALUE}\" \"${SPECTRE_V4_OFF_VALUE}\" \"${SPECTRE_MDS_OFF_VALUE}\" "
		;;
		RANDOM_SETTING1)
		#SPECTRE_V2_RETPOLINE="spectre_v2=retpoline"
		#SPECTRE_V4_PRCTL="spec_store_bypass_disable=prctl"
		#SPECTRE_V2_USER_PRCTL="spectre_v2_user=prctl"
		#MDS_ON_NOSMT="mds=full,nosmt"
		sshpass -p ${password} ssh root@${guestip} "$(typeset -f ); verify_result \"sys\"   \"${SPECTRE_V2_ON_VALUE}\" \"${SPECTRE_V4_PRCTL_VALUE}\" \"${SPECTRE_MDS_ON_VALUE}\" "
		sshpass -p ${password} ssh root@${guestip} "$(typeset -f ); verify_result \"dmesg\"   \"${SPECTRE_V2_USER_PRCTL_VALUE}\"  "
		;;
		RANDOM_SETTING2)
		#SPECTRE_V4_SECCOMP="spec_store_bypass_disable=seccomp"
		#SPECTRE_V2_USER_SECCOMP="spectre_v2_user=seccomp"
		sshpass -p ${password} ssh root@${guestip} "$(typeset -f ); verify_result \"sys\"   \"${SPECTRE_V2_ON_VALUE}\" \"${SPECTRE_V4_SECCOMP_VALUE}\"  "
		sshpass -p ${password} ssh root@${guestip} "$(typeset -f ); verify_result \"dmesg\"   \"${SPECTRE_V2_USER_SECCOMP_VALUE}\"  "
		;;
		SPECTRE_V2_PRCTL_IBPB)
		sshpass -p ${password} ssh root@${guestip} "$(typeset -f ); verify_result \"sys\"   \"${SPECTRE_V2_ON_USER_VALUE}\"  "
		sshpass -p ${password} ssh root@${guestip} "$(typeset -f ); verify_result \"dmesg\"   \"${SPECTRE_V2_USER_PRCTL_VALUE}\" "
		;;
		SPECTRE_V2_SECCOMP_IBPB)
		sshpass -p ${password} ssh root@${guestip} "$(typeset -f ); verify_result \"sys\"   \"${SPECTRE_V2_ON_USER_VALUE}\"   "
		sshpass -p ${password} ssh root@${guestip} "$(typeset -f ); verify_result \"dmesg\"   \"${SPECTRE_V2_USER_SECCOMP_VALUE}\" "
		;;
		*)
		PRINT ERROR "No verification result for [$param]"
		;;
	esac
}


function mitigation_func_test() {
	local guestname=$1
	shift
	local user_testcase=$@
	full_testcases="MITIGATION_AUTO MITIGATION_OFF MITIGATION_AUTO_NOSMT POSITIVE_ALL_OPTS NAGATIVE_ALL_OPTS_OFF NAGATIVE_ALL_OPTS_NO RANDOM_SETTING1 RANDOM_SETTING2 SPECTRE_V2_PRCTL_IBPB SPECTRE_V2_SECCOMP_IBPB"
	
	testcases=$user_testcase
	[ -z "${user_testcase}" ] && testcases=$full_testcases 

	for case in $testcases
	do
		set_guest_kernel $guestname $case
		verify_mitigation_result $guestname $case
	done

}



function usage(){

	echo "$0
		SET_XL_PARM \$MITIGATION_PARAM:
				HVM_FULL_DISABLE
				PV_FULL_DISABLE
				DEFAULT|HVM_DEFAULT|PV_DEFAULT|HVM_L1TF_ENABLE
				HVM_PTI_ENABLE|HVM_SPEC2_ENABLE|HVM_SPEC2_USER_ENABLE|HVM_SPEC4_ENABLE
				HVM_L1TF_FULL_ENABLE
				PV_PTI_ENABLE
				PV_SPEC2_ENABLE|PV_SPEC2_USER_ENABLE|PV_SPEC4_ENABLE
				PV_L1TF_FULL_ENABLE
				PV_L1TF_ENABLE

		 TRANS_FILE \$GUESTNAME     

		 COLLECT_FILE \$GUESTNAME \$LOCATION"
		 exit -1
}


##################################MAIN##########################
case $1 in
	SET_XL_PARM)
		set_parse_xl_params $2
		;;
	TRANS_FILE)
		transfer_file2_guest $2 nots3cr3t
		;;
	COLLECT_FILE)
		collect_hy_files $2 $3
		;;
	*)
		echo
		#usage
		;;
esac

#set_guest_kernel $1 MITIGATION_AUTO
mitigation_func_test $* 
#set_parse_xl_params $1
#transfer_file2_guest $1 nots3cr3t 
