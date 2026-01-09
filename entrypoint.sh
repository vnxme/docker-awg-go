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

# Supported environment variables:
#
# VARIABLE # DESCRIPTION                                        # DEFAULT VALUE          #
# -------- # -------------------------------------------------- # ---------------------- #
# CONF_DEF # the default interface name to create and/or run    # wg0                    #
# CONF_DIR # the configuration directory                        # /etc/amnezia/amneziawg #
# CONF_RUN # the comma-separated list of interface names to run # ${CONF_DEF}            #
# HOOK_DIR # the pre/post-up/down hook scripts directory        # ./hooks                #
#
# Note: if ${CONF_DIR} exists and no non-empty configuration files are found in it
# according to ${CONF_RUN}, the script runs the daemon with each non-empty *.conf
# file. The script creates a new configuration if there are no *.conf files at all.

CONF_DEF="${CONF_DEF:-wg0}"
CONF_DIR="${CONF_DIR:-/etc/amnezia/amneziawg}"
CONF_RUN="${CONF_RUN:-${CONF_DEF}}"
HOOK_DIR="${HOOK_DIR:-./hooks}"

PIDS=()
FILES=()

hooks() {
	[ ! -d "${HOOK_DIR}/$1" ] && mkdir -p "${HOOK_DIR}/$1"
	local FILE; for FILE in "${HOOK_DIR}"/"$1"/*.sh; do
		if [ -s "${FILE}" ]; then
			/bin/bash -- "${FILE}" || true
		fi
	done
}

launch() {
	# Display a warning about the arguments
	if [ $# -gt 0 ]; then
		echo "$(basename -- "$0"): Warning: No command line arguments are supported. Ignoring them"
	fi 

	# Apply kernel parameters
	sysctl -q -p /etc/sysctl.d/*.conf /etc/sysctl.conf || true

	# Call pre-up hooks
	hooks "pre-up"

	# Launch one or multiple tunnels
	if [ -n "$(which awg)" ] && [ -n "$(which awg-quick)" ] && [ -n "$(which amneziawg-go)" ]; then
		local CONFS; IFS=',' read -r -a CONFS <<< "${CONF_RUN}"
		local CONF; for CONF in "${CONFS[@]}"; do
			local FILE="${CONF_DIR}/${CONF}.conf"
			if [ -s "${FILE}" ]; then
				awg-quick down "${FILE}" || true
				awg-quick up "${FILE}" || true
				FILES+=("${FILE}")
			fi
		done

		if [ ${#FILES[@]} -eq 0 ] && [ -d "${CONF_DIR}" ]; then
			if [ -n "$(find "${CONF_DIR}" -maxdepth 0 -type d -empty)" ]; then
				cd -- "${CONF_DIR}" && bash -- /app/configure.sh new "${CONF_DEF}" && cd -
			fi

			local FILE; for FILE in "${CONF_DIR}"/*.conf; do
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

	exit 0
}

# Call terminate() when SIGINT or SIGTERM is received
trap terminate INT TERM

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
