#!/bin/sh


function _get_ip_by_expect {

local guestname=$1

expect -c " 
set timeout 3600

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
expect -re {dev.*?([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})[^0-9]}

if {![info exists expect_out(1,string)]} {
        puts \"Match did not happen :(\"
        exit 1
}

# assign submatch to variable
set output \$expect_out(1,string)
#clear terminal, no work for current situation
unset expect_out(buffer)
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
	#echo $gip
	if [ $ret != 0 ];then
		if [ $ret -eq 8 ];then
			echo "Error: Domian $guestname is not running,"  $w
			exit -1
		fi
	fi

	echo $gip

}

function create_disk() {
	local hyper_type=$1
	local guest_disk_name=$2
	mkdir -p /${hyper_type}
	qemu-img create -f qcow2  ${guest_disk_name}  20G

}

function install_kvm_guest() {
	local guest_name=$1
        local guest_disk_name=$2
	local prd_image_url=$3
	virt-install --name ${guest_name}  --disk path="${guest_disk_name}",format=qcow2,bus=virtio,boot_order=1  --os-variant auto --noautoconsole  --vnc  --cpu host-passthrough  --vcpus=2  --vcpus sockets=1,cores=1,threads=2  --memory=2048   --network bridge=br0,model=virtio --events on_reboot=restart --location="${prd_image_url}" -x "console=ttyS0,115200n8  install=${prd_image_url} YAST_SKIP_XML_VALIDATION=1 autoyast=http://openqa.qa2.suse.asia/assets/autoyast/SLES-15-SP3/KVM/SLES-15-SP3-KVM-AUTOYAST.xml" --wait=-1
	if [ $? -ne 0 ];then
		echo "ERROR: Guest ${guest_name} Installation failure"
	else
		echo "INFO: Guest ${guest_name} installation success"
	fi
}

function install_xen_guest() {
	local guest_type=$1
	local guest_name=$2
        local guest_disk_name=$3
	local prd_image_url=$4
	if [ "pv" == "${guest_type}" ];then
		g_type_parama="-p"
		g_console_param="console=hvc0,115200"
	else
		g_type_parama="-v"
		g_console_param="console=ttyS0,115200n8"
	fi

	virt-install --name ${guest_name} ${g_type_parama} --location "${prd_image_url}" --extra-args "
 ${g_console_param} YAST_SKIP_XML_VALIDATION=1 autoyast=http://openqa.qa2.suse.asia/assets/autoyast/SLES-15-SP3/XEN/HVM/SLES-15-SP3-HVM-AUTOYAST.xml " --disk path=${guest_disk_name},size=20,format=qcow2  --network=bridge=br0   --memory=2048 --vcpu=2    --vnc    --events on_reboot=restart --serial pty --wait=-1
	if [ $? -ne 0 ];then
		echo "ERROR: Guest ${guest_name} Installation failure"
	else
		echo "INFO: Guest ${guest_name} installation success"
	fi
}

function restart_guest() {
	local guest_name=$1
	virsh start ${guest_name}
}

function install_guest() {
	local hyper_type=$1
	local prd_image_url=$2
	local guest_disk_folder="/${hyper_type}"
	if [ "kvm" == "${hyper_type}" ];then
		guest_name="vm_kvm"
		guest_disk_name="/${hyper_type}/${guest_name}"
		create_disk ${hyper_type} ${guest_disk_name}
		install_kvm_guest ${guest_name} ${guest_disk_name} ${prd_image_url}
		restart_guest ${guest_name}
		check_guest ${guest_name}
	else
		hvm_guest_name="hvm_xen"
		guest_disk_name="/${hyper_type}/${hvm_guest_name}"
		create_disk ${hyper_type} ${guest_disk_name}
		install_xen_guest hvm ${hvm_guest_name} ${guest_disk_name} ${prd_image_url}
		restart_guest ${hvm_guest_name}
		check_guest ${hvm_guest_name}

		pv_guest_name="pv_xen"
		guest_disk_name="/${hyper_type}/${pv_guest_name}"
		create_disk ${hyper_type} ${guest_disk_name}
		install_xen_guest pv ${pv_guest_name} ${guest_disk_name} ${prd_image_url}
		restart_guest ${pv_guest_name}
		check_guest ${pv_guest_name}
	fi
        

}

function check_guest() {
	local guest_name=$1
	get_guest_ip_addr ${guest_name}
	if [ $? -ne 0 ];then
		echo "ERROR: Guest ${guest_name} get ip failure"
	else
		echo "INFO: Guest ${guest_name} get ip success"
	fi
}
zypper -n in expect
install_guest $1 $2
