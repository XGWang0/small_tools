#!/bin/sh



# Create bridge

function create_bridge() {
	local net_interface=$1
	local net_mac_address=$2

	nmcli connection add type bridge con-name br0 ifname br0
	nmcli connection add type ethernet slave-type bridge con-name br0-port1 ifname ${net_interface} master br0
	nmcli connection modify br0 connection.autoconnect-slaves 1 # optional
	nmcli connection modify br0 bridge.stp no ethernet.cloned-mac-address ${net_mac_address} # stp disable is mandatory
	nmcli con up br0
}


# Install package

function install_package() {

	zypper ar http://mirror.suse.asia/ibs/QA:/Head/SLES-16.0/ qahead
	zypper -n --gpg-auto-import-keys ref
	zypper -n in --allow-vendor-change screen wget sysstat cpupower numactl nfs-client lsscsi pciutils smartmontools bc netcat-openbsd
	
	wget http://10.200.134.67/repo/sleperf.tar
	tar -xf sleperf.tar
	./sleperf/SLEPerf/common-infra/installer.sh
	./sleperf/SLEPerf/scheduler-service/installer.sh

	semanage fcontext -a -s system_u -t usr_t "/usr/share/qa(/.*)?"
	semanage fcontext -a -s system_u -t bin_t "/usr/share/qa/qaset/bin(/.*)?"
	semanage fcontext -a -s system_u -t bin_t "/usr/share/qa/perfcom/perfcmd.py"
	semanage fcontext -a -s system_u -t systemd_unit_file_t "/usr/lib/systemd/system/qaperf.service"
	  
	restorecon -FR -v /usr/share/qa
	restorecon -FR -v /usr/lib/systemd/system/qaperf.service
	restorecon -FR -v /etc/systemd/system/multi-user.target.wants/qaperf.service

}


# New qcow2
function create_qcow2() {

	local disk_id=$1

	mkdir -p /kvm/
	mkdir -p /kvm/disk_io
	 
	local disk_name=`readlink -f /dev/disk/by-id/${disk_id}`
	local partition_name=${disk_name}1
	mkfs.xfs -f ${partition_name}
	mount ${partition_name} /kvm/disk_io
	 
	 
	qemu-img create -f qcow2 /kvm/base_vm.qcow2 20G
	chown qemu:qemu /kvm/base_vm.qcow2
	 
	qemu-img create -f qcow2 /kvm/disk_io/vm-kvm.test_disk 60G
	chown qemu:qemu /kvm/disk_io/vm-kvm.test_disk


}

# Install base guest
function install_guest() {
	local build_num=$1
	virt-install --name sles16 --disk path=/kvm/base_vm.qcow2,format=qcow2,bus=virtio,boot_order=1 --osinfo detect=on,require=off  --noautoconsole --vnc  --cpu host-passthrough --vcpus=12  --memory=16384 --network bridge=br0,model=virtio --events on_reboot=restart  --location="http://10.145.10.207/assets/repo/SLES-16.0-Online-x86_64-Build${build_num}.install/,kernel=boot/x86_64/loader/linux,initrd=boot/x86_64/loader/initrd" -x "console=ttyS0 linuxrc.log=/dev/ttyS0 linuxrc.core=/dev/ttyS0,115200  live.password=nots3cr3t  agama.install_url=http://10.145.10.207/assets/repo/SLES-16.0-x86_64-Build${build_num} root=live:http://10.145.10.207/assets/iso/SLES-16.0-Online-x86_64-Build${build_num}.install.iso  inst.auto=http://10.200.129.6/assets/autoyast/vt_perf_openqa/guest_common_profile.jsonnet inst.finish=poweroff inst.register_url=http://all-${build_num}.scc-proxy.suse.de/ "

}

# import guest

function import_guest() {

	local guest_name=$1

	virsh shutdown sles16
	sleep 10
	virsh undefine sles16
	 
	 
	qemu-img create -f qcow2 -b /kvm/base_vm.qcow2 -F qcow2 /kvm/${guest_name}.fs_disk
	 
	 
	# Import guest for io test
	virt-install --name ${guest_name}  --disk path="/kvm/${guest_name}.fs_disk",format=qcow2,bus=virtio,boot_order=1  --import  --osinfo detect=on,require=off  --noautoconsole  --vnc  --cpu host-passthrough  --vcpus=12  --memory=8192  --network bridge=br0,model=virtio   --qemu-commandline="     -device pcie-root-port,addr=09.0,id=pci.10 -drive file=/kvm/disk_io/vm-kvm.test_disk,format=qcow2,l2-cache-size=8388608,if=none,cache=none,id=drive-virtio-disk1 -device virtio-blk-pci,drive=drive-virtio-disk1,id=virtio-disk1,bus=pci.10  "
}

function set_hostname() {
	echo "[main]" > /etc/NetworkManager/NetworkManager.conf
	echo "hostname-mode=none" >> /etc/NetworkManager/NetworkManager.conf

	hostnamectl set-hostname $1
	systemctl restart NetworkManager.service
}

function parted_virt_disk() {
	if [ ! -f /dev/vdb1 ];then
		parted /dev/vdb --script -- mklabel gpt
		parted /dev/vdb --script -- mkpart primary xfs 32MiB -1
		mkfs.xfs -f -L ABUILD /dev/vdb1 && sync
	fi
}

function edit_config() {

	local milestone=$1
	local host_ip=$2
	local guest_name=$3
	rm -rf /root/qaset/config
cat << EOL >> /root/qaset/config
PRODUCT_RELEASE=sles-16
PRODUCT_BUILD=${milestone}
_QASET_ROLE=Virt-Performance
SQ_TEST_RUN_SET=performance
SQ_MSG_QUEUE_ENALBE=y
_QASET_SOFTWARE_TAG=VT
_QASET_SOFTWARE_SUB_TAG=vm
KVM=1
_REMOTE_HOSTNAME=${host_ip}:${guest_name}
NPB_CLASS_SET=C
SQ_ABUILD_PARTITION=/dev/vdb1
EOL


}

function edit_list() {
	local host_ip=$1
	rm -rf /root/qaset/list
cat << EOL >> /root/qaset/list
#!/bin/bash

SQ_TEST_RUN_LIST=(

#default enable

_monitor_all_off
perf_syscall
perf_syscall
perf_syscall


_monitor_iostat_vmstat_turbostat_pidstat_pages_memory_on
_remote_${host_ip}_monitor_xentop_iostat_vmstat_turbostat_pidstat_pages_memory_on

workload_database_postgre_smallMem_pgbench_read_xfs
workload_database_postgre_smallMem_pgbench_read_xfs
workload_database_postgre_smallMem_pgbench_read_xfs
workload_database_postgre_smallMem_pgbench_rw_xfs
workload_database_postgre_smallMem_pgbench_rw_xfs
workload_database_postgre_smallMem_pgbench_rw_xfs
io_block_generic_fio_singlejob_fsync_xfs
io_block_generic_fio_singlejob_fsync_xfs
io_block_generic_fio_singlejob_fsync_xfs
io_block_generic_fio_singlejob_async_xfs
io_block_generic_fio_singlejob_async_xfs
io_block_generic_fio_singlejob_async_xfs
workload_database_mariadb_sysbench_read_xfs
workload_database_mariadb_sysbench_read_xfs
workload_database_mariadb_sysbench_read_xfs
io_block_generic_fio_async_xfs
io_block_generic_fio_async_xfs
io_block_generic_fio_async_xfs
io_block_generic_fio_fsync_xfs
io_block_generic_fio_fsync_xfs
io_block_generic_fio_fsync_xfs

_monitor_all_off
_remote_monitor_all_off

workload_NPB_BT_mpich
workload_NPB_BT_openmp
workload_NPB_CG_mpich
workload_NPB_CG_openmp
workload_NPB_EP_mpich
workload_NPB_EP_openmp
workload_NPB_FT_mpich
workload_NPB_FT_openmp
workload_NPB_IS_mpich
workload_NPB_IS_openmp
workload_NPB_LU_mpich
workload_NPB_LU_openmp
workload_NPB_MG_mpich
workload_NPB_MG_openmp
workload_NPB_SP_mpich
workload_NPB_SP_openmp
workload_NPB_UA_openmp

)
EOL

}

function run_qaset() {

/usr/share/qa/qaset/qaset reset
 
/usr/share/qa/qaset/run/performance-run.upload_Beijing
}

function add_kernel_tag2_config() {

	local kernel_tag=$1
	echo "_QASET_KERNEL_TAG=${kernel_tag}" >> /root/qaset/config
}


U1_NET_INTERFACE=eno1np0
U1_NET_MAC_ADDRESS='3C:EC:EF:E3:1D:62'
U1_DISK_ID='scsi-35002538fa4605e15'
U1_GUEST_NAME='vm-kvm-1u-perf02'
U1_GUEST_CPUS=12
U1_GUEST_MEMS=8192
U1_HOST_IP=10.146.4.158

U2_NET_INTERFACE=eno1np0
U2_NET_MAC_ADDRESS='7c:c2:55:82:5d:46'
U2_DISK_ID='scsi-3600062b2136b18402ebe2f74be00aaab'
U2_GUEST_NAME='vm-kvm-2u-perf02'
U2_GUEST_CPUS=8
U2_GUEST_MEMS=8192
U1_HOST_IP=10.146.4.162




function prepare_u1_machine() {
	local BUILD_NUM=$1
	#create_bridge ${U1_NET_INTERFACE} ${U1_NET_MAC_ADDRESS}
	#
	#install_package
	#
	#create_qcow2 ${U1_DISK_ID}
	#
	#install_guest ${BUILD_NUM}
	#
	import_guest ${U1_GUEST_NAME} ${U1_GUEST_CPUS} ${U1_GUEST_MEMS}
}

function prepare_u2_machine() {
	local BUILD_NUM=$1
	create_bridge ${U2_NET_INTERFACE} ${U2_NET_MAC_ADDRESS}
	
	install_package
	
	create_qcow2 ${U2_DISK_ID}
	
	install_guest ${BUILD_NUM}
	
	#import_guest ${U2_GUEST_NAME} ${U2_GUEST_CPUS} ${U2_GUEST_MEMS}
}

function usage() {

	echo "prepare_u1_machine 124.1"	
	echo "prepare_u2_machine 124.1"	
	echo "create_bridge em1 3C:EC:EF:E3:1D:62"
	echo "install_package"
	echo "create_qcow2 scsi-35002538fa4605e15"
	echo "install_guest 97.3"
	echo "import_guest vm-kvm-1u-perf02 12 8192"
	echo "set_hostname vm-kvm-1u-perf02"
	echo "parted_virt_disk"
	echo "edit_config RC1 10.146.4.158 vm-kvm-1u-perf02"
	echo "add_kernel_tag2_config -host_xxx-guest_xxx"
	echo "edit_list 10.146.4.158"
	echo "run_qaset"
	exit -1
}


if [ $# -ge 2 -o "k$1" != "k-h" ];then
	${*}
else
	usage
fi
