#!/usr/bin/env bats
# *-*- Mode: sh; sh-basic-offset: 8; indent-tabs-mode: nil -*-*
#
# Copyright (c) 2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#
# Swarm testing : This will start swarm as well as it will create and
# run swarm replicas using Nginx

# Image for swarm testing
nginx_image="gabyct/nginx"
# Name of service to test swarm
SERVICE_NAME="testswarm"
# Number of replicas that will be launch
number_of_replicas=1
# Timeout in seconds to verify replicas are running
timeout=10
# Retry number for the curl
number_of_retries=5
# SHIM PATH
SHIM_PATH="${SHIM_PATH:-/usr/libexec/kata-containers/kata-shim}"
# PROXY PATH
PROXY_PATH="${PROXY_PATH:-/usr/libexec/kata-containers/kata-proxy}"

# This function checks if active processes were
# left behind by kata-runtime.

check_processes() {
	process=$1
	pgrep -f "$process"
	if [ $? -eq 0 ]; then
		echo "Found unexpected ${process} present"
		ps -ef | grep $process
		return 1
	fi
}

setup() {
	interfaces=$(basename -a /sys/class/net/*)
	swarm_interface_arg=""
	for i in ${interfaces[@]}; do
		if [ "$(cat /sys/class/net/${i}/operstate)" == "up" ]; then
			swarm_interface_arg="--advertise-addr ${i}"
			break;
		fi
	done
	docker swarm init ${swarm_interface_arg}
	nginx_command="hostname > /usr/share/nginx/html/hostname; nginx -g \"daemon off;\""
	docker service create \
		--name "${SERVICE_NAME}" --replicas $number_of_replicas \
		--publish 8080:80 "${nginx_image}" sh -c "$nginx_command"
	running_regex='Running\s+\d+\s(seconds|minutes)\s+ago'
	for i in $(seq "$timeout") ; do
		docker service ls --filter name="$SERVICE_NAME"
		replicas_running=$(docker service ps "$SERVICE_NAME" | grep -c -P "${running_regex}")
		if [ "$replicas_running" -ge "$number_of_replicas" ]; then
			break
		fi
		sleep 1
		[ "$i" == "$timeout" ] && return 1
	done
}

@test "check_replicas_interfaces" {
	# here we are checking that each replica has two interfaces
	# and they should be always eth0 and eth1
	REPLICA_ID=$(docker ps -q)
	docker exec ${REPLICA_ID} sh -c "ip route show | grep -E eth0 && ip route show | grep -E eth1" > /dev/null
}

teardown() {
	docker service remove "${SERVICE_NAME}"
	docker swarm leave --force
	check_processes ${PROXY_PATH}
	check_processes ${SHIM_PATH}
}
