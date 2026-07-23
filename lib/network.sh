# Host networking helpers for TAP plus optional port forwards.
# Source after lib/common.sh.
#
# PORT_FORWARDS format: host:guest or host:guest:tcp|udp
# Multiple entries are comma separated.

parse_forward() {
	# Sets HOST_PORT GUEST_PORT PROTO from one entry.
	entry="$1"
	PROTO=tcp
	case "${entry}" in
	*:*:*)
		HOST_PORT="${entry%%:*}"
		rest="${entry#*:}"
		GUEST_PORT="${rest%%:*}"
		PROTO="${rest#*:}"
		;;
	*:*)
		HOST_PORT="${entry%%:*}"
		GUEST_PORT="${entry##*:}"
		;;
	*)
		die "bad PORT_FORWARDS entry: ${entry}"
		;;
	esac
	case "${HOST_PORT}${GUEST_PORT}" in
	*[!0-9]*)
		die "bad PORT_FORWARDS entry: ${entry}"
		;;
	esac
	case "${PROTO}" in
	tcp|udp) ;;
	*) die "bad protocol in PORT_FORWARDS entry: ${entry}" ;;
	esac
}

setup_bridge() {
	br="${BRIDGE_NAME}"
	gw="${GATEWAY_IP}"
	prefix="${GUEST_PREFIX}"

	if [ "$(id -u)" -ne 0 ]; then
		die "network setup needs root (run with sudo or as root)"
	fi

	echo 1 >/proc/sys/net/ipv4/ip_forward 2>/dev/null || true

	if ! ip link show "${br}" >/dev/null 2>&1; then
		ip link add name "${br}" type bridge
	fi

	ip addr flush dev "${br}" 2>/dev/null || true
	ip addr add "${gw}/${prefix}" dev "${br}" 2>/dev/null \
		|| ip addr replace "${gw}/${prefix}" dev "${br}"
	ip link set "${br}" up
}

setup_tap() {
	tap="$1"
	br="${BRIDGE_NAME}"

	if [ "$(id -u)" -ne 0 ]; then
		die "network setup needs root (run with sudo or as root)"
	fi

	setup_bridge

	if ! ip link show "${tap}" >/dev/null 2>&1; then
		ip tuntap add mode tap name "${tap}"
	fi

	ip link set "${tap}" nomaster 2>/dev/null || true
	ip addr flush dev "${tap}" 2>/dev/null || true
	ip link set "${tap}" master "${br}"
	ip link set "${tap}" up
}

teardown_tap() {
	tap="$1"
	if [ "$(id -u)" -ne 0 ]; then
		return 0
	fi
	if ip link show "${tap}" >/dev/null 2>&1; then
		ip link set "${tap}" down 2>/dev/null || true
		ip link delete "${tap}" 2>/dev/null || true
	fi
}

apply_port_forwards() {
	guest_ip="$1"
	forwards="$2"

	[ -n "${forwards}" ] || return 0
	if [ "$(id -u)" -ne 0 ]; then
		die "port forwards need root (run with sudo or as root)"
	fi

	_pf_old_ifs=${IFS}
	IFS=,
	for entry in ${forwards}; do
		IFS=${_pf_old_ifs}
		entry="$(echo "${entry}" | tr -d '[:space:]')"
		[ -n "${entry}" ] || continue
		parse_forward "${entry}"

		iptables -t nat -C PREROUTING -p "${PROTO}" --dport "${HOST_PORT}" \
			-j DNAT --to-destination "${guest_ip}:${GUEST_PORT}" 2>/dev/null \
			|| iptables -t nat -A PREROUTING -p "${PROTO}" --dport "${HOST_PORT}" \
				-j DNAT --to-destination "${guest_ip}:${GUEST_PORT}"

		iptables -t nat -C OUTPUT -p "${PROTO}" --dport "${HOST_PORT}" \
			-j DNAT --to-destination "${guest_ip}:${GUEST_PORT}" 2>/dev/null \
			|| iptables -t nat -A OUTPUT -p "${PROTO}" --dport "${HOST_PORT}" \
				-j DNAT --to-destination "${guest_ip}:${GUEST_PORT}"

		iptables -C FORWARD -p "${PROTO}" -d "${guest_ip}" --dport "${GUEST_PORT}" -j ACCEPT 2>/dev/null \
			|| iptables -A FORWARD -p "${PROTO}" -d "${guest_ip}" --dport "${GUEST_PORT}" -j ACCEPT

		iptables -t nat -C POSTROUTING -p "${PROTO}" -d "${guest_ip}" --dport "${GUEST_PORT}" -j MASQUERADE 2>/dev/null \
			|| iptables -t nat -A POSTROUTING -p "${PROTO}" -d "${guest_ip}" --dport "${GUEST_PORT}" -j MASQUERADE
	done
	IFS=${_pf_old_ifs}
}

remove_port_forwards() {
	guest_ip="$1"
	forwards="$2"

	[ -n "${forwards}" ] || return 0
	if [ "$(id -u)" -ne 0 ]; then
		return 0
	fi

	_pf_old_ifs=${IFS}
	IFS=,
	for entry in ${forwards}; do
		IFS=${_pf_old_ifs}
		entry="$(echo "${entry}" | tr -d '[:space:]')"
		[ -n "${entry}" ] || continue
		parse_forward "${entry}"
		iptables -t nat -D PREROUTING -p "${PROTO}" --dport "${HOST_PORT}" \
			-j DNAT --to-destination "${guest_ip}:${GUEST_PORT}" 2>/dev/null || true
		iptables -t nat -D OUTPUT -p "${PROTO}" --dport "${HOST_PORT}" \
			-j DNAT --to-destination "${guest_ip}:${GUEST_PORT}" 2>/dev/null || true
		iptables -D FORWARD -p "${PROTO}" -d "${guest_ip}" --dport "${GUEST_PORT}" -j ACCEPT 2>/dev/null || true
		iptables -t nat -D POSTROUTING -p "${PROTO}" -d "${guest_ip}" --dport "${GUEST_PORT}" -j MASQUERADE 2>/dev/null || true
		IFS=,
	done
	IFS=${_pf_old_ifs}
}

enable_masquerade() {
	if [ "$(id -u)" -ne 0 ]; then
		die "masquerade needs root"
	fi
	outif="$(ip route show default | awk '{print $5; exit}')"
	[ -n "${outif}" ] || die "no default route found"
	iptables -t nat -C POSTROUTING -s "${SUBNET_PREFIX}.0/${GUEST_PREFIX}" -o "${outif}" -j MASQUERADE 2>/dev/null \
		|| iptables -t nat -A POSTROUTING -s "${SUBNET_PREFIX}.0/${GUEST_PREFIX}" -o "${outif}" -j MASQUERADE
	iptables -C FORWARD -i "${BRIDGE_NAME}" -o "${outif}" -j ACCEPT 2>/dev/null \
		|| iptables -A FORWARD -i "${BRIDGE_NAME}" -o "${outif}" -j ACCEPT
	iptables -C FORWARD -i "${outif}" -o "${BRIDGE_NAME}" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null \
		|| iptables -A FORWARD -i "${outif}" -o "${BRIDGE_NAME}" -m state --state RELATED,ESTABLISHED -j ACCEPT
}
