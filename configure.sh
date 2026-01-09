#!/bin/bash

# Copyright 2026 VNXME
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Ref: https://filipenf.github.io/2015/12/06/bash-calculating-ip-addresses/
# Receives an IPv4/mask parameter and returns the nth IPv4 in that range
get_nth_ipv4() {
	# Converts an int to an IPv4 netmask as 24 -> 255.255.255.0
	netmask() {
		local mask=$((0xffffffff << (32 - $1))); shift
		local ip n
		for n in 1 2 3 4; do
			ip=$((mask & 0xff))${ip:+.}$ip
			mask=$((mask >> 8))
		done
		echo "${ip}"
	}

	local i1 i2 i3 i4 mask m1 m2 m3 m4
	IFS=". /" read -r i1 i2 i3 i4 mask <<< "$1"
	IFS=" ." read -r m1 m2 m3 m4 <<< "$(netmask "${mask}")"
	printf "%d.%d.%d.%d\n" "$((i1 & m1))" "$((i2 & m2))" "$((i3 & m3))" "$(($2 + (i4 & m4)))"
}

new() {
	local IFACE="$1"
	if [ -z "${IFACE}" ]; then
		echo "$(basename -- "$0"): Error: An interface name must be provided. Exiting"
		exit 1
	fi
	if [ -s "./${IFACE}.conf" ] || [ -d "./${IFACE}" ]; then
		echo "$(basename -- "$0"): Error: The interface name already exists. Exiting"
		exit 1
	fi

	mkdir -p "./${IFACE}"

	local LOCAL_PRIVATE_KEY="$(awg genkey)"
	echo "${LOCAL_PRIVATE_KEY}" > "./${IFACE}/local_private.key"

	local LOCAL_PUBLIC_KEY="$(echo "${LOCAL_PRIVATE_KEY}" | awg pubkey)"
	echo "${LOCAL_PUBLIC_KEY}" > "./${IFACE}/local_public.key"

	# Choose a local 24-bit IPv4 subnet from the 192.168.0.0/16 block based on the first byte of the public key
	local LOCAL_IPV4_BYTE="$(echo "${LOCAL_PUBLIC_KEY}" | base64 -d | dd bs=1 count=1 skip=0 status=none | xxd -p)"
	local LOCAL_IPV4_NET="192.168.$((16#${LOCAL_IPV4_BYTE})).0"
	local LOCAL_IPV4_MASK="24"
	local LOCAL_IPV4_ADDR="$(get_nth_ipv4 "${LOCAL_IPV4_NET}/${LOCAL_IPV4_MASK}" 1)"

	# Choose a local 64-bit IPv6 subnet from the fd00::/8 block based on bytes 1-8 of the public key
	local LOCAL_IPV6_BYTES="$(echo "${LOCAL_PUBLIC_KEY}" | base64 -d | dd bs=1 count=7 skip=1 status=none | xxd -p)"
	local LOCAL_IPV6_NET="fd${LOCAL_IPV6_BYTES:0:2}:${LOCAL_IPV6_BYTES:2:4}:${LOCAL_IPV6_BYTES:6:4}:${LOCAL_IPV6_BYTES:10:4}::"
	local LOCAL_IPV6_MASK="$((128 - (32 - LOCAL_IPV4_MASK)))" # Make IPv4 and IPv6 subnets equally sized
	local LOCAL_IPV6_ADDR="${LOCAL_IPV6_NET}$(printf '%x' 1)"

	# Choose a local port from the registered/user ports, skip the ports that are already in use
	local LOCAL_PORTS_IN_USE="$(netstat -ln --udp | tr -s ' ' | cut -d' ' -f4 | rev | cut -d':' -f1 | rev | tail +3 | sort -u)"
	local LOCAL_PORT_IN_USE
	local LOCAL_PORT
	while true; do
		LOCAL_PORT="$(shuf -i 1024-49151 -n 1)"
		for LOCAL_PORT_IN_USE in "${LOCAL_PORTS_IN_USE[@]}"; do
			if [ "${LOCAL_PORT_IN_USE}" -eq "${LOCAL_PORT}" ]; then
				continue 2
			fi
		done
		break
	done

	# Obtain a local public IPv4 via the ipify API, or get the address of the interface used for internet access
	local LOCAL_ADDR="$(curl -s https://api.ipify.org)"
	if [ $? -ne 0 ]; then
		LOCAL_ADDR="$(ip route get "1.1.1.1" | head -1 | awk '{print $7}')"
	fi

	# Obtain IPv4 and IPv6 default route interfaces
	local LOCAL_IPV4_IFACE="${ip route get "1.1.1.1" | head -1 | awk '{print $5}'}"
	if [ -z "${LOCAL_IPV4_IFACE}" ] || [ -n "$(ifconfig "${LOCAL_IPV4_IFACE}" | grep 'not found')" ]; then
		LOCAL_IPV4_IFACE="eth0"
	fi
	local LOCAL_IPV6_IFACE="${ip route get "2606:4700:4700::1111" | head -1 | awk '{print $5}'}"
	if [ -z "${LOCAL_IPV6_IFACE}" ] || [ -n "$(ifconfig "${LOCAL_IPV6_IFACE}" | grep 'not found')" ]; then
		LOCAL_IPV6_IFACE="${LOCAL_IPV4_IFACE}"
	fi
	fi

	# Refer to the following documents for the recommended values:
	# https://docs.amnezia.org/documentation/amnezia-wg/
	# https://github.com/amnezia-vpn/amneziawg-go/blob/v0.2.16/README.md
	# https://github.com/amnezia-vpn/amneziawg-linux-kernel-module/blob/v1.0.20251104/README.md

	# Jc, Jmin, Jmax
	# 0 ≤ Jc ≤ 128; recommended range is [4;12]
	# Jmin < Jmax ≤ 1280; recommended values are 8 and 80
	# Values 0,*,* ensure compliance with vanilla WireGuard implementations
	local JUNK_PACKET_COUNT="$(shuf -i 4-12 -n 1)"
	local JUNK_PACKET_MIN_SIZE="8"
	local JUNK_PACKET_MAX_SIZE="80"

	# S1, S2, S3, S4
	# 0 ≤ S1 ≤ 1132 (1280 - 148 = 1132); recommended range is [15; 150]
	# 0 ≤ S2 ≤ 1188 (1280 -  92 = 1188); recommended range is [15; 150]
	# 0 ≤ S3 ≤ 1216 (1280 -  64 = 1216); recommended range is [15; 150]
	# S2 + (148 - 92) ≠ S1; S3 + (92 - 64) ≠ S2; S3 + (148 - 64) ≠ S1
	# Values 0,0,0,0 ensure compliance with vanilla WireGuard implementations
	local JUNK_SIZES=()
	local JUNK_SIZE
	while [ "${#JUNK_SIZES[@]}" -lt 3 ]; do
		JUNK_SIZE="$(shuf -i 15-150 -n 1)"
		if [ "${#JUNK_SIZES[@]}" -eq 1 ]; then
			if [ "$(( JUNK_SIZE + 56 ))" -eq "${JUNK_SIZES[0]}" ]; then
				continue
			fi
		elif [ "${#JUNK_SIZES[@]}" -eq 2 ]; then
			if [ "$(( JUNK_SIZE + 28 ))" -eq "${JUNK_SIZES[1]}" ]; then
				continue
			fi
			if [ "$(( JUNK_SIZE + 84 ))" -eq "${JUNK_SIZES[0]}" ]; then
				continue
			fi
		fi
		JUNK_SIZES+=("${JUNK_SIZE}")
	done
	local INIT_PACKET_JUNK_SIZE="${JUNK_SIZES[0]}" 
	local RESPONSE_PACKET_JUNK_SIZE="${JUNK_SIZES[1]}"
	local COOKIE_REPLY_PACKET_JUNK_SIZE="${JUNK_SIZES[2]}"
	local TRANSPORT_PACKET_JUNK_SIZE="0"
	
	# H1, H2, H3, H4
	# Must be a set of 4 unique numbers; recommended range is [5; 2147483647]
	# Values 1,2,3,4 ensure compliance with vanilla WireGuard implementations
	local MAGIC_HEADERS=()
	local MAGIC_HEADER
	local UINT32
	while [ "${#MAGIC_HEADERS[@]}" -lt 4 ]; do
		UINT32="$(openssl rand 4 | od -vAn -tu4 -vAn | tr -d ' ')"
		if [ "${UINT32}" -lt 5 ] || [ "${UINT32}" -gt 2147483647 ]; then
			continue
		fi
		for MAGIC_HEADER in ${MAGIC_HEADERS[@]}; do
			if [ "${UINT32}" -eq "${MAGIC_HEADER}" ]; then
				continue 2
			fi
		done
		MAGIC_HEADERS+=("${UINT32}")
	done
	local INIT_PACKET_MAGIC_HEADER="${MAGIC_HEADERS[0]}"
	local RESPONSE_PACKET_MAGIC_HEADER="${MAGIC_HEADERS[1]}"
	local UNDERLOAD_PACKET_MAGIC_HEADER="${MAGIC_HEADERS[2]}"
	local TRANSPORT_PACKET_MAGIC_HEADER="${MAGIC_HEADERS[3]}"

	# Ref: https://github.com/amnezia-vpn/amnezia-client/blob/4.8.12.6/client/server_scripts/awg/configure_container.sh
	cat <<-EOF > "./${IFACE}.conf"
	[Interface]
	PrivateKey = ${LOCAL_PRIVATE_KEY}
	Address = ${LOCAL_IPV4_ADDR}/${LOCAL_IPV4_MASK}, ${LOCAL_IPV6_ADDR}/${LOCAL_IPV6_MASK}
	ListenPort = ${LOCAL_PORT}
	Jc = ${JUNK_PACKET_COUNT}
	Jmin = ${JUNK_PACKET_MIN_SIZE}
	Jmax = ${JUNK_PACKET_MAX_SIZE}
	S1 = ${INIT_PACKET_JUNK_SIZE}
	S2 = ${RESPONSE_PACKET_JUNK_SIZE}
	S3 = ${COOKIE_REPLY_PACKET_JUNK_SIZE}
	S4 = ${TRANSPORT_PACKET_JUNK_SIZE}
	H1 = ${INIT_PACKET_MAGIC_HEADER}
	H2 = ${RESPONSE_PACKET_MAGIC_HEADER}
	H3 = ${UNDERLOAD_PACKET_MAGIC_HEADER}
	H4 = ${TRANSPORT_PACKET_MAGIC_HEADER}
	EOF

	# Ref: https://github.com/amnezia-vpn/amnezia-client/blob/4.8.12.6/client/server_scripts/awg/template.conf
	cat <<-EOF > "./${IFACE}/remote.conf.template"
	[Interface]
	Address = {REMOTE_IPV4_ADDR}/32, {REMOTE_IPV6_ADDR}/128
	DNS = {PRIMARY_DNS}, {SECONDARY_DNS}
	PrivateKey = {REMOTE_PRIVATE_KEY}
	Jc = ${JUNK_PACKET_COUNT}
	Jmin = ${JUNK_PACKET_MIN_SIZE}
	Jmax = ${JUNK_PACKET_MAX_SIZE}
	S1 = ${INIT_PACKET_JUNK_SIZE}
	S2 = ${RESPONSE_PACKET_JUNK_SIZE}
	S3 = ${COOKIE_REPLY_PACKET_JUNK_SIZE}
	S4 = ${TRANSPORT_PACKET_JUNK_SIZE}
	H1 = ${INIT_PACKET_MAGIC_HEADER}
	H2 = ${RESPONSE_PACKET_MAGIC_HEADER}
	H3 = ${UNDERLOAD_PACKET_MAGIC_HEADER}
	H4 = ${TRANSPORT_PACKET_MAGIC_HEADER}
	# I1 = {SPECIAL_JUNK_1}
	# I2 = {SPECIAL_JUNK_2}
	# I3 = {SPECIAL_JUNK_3}
	# I4 = {SPECIAL_JUNK_4}
	# I5 = {SPECIAL_JUNK_5}

	[Peer]
	PublicKey = ${LOCAL_PUBLIC_KEY}
	PresharedKey = {REMOTE_PRESHARED_KEY}
	AllowedIPs = 0.0.0.0/0, ::/0
	Endpoint = ${LOCAL_ADDR}:${LOCAL_PORT}
	PersistentKeepalive = 25
	EOF

	cat <<-EOF > "./${IFACE}/peer.conf.template"
	# {REMOTE_NAME}
	[Peer]
	PublicKey = {REMOTE_PUBLIC_KEY}
	PresharedKey = {REMOTE_PRESHARED_KEY}
	AllowedIPs = {REMOTE_IPV4_ADDR}/32, {REMOTE_IPV6_ADDR}/128
	PersistentKeepalive = 25
	EOF
}

peer() {
	local IFACE="$1"
	local REMOTE_NAME="$2"

	local REMOTE_PRIVATE_KEY="$(awg genkey)"
	# echo "${REMOTE_PRIVATE_KEY}" > "./${IFACE}/remote_private.key"

	local REMOTE_PUBLIC_KEY="$(echo "${REMOTE_PRIVATE_KEY}" | awg pubkey)"
	# echo "${REMOTE_PUBLIC_KEY}" > "./${IFACE}/remote_public.key"

	local REMOTE_PRESHARED_KEY="$(awg genpsk)"
	# echo "${REMOTE_PRESHARED_KEY}" > "./${IFACE}/remote_preshared.key"

	cat "./${IFACE}/remote.conf.template" \
	| sed "s/{REMOTE_PRIVATE_KEY}/${REMOTE_PRIVATE_KEY}/g" \
	| sed "s/{REMOTE_PRESHARED_KEY}/${REMOTE_PRESHARED_KEY}/g" \
	> "./${IFACE}/${REMOTE_NAME}.conf"

	cat "./${IFACE}/peer.conf.template" \
	| sed "s/{REMOTE_NAME}/${REMOTE_NAME}/g" \
	| sed "s/{REMOTE_PUBLIC_KEY}/${REMOTE_PUBLIC_KEY}/g" \
	| sed "s/{REMOTE_PRESHARED_KEY}/${REMOTE_PRESHARED_KEY}/g" \
	>> ".{IFACE}.conf"
}

if [ "$1" == "new" ]; then
	new "$2"
elif [ "$1" == "peer" ]; then
	peer "$2" "$3"
fi
