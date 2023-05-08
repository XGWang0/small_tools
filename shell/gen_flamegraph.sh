#!/bin/sh




function install_env {
	zypper in -y git
	git clone https://github.com/brendangregg/FlameGraph

}

function usage() {
	echo "$0 pid PID PREFIX_FOR_OUTPUT"
	echo "$0 cmd  PREFIX_FOR_OUTPUT  CMD"
}

install_env
usage

if [ $1 == "pid" ];then
	PID=$2
	prefix=$3
	output=${prefix}_perf.data
	perf record -a -g -p ${PID} -o ${output}
elif [ $1 == "cmd" ];then
	prefix=$2
	shift
	shift
	cmd=$*
	output=${prefix}_perf.data
	perf record -a -g -o ${output} $cmd
fi
	


function gen_flamegraph() {

	perf  script  -i  ${output}  >  ${output}.unfold

	FlameGraph/stackcollapse-perf.pl  ${output}.unfold  >  ${output}.folded

	FlameGraph/flamegraph.pl  ${output}.folded  >  ${output}.svg
}

gen_flamegraph
