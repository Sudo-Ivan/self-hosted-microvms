# Argus central firewall for microVM guests.
# Source after lib/common.sh and lib/network.sh.
# Requires root and nftables.
# Argus is the all-seeing guardian of guest traffic (Greek Argos Panoptes).

ARGUS_DIR="${REPO_ROOT}/argus"
ARGUS_POLICY_FILE="${ARGUS_POLICY_FILE:-${ARGUS_DIR}/policy.env}"
ARGUS_NFT_TABLE="${ARGUS_NFT_TABLE:-argus}"

# shellcheck source=dns.sh
. "${ARGUS_DIR}/dns.sh"

argus_require_root() {
	[ "$(id -u)" -eq 0 ] || die "argus needs root (run with sudo or as root)"
}

argus_require_nft() {
	require_cmd nft
}

argus_load_global_policy() {
	ARGUS_ENABLED="${ARGUS_ENABLED:-1}"
	ARGUS_DEFAULT_EGRESS="${ARGUS_DEFAULT_EGRESS:-allow}"
	ARGUS_INTER_VM="${ARGUS_INTER_VM:-deny}"
	ARGUS_LOG_DROPS="${ARGUS_LOG_DROPS:-1}"
	# Permit guests to query external resolvers directly (usually off when DNS force is on)
	ARGUS_ALLOW_DNS_EGRESS="${ARGUS_ALLOW_DNS_EGRESS:-0}"
	ARGUS_ALLOW_GATEWAY="${ARGUS_ALLOW_GATEWAY:-1}"

	if [ -f "${ARGUS_POLICY_FILE}" ]; then
		# shellcheck disable=SC1090
		set -a
		# shellcheck disable=SC1091
		. "${ARGUS_POLICY_FILE}"
		set +a
	fi

	# Compatibility with older Odin policy keys if someone still has them.
	ARGUS_ENABLED="${ARGUS_ENABLED:-${ODIN_ENABLED:-1}}"
	ARGUS_DEFAULT_EGRESS="${ARGUS_DEFAULT_EGRESS:-${ODIN_DEFAULT_EGRESS:-allow}}"
	ARGUS_INTER_VM="${ARGUS_INTER_VM:-${ODIN_INTER_VM:-deny}}"
	ARGUS_LOG_DROPS="${ARGUS_LOG_DROPS:-${ODIN_LOG_DROPS:-1}}"
	ARGUS_ALLOW_GATEWAY="${ARGUS_ALLOW_GATEWAY:-${ODIN_ALLOW_GATEWAY:-1}}"

	argus_dns_defaults

	case "${ARGUS_DEFAULT_EGRESS}" in
	allow|deny) ;;
	*) die "ARGUS_DEFAULT_EGRESS must be allow or deny" ;;
	esac
	case "${ARGUS_INTER_VM}" in
	allow|deny) ;;
	*) die "ARGUS_INTER_VM must be allow or deny" ;;
	esac
}

argus_load_instance_firewall() {
	name="$1"
	dir=
	fw=
	dir="$(instance_dir "${name}")"
	fw="${dir}/firewall.env"

	EGRESS_ALLOW=""
	EGRESS_DENY=""
	ALLOW_PEERS=""
	INGRESS_EXTRA=""

	if [ -f "${fw}" ]; then
		# shellcheck disable=SC1090
		set -a
		# shellcheck disable=SC1091
		. "${fw}"
		set +a
	fi
}

argus_ip_for_name() {
	name="$1"
	dir=
	conf=
	dir="$(instance_dir "${name}")"
	conf="${dir}/config.env"
	[ -f "${conf}" ] || return 1
	# shellcheck disable=SC1090
	set -a
	# shellcheck disable=SC1091
	. "${conf}"
	set +a
	printf '%s\n' "${GUEST_IP:-}"
}

argus_foreach_instance() {
	dir=
	name=
	for dir in "${INSTANCES_DIR}"/*/; do
		name="$(basename "${dir}")"
		[ -f "${dir}/config.env" ] || continue
		# shellcheck disable=SC1090
		set -a
		# shellcheck disable=SC1091
		. "${dir}/config.env"
		set +a
		# Use tabs so empty TAP_DEV does not shift fields.
		printf '%s\t%s\t%s\t%s\n' \
			"${name}" \
			"${GUEST_IP:-}" \
			"${TAP_DEV:-}" \
			"${PORT_FORWARDS:-}"
	done
}

argus_parse_portspec() {
	_aps_spec="$1"
	case "${_aps_spec}" in
	tcp/*|udp/*)
		P_PROTO="${_aps_spec%%/*}"
		P_PORT="${_aps_spec#*/}"
		;;
	*)
		die "bad port spec '${_aps_spec}' (want proto/port like tcp/443)"
		;;
	esac
	if [ "${P_PORT}" != "all" ]; then
		case "${P_PORT}" in
		*[!0-9]*|'')
			die "bad port in '${_aps_spec}'"
			;;
		esac
	fi
}

argus_csv_foreach() {
	# $1=csv $2=callback name (unused, inline in caller)
	:
}

argus_join_file() {
	# Print comma-separated elements from one value per line file.
	_ajf="$1"
	if [ ! -s "${_ajf}" ]; then
		return 0
	fi
	awk 'NR>1{printf ", "} {printf "%s", $0}' "${_ajf}"
}

argus_collect_state() {
	ARGUS_GUESTS_FILE=$(mktemp)
	ARGUS_EGRESS_FILE=$(mktemp)
	ARGUS_EGRESS_DENY_FILE=$(mktemp)
	ARGUS_PEER_FILE=$(mktemp)
	ARGUS_INGRESS_FILE=$(mktemp)
	ARGUS_DNAT_FILE=$(mktemp)
	: >"${ARGUS_GUESTS_FILE}"
	: >"${ARGUS_EGRESS_FILE}"
	: >"${ARGUS_EGRESS_DENY_FILE}"
	: >"${ARGUS_PEER_FILE}"
	: >"${ARGUS_INGRESS_FILE}"
	: >"${ARGUS_DNAT_FILE}"

	_ac_name=
	_ac_ip=
	_ac_tap=
	_ac_ports=
	_ac_entry=
	_ac_peer=
	_ac_peer_ip=
	_ac_old_ifs=
	_ac_egress_allow=
	_ac_egress_deny=
	_ac_allow_peers=
	_ac_ingress_extra=

	argus_foreach_instance | while IFS='	' read -r _ac_name _ac_ip _ac_tap _ac_ports; do
		[ -n "${_ac_name}" ] && [ -n "${_ac_ip}" ] || continue
		printf '%s\n' "${_ac_ip}" >>"${ARGUS_GUESTS_FILE}"

		argus_load_instance_firewall "${_ac_name}"
		_ac_egress_allow="${EGRESS_ALLOW:-}"
		_ac_egress_deny="${EGRESS_DENY:-}"
		_ac_allow_peers="${ALLOW_PEERS:-}"
		_ac_ingress_extra="${INGRESS_EXTRA:-}"

		if [ "${ARGUS_ALLOW_DNS_EGRESS}" = "1" ]; then
			if [ -n "${_ac_egress_allow}" ]; then
				_ac_egress_allow="${_ac_egress_allow},udp/53,tcp/53"
			else
				_ac_egress_allow="udp/53,tcp/53"
			fi
		fi

		_ac_old_ifs=${IFS}
		IFS=,
		for _ac_entry in ${_ac_egress_allow}; do
			IFS=${_ac_old_ifs}
			_ac_entry="$(echo "${_ac_entry}" | tr -d '[:space:]')"
			[ -n "${_ac_entry}" ] || continue
			argus_parse_portspec "${_ac_entry}"
			if [ "${P_PORT}" = "all" ]; then
				printf '%s\n' "${_ac_ip} . ${P_PROTO} . 1-65535" >>"${ARGUS_EGRESS_FILE}"
			else
				printf '%s\n' "${_ac_ip} . ${P_PROTO} . ${P_PORT}" >>"${ARGUS_EGRESS_FILE}"
			fi
			IFS=,
		done
		IFS=${_ac_old_ifs}

		_ac_old_ifs=${IFS}
		IFS=,
		for _ac_entry in ${_ac_egress_deny}; do
			IFS=${_ac_old_ifs}
			_ac_entry="$(echo "${_ac_entry}" | tr -d '[:space:]')"
			[ -n "${_ac_entry}" ] || continue
			argus_parse_portspec "${_ac_entry}"
			[ "${P_PORT}" != "all" ] || die "EGRESS_DENY does not support all"
			printf '%s\n' "${_ac_ip} . ${P_PROTO} . ${P_PORT}" >>"${ARGUS_EGRESS_DENY_FILE}"
			IFS=,
		done
		IFS=${_ac_old_ifs}

		_ac_old_ifs=${IFS}
		IFS=,
		for _ac_peer in ${_ac_allow_peers}; do
			IFS=${_ac_old_ifs}
			_ac_peer="$(echo "${_ac_peer}" | tr -d '[:space:]')"
			[ -n "${_ac_peer}" ] || continue
			case "${_ac_peer}" in
			*.*.*.*)
				_ac_peer_ip="${_ac_peer}"
				;;
			*)
				_ac_peer_ip="$(argus_ip_for_name "${_ac_peer}" || true)"
				[ -n "${_ac_peer_ip}" ] || die "ALLOW_PEERS unknown instance: ${_ac_peer}"
				;;
			esac
			printf '%s\n' "${_ac_ip} . ${_ac_peer_ip}" >>"${ARGUS_PEER_FILE}"
			IFS=,
		done
		IFS=${_ac_old_ifs}

		if [ -n "${_ac_ports}" ]; then
			_ac_old_ifs=${IFS}
			IFS=,
			for _ac_entry in ${_ac_ports}; do
				IFS=${_ac_old_ifs}
				_ac_entry="$(echo "${_ac_entry}" | tr -d '[:space:]')"
				[ -n "${_ac_entry}" ] || continue
				parse_forward "${_ac_entry}"
				# parse_forward sets PROTO HOST_PORT GUEST_PORT
				# shellcheck disable=SC2153
				printf '%s\n' "${_ac_ip} . ${PROTO} . ${GUEST_PORT}" >>"${ARGUS_INGRESS_FILE}"
				# shellcheck disable=SC2153
				printf '%s %s %s %s\n' "${PROTO}" "${HOST_PORT}" "${_ac_ip}" "${GUEST_PORT}" >>"${ARGUS_DNAT_FILE}"
				IFS=,
			done
			IFS=${_ac_old_ifs}
		fi

		_ac_old_ifs=${IFS}
		IFS=,
		for _ac_entry in ${_ac_ingress_extra}; do
			IFS=${_ac_old_ifs}
			_ac_entry="$(echo "${_ac_entry}" | tr -d '[:space:]')"
			[ -n "${_ac_entry}" ] || continue
			argus_parse_portspec "${_ac_entry}"
			[ "${P_PORT}" != "all" ] || die "INGRESS_EXTRA does not support all"
			printf '%s\n' "${_ac_ip} . ${P_PROTO} . ${P_PORT}" >>"${ARGUS_INGRESS_FILE}"
			IFS=,
		done
		IFS=${_ac_old_ifs}
	done
}

argus_render_nft() {
	guests_elems=
	egress_elems=
	deny_elems=
	peer_elems=
	ingress_elems=
	outif=
	log_drop_inter=
	log_drop_egress=
	log_drop_other=
	subnet="${SUBNET_PREFIX}.0/${GUEST_PREFIX}"
	proto=
	host_port=
	guest_ip=
	guest_port=
	rule=

	outif="$(ip route show default | awk '{print $5; exit}')"
	[ -n "${outif}" ] || die "no default route found"

	guests_elems="$(argus_join_file "${ARGUS_GUESTS_FILE}")"
	egress_elems="$(argus_join_file "${ARGUS_EGRESS_FILE}")"
	deny_elems="$(argus_join_file "${ARGUS_EGRESS_DENY_FILE}")"
	peer_elems="$(argus_join_file "${ARGUS_PEER_FILE}")"
	ingress_elems="$(argus_join_file "${ARGUS_INGRESS_FILE}")"

	if [ "${ARGUS_LOG_DROPS}" = "1" ]; then
		log_drop_inter='log prefix "argus-drop-intervm "'
		log_drop_egress='log prefix "argus-drop-egress "'
		log_drop_other='log prefix "argus-drop "'
	else
		log_drop_inter=""
		log_drop_egress=""
		log_drop_other=""
	fi

	cat <<EOF
table inet ${ARGUS_NFT_TABLE} {
	comment "microvm central firewall (Argus)"

	set guests {
		type ipv4_addr
		comment "known guest addresses"
EOF
	if [ -n "${guests_elems}" ]; then
		echo "		elements = { ${guests_elems} }"
	fi
	cat <<EOF
	}

	set egress_allow {
		type ipv4_addr . inet_proto . inet_service
		flags interval
		comment "guest ip . proto . dport allow"
EOF
	if [ -n "${egress_elems}" ]; then
		echo "		elements = { ${egress_elems} }"
	fi
	cat <<EOF
	}

	set egress_deny {
		type ipv4_addr . inet_proto . inet_service
		flags interval
		comment "guest ip . proto . dport deny"
EOF
	if [ -n "${deny_elems}" ]; then
		echo "		elements = { ${deny_elems} }"
	fi
	cat <<EOF
	}

	set peer_allow {
		type ipv4_addr . ipv4_addr
		comment "src guest . dst guest"
EOF
	if [ -n "${peer_elems}" ]; then
		echo "		elements = { ${peer_elems} }"
	fi
	cat <<EOF
	}

	set ingress_allow {
		type ipv4_addr . inet_proto . inet_service
		flags interval
		comment "guest ip . proto . dport published"
EOF
	if [ -n "${ingress_elems}" ]; then
		echo "		elements = { ${ingress_elems} }"
	fi
	cat <<EOF
	}

	chain forward {
		type filter hook forward priority filter; policy drop;

		ct state invalid drop
		ct state established,related accept
EOF

	if [ "${ARGUS_ALLOW_GATEWAY}" = "1" ]; then
		cat <<EOF
		iifname "${BRIDGE_NAME}" ip daddr ${GATEWAY_IP} accept
EOF
	fi

	cat <<EOF
		iifname "${BRIDGE_NAME}" oifname "${BRIDGE_NAME}" ip saddr @guests ip daddr @guests ip saddr . ip daddr @peer_allow accept
EOF
	if [ "${ARGUS_INTER_VM}" = "allow" ]; then
		cat <<EOF
		iifname "${BRIDGE_NAME}" oifname "${BRIDGE_NAME}" ip saddr @guests ip daddr @guests accept
EOF
	else
		cat <<EOF
		iifname "${BRIDGE_NAME}" oifname "${BRIDGE_NAME}" ip saddr @guests ip daddr @guests ${log_drop_inter} drop
EOF
	fi

	cat <<EOF
		iifname "${BRIDGE_NAME}" oifname != "${BRIDGE_NAME}" ip saddr . meta l4proto . th dport @egress_deny ${log_drop_egress} drop
		iifname "${BRIDGE_NAME}" oifname != "${BRIDGE_NAME}" ip saddr . meta l4proto . th dport @egress_allow accept
EOF

	if [ "${ARGUS_DEFAULT_EGRESS}" = "allow" ]; then
		cat <<EOF
		iifname "${BRIDGE_NAME}" oifname != "${BRIDGE_NAME}" ip saddr @guests accept
EOF
	else
		cat <<EOF
		iifname "${BRIDGE_NAME}" oifname != "${BRIDGE_NAME}" ip saddr @guests ${log_drop_egress} drop
EOF
	fi

	cat <<EOF
		oifname "${BRIDGE_NAME}" ip daddr . meta l4proto . th dport @ingress_allow accept
		${log_drop_other} drop
	}

	chain input {
		type filter hook input priority filter; policy accept;
		iifname "${BRIDGE_NAME}" ip saddr @guests meta l4proto { tcp, udp } th dport ${ARGUS_DNS_PORT:-53} accept
	}

	chain postrouting {
		type nat hook postrouting priority srcnat; policy accept;
		ip saddr ${subnet} oifname "${outif}" masquerade
	}

	chain prerouting {
		type nat hook prerouting priority dstnat; policy accept;
EOF

	if [ "${ARGUS_DNS_ENABLED}" = "1" ] && [ "${ARGUS_DNS_FORCE}" = "1" ]; then
		cat <<EOF
		iifname "${BRIDGE_NAME}" ip saddr @guests meta l4proto { tcp, udp } th dport 53 dnat ip to ${GATEWAY_IP}:${ARGUS_DNS_PORT:-53}
EOF
	fi

	while read -r rule; do
		[ -n "${rule}" ] || continue
		set -- ${rule}
		proto=$1
		host_port=$2
		guest_ip=$3
		guest_port=$4
		cat <<EOF
		meta l4proto ${proto} th dport ${host_port} dnat ip to ${guest_ip}:${guest_port}
EOF
	done <"${ARGUS_DNAT_FILE}"

	cat <<EOF
	}

	chain output {
		type nat hook output priority dstnat; policy accept;
EOF

	while read -r rule; do
		[ -n "${rule}" ] || continue
		set -- ${rule}
		proto=$1
		host_port=$2
		guest_ip=$3
		guest_port=$4
		cat <<EOF
		meta l4proto ${proto} th dport ${host_port} dnat ip to ${guest_ip}:${guest_port}
EOF
	done <"${ARGUS_DNAT_FILE}"

	cat <<EOF
	}
}
EOF
}

argus_apply() {
	_aa_guest_count=
	argus_require_root
	argus_require_nft
	argus_load_global_policy

	if [ "${ARGUS_ENABLED}" != "1" ]; then
		echo "argus disabled (ARGUS_ENABLED=${ARGUS_ENABLED})"
		return 0
	fi

	setup_bridge
	echo 1 >/proc/sys/net/ipv4/ip_forward 2>/dev/null || true

	if [ "${ARGUS_DNS_ENABLED}" = "1" ]; then
		argus_dns_apply
	else
		argus_dns_stop
	fi

	argus_collect_state
	rules="$(argus_render_nft)"
	_aa_guest_count="$(wc -l <"${ARGUS_GUESTS_FILE}" | tr -d ' ')"

	nft delete table inet "${ARGUS_NFT_TABLE}" 2>/dev/null || true
	# Remove legacy Odin table if present.
	nft delete table inet odin 2>/dev/null || true
	printf '%s\n' "${rules}" | nft -f -

	mkdir -p "${SHARED_DIR}"
	printf '%s\n' "${rules}" >"${SHARED_DIR}/argus.nft"
	echo "argus policy applied (${_aa_guest_count} guests, egress=${ARGUS_DEFAULT_EGRESS}, inter_vm=${ARGUS_INTER_VM}, dns=${ARGUS_DNS_ENABLED})"

	rm -f "${ARGUS_GUESTS_FILE}" "${ARGUS_EGRESS_FILE}" "${ARGUS_EGRESS_DENY_FILE}" \
		"${ARGUS_PEER_FILE}" "${ARGUS_INGRESS_FILE}" "${ARGUS_DNAT_FILE}"
}

argus_flush() {
	argus_require_root
	argus_require_nft
	argus_load_global_policy
	argus_dns_stop
	nft list table inet "${ARGUS_NFT_TABLE}" >/dev/null 2>&1 || {
		nft delete table inet odin 2>/dev/null || true
		echo "argus table not present"
		return 0
	}
	nft delete table inet "${ARGUS_NFT_TABLE}"
	nft delete table inet odin 2>/dev/null || true
	rm -f "${SHARED_DIR}/argus.nft" "${SHARED_DIR}/odin.nft"
	echo "argus table removed"
}

argus_name_for_ip() {
	_an_want="$1"
	_an_name=
	_an_ip=
	_an_tap=
	_an_ports=
	argus_foreach_instance | while IFS='	' read -r _an_name _an_ip _an_tap _an_ports; do
		if [ "${_an_ip}" = "${_an_want}" ]; then
			printf '%s\n' "${_an_name}"
			exit 0
		fi
	done
	printf '%s\n' "${_an_want}"
}
