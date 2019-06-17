#!/bin/sh

SRC_PATH=/usr/src/packages
CMD_XEN_BUILD="rpmbuild -bp ${SRC_PATH}/SPECS/xen.spec 2>&1 "


function add_repo() {


	zypper ar http://mirror.suse.asia/dist/install/SLP/SLE-12-SP5-SDK-LATEST/x86_64/DVD1/ sdk
	zypper ar http://download.suse.de/ibs/Devel:/Virt:/SLE-12-SP1/SUSE_SLE-12_GA_standard/ figlet_needed
	zypper -n in -t srcpackage xen
	zypper -n ref

}


function install_pkg() {
	local pkg_name=$1
	local refesh_flag=$2
	if [ -n ${refesh_flag} ];then
		zypper -n ref
	fi
	zypper -n in ${pkg_name}

}



function prepare_env() {

	#install_pkg rpm_build

	for times in `seq 1 3`
	do
		eval "${CMD_XEN_BUILD}" > ./log
		if [ $? -ne 0 ];then
			for pkg in `sed -n "s/\(.*\) is needed.*$/\1/gp" ./log`
			do
				install_pkg $pkg

			done
		else
			break
		fi

	done
}

add_repo
prepare_env
