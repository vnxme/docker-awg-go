#!/bin/bash

# Supported environment variables:
#
# Firewall & Forwarding
# FORWARDING   - [true/ipv4/ipv6/false]      - enables/disables IPv4/IPv6 forwarding
# MASQUERADE   - [true/...]                  - enables masquerade on the default interface
# PRIVATE_IPV4 - [semicolon separated CIDRs] - IPv4 ranges to masquerade outgoing traffic from
# PRIVATE_IPV6 - [semicolon separated CIDRs] - IPv6 ranges to masquerade outgoing traffic from
#
# VARIABLE   # DESCRIPTION                                 # DEFAULT VALUE          #
# ---------- # ------------------------------------------- # ---------------------- #
# CONFS_DEF  # the default interface name                  # wg0                    #
# CONFS_DIR  # the configuration directory                 # /etc/amnezia/amneziawg #
# CONFS_LIST # the comma-separated list of interface names # ${CONFS_DEF}           #
# HOOKS_DIR  # the pre/post-up/down hook scripts directory # ./hooks                #
#
# Note: if ${CONFS_DIR} exists and no non-empty configuration files are found in it
# according to ${CONFS_LIST}, the script runs the daemon with each non-empty *.conf
# file. The script creates a new configuration if there are no *.conf files at all.

CONFS_DEF="${CONFS_DEF:-wg0}"
CONFS_DIR="${CONFS_DIR:-/etc/amnezia/amneziawg}"
CONFS_LIST="${CONFS_LIST:-${CONFS_DEF}}"
HOOKS_DIR="${HOOKS_DIR:-./hooks}"

PIDS=()
FILES=()

firewall_up() {
	local M="${MASQUERADE,,:-}"

	if [ -n "$(which iptables)" ] && [ $(iptables -t filter -L 2>/dev/null 1>&2; echo $?) -eq 0 ]; then
		IPT4='iptables'
	elif [ -n "$(which iptables-legacy)" ] && [ $(iptables-legacy -t filter -L 2>/dev/null 1>&2; echo $?) -eq 0 ]; then
		IPT4='iptables-legacy'
	fi

	if [ -n "${IPT4}" ]; then
		FIREWALL_IPV4_FILTER="$(${IPT4}-save -t filter || true)"
		FIREWALL_IPV4_MANGLE="$(${IPT4}-save -t mangle || true)"
		FIREWALL_IPV4_NAT="$(${IPT4}-save -t nat || true)"

		${IPT4} -t filter -F || true
		${IPT4} -t mangle -F || true
		${IPT4} -t nat -F || true

		if [ "${M}" == "true" ]; then
			local IFACE="$(ip route | grep default | awk '{print $5}')"
			if [ -n "${IFACE}" ]; then
				if [ -n "${PRIVATE_IPV4:-}" ]; then
					local RANGES; IFS=';' read -r -a RANGES <<< "${PRIVATE_IPV4}"
					local RANGE; for RANGE in "${RANGES[@]}"; do
						${IPT4} -t nat -A POSTROUTING -s ${RANGE} -o ${IFACE} -j MASQUERADE || true
					done
				else
					${IPT4} -t nat -A POSTROUTING -o ${IFACE} -j MASQUERADE || true
				fi
			fi
		fi
	fi

	if [ -n "$(which ip6tables)" ] && [ $(ip6tables -t filter -L 2>/dev/null 1>&2; echo $?) -eq 0 ]; then
		IPT6='ip6tables'
	elif [ -n "$(which ip6tables-legacy)" ] && [ $(ip6tables-legacy -t filter -L 2>/dev/null 1>&2; echo $?) -eq 0 ]; then
		IPT6='ip6tables-legacy'
	fi

	if [ -n "${IPT6}" ]; then
		FIREWALL_IPV6_FILTER="$(${IPT6}-save -t filter || true)"
		FIREWALL_IPV6_MANGLE="$(${IPT6}-save -t mangle || true)"
		FIREWALL_IPV6_NAT="$(${IPT6}-save -t nat || true)"

		${IPT6} -t filter -F || true
		${IPT6} -t mangle -F || true
		${IPT6} -t nat -F || true

		if [ "${M}" == "true" ]; then
			local IFACE="$(ip -6 route | grep default | awk '{print $5}')"
			if [ -n "${IFACE}" ]; then
				if [ -n "${PRIVATE_IPV6:-}" ]; then
					local RANGES; IFS=';' read -r -a RANGES <<< "${PRIVATE_IPV6}"
					local RANGE; for RANGE in "${RANGES[@]}"; do
						${IPT6} -t nat -A POSTROUTING -s ${RANGE} -o ${IFACE} -j MASQUERADE || true
					done
				else
					${IPT6} -t nat -A POSTROUTING -o ${IFACE} -j MASQUERADE || true
				fi
			fi
		fi
	fi
}

firewall_down() {
	if [ -n "${IPT4}" ]; then
		echo "${FIREWALL_IPV4_FILTER}" | ${IPT4}-restore || true
		echo "${FIREWALL_IPV4_MANGLE}" | ${IPT4}-restore || true
		echo "${FIREWALL_IPV4_NAT}" | ${IPT4}-restore || true
	fi

	if [ -n "${IPT6}" ]; then
		echo "${FIREWALL_IPV6_FILTER}" | ${IPT6}-restore || true
		echo "${FIREWALL_IPV6_MANGLE}" | ${IPT6}-restore || true
		echo "${FIREWALL_IPV6_NAT}" | ${IPT6}-restore || true
	fi
}

forwarding_up() {
	FORWARDING_IPV4="$(cat /proc/sys/net/ipv4/ip_forward)"
	FORWARDING_IPV6_ALL="$(cat /proc/sys/net/ipv6/conf/all/forwarding)"
	FORWARDING_IPV6_DEF="$(cat /proc/sys/net/ipv6/conf/default/forwarding)"	

	local F="${FORWARDING,,:-}"
	if [ "${F}" == "true" ]; then
		echo 1 > /proc/sys/net/ipv4/ip_forward
		echo 1 > /proc/sys/net/ipv6/conf/all/forwarding
		echo 1 > /proc/sys/net/ipv6/conf/default/forwarding
	elif [ "${F}" == "ipv4" ]; then
		echo 1 > /proc/sys/net/ipv4/ip_forward
		echo 0 > /proc/sys/net/ipv6/conf/all/forwarding
		echo 0 > /proc/sys/net/ipv6/conf/default/forwarding
	elif [ "${F}" == "ipv6" ]; then
		echo 0 > /proc/sys/net/ipv4/ip_forward
		echo 1 > /proc/sys/net/ipv6/conf/all/forwarding
		echo 1 > /proc/sys/net/ipv6/conf/default/forwarding
	elif [ "${F}" == "false" ]; then
		echo 0 > /proc/sys/net/ipv4/ip_forward
		echo 0 > /proc/sys/net/ipv6/conf/all/forwarding
		echo 0 > /proc/sys/net/ipv6/conf/default/forwarding
	fi
}

forwarding_down() {
	echo "${FORWARDING_IPV4}" > /proc/sys/net/ipv4/ip_forward
	echo "${FORWARDING_IPV6_ALL}" > /proc/sys/net/ipv6/conf/all/forwarding
	echo "${FORWARDING_IPV6_DEF}" > /proc/sys/net/ipv6/conf/default/forwarding
}

hooks() {
	[ ! -d "${HOOKS_DIR}/$1" ] && mkdir -p "${HOOKS_DIR}/$1"
	local FILE; for FILE in "${HOOKS_DIR}"/"$1"/*.sh; do
		if [ -s "${FILE}" ]; then
			/bin/bash -- "${FILE}" || true
		fi
	done
}

launch() {
	# Configure firewall and forwarding
	firewall_up
	forwarding_up

	# Call pre-up hooks
	hooks "pre-up"

	# Launch one or multiple tunnels
	if [ -n "$(which awg)" ] && [ -n "$(which awg-quick)" ] && [ -n "$(which amneziawg-go)" ]; then
		local CONFS; IFS=',' read -r -a CONFS <<< "${CONFS_LIST}"
		local CONF; for CONF in "${CONFS[@]}"; do
			local FILE="${CONFS_DIR}/${CONF}.conf"
			if [ -s "${FILE}" ]; then
				awg-quick down "${FILE}" || true
				awg-quick up "${FILE}" || true
				FILES+=("${FILE}")
			fi
		done

		if [ ${#FILES[@]} -eq 0 ] && [ -d "${CONFS_DIR}" ]; then
			if [ -n "$(find "${CONFS_DIR}" -maxdepth 0 -type d -empty)" ]; then
				cd -- "${CONFS_DIR}" && bash -- /app/configure.sh "${CONFS_DEF}" && cd -
			fi

			local FILE; for FILE in "${CONFS_DIR}"/*.conf; do
				if [ -s "${FILE}" ]; then
					awg-quick down "${FILE}" || true
					awg-quick up "${FILE}" || true
					FILES+=("${FILE}")
				fi
			done
		fi
	fi

	# Launch one empty process to keep this script running
	tail -f /dev/null &
	PIDS+=($!)

	# Call post-up hooks
	hooks "post-up"
}

terminate() {
	# Call pre-down hooks
	hooks "pre-down"

	# Terminate all tunnels
	local FILE; for FILE in "${FILES[@]}"; do
		awg-quick down "${FILE}" || true
	done

	# Terminate all subprocesses
	local PID; for PID in "${PIDS[@]}"; do
		kill "${PID}" 2>/dev/null || true
	done

	# Call post-down hooks
	hooks "post-down"

	# Restore firewall and forwarding
	forwarding_down
	firewall_down

	exit 0
}

# Call terminate() when SIGTERM is received
trap terminate TERM

# Call launch() with command line arguments
launch $@

# Wait for all subprocesses to exit
FAIL=0
for PID in "${PIDS[@]}"; do
	if ! wait "${PID}"; then
		FAIL=1
	fi
done
exit ${FAIL}
