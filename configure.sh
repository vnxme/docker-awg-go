#!/bin/bash

IFACE="$1"
if [ -z "${IFACE}" ]; then
    echo "Error: an interface name must be provided. Exiting."
    exit 1
fi

LOCAL_PRIVATE_KEY="$(awg genkey)"
echo "${LOCAL_PRIVATE_KEY}" > "./${IFACE}_local_private.key"

LOCAL_PUBLIC_KEY="$(echo "${LOCAL_PRIVATE_KEY}" | awg pubkey)"
echo "${LOCAL_PUBLIC_KEY}" > "./${IFACE}_local_public.key"

LOCAL_SHARED_KEY="$(awg genpsk)"
echo "${LOCAL_SHARED_KEY}" > "./${IFACE}_shared.key"

# Ref: https://github.com/amnezia-vpn/amnezia-client/blob/4.8.12.6/client/server_scripts/awg/configure_container.sh
cat <<EOF > "./${IFACE}.conf"
[Interface]
PrivateKey = ${LOCAL_PRIVATE_KEY}
Address = {LOCAL_ADDR_IPV4}/{LOCAL_MASK_IPV4}, {LOCAL_ADDR_IPV6}/{LOCAL_MASK_IPV6}
ListenPort = {LOCAL_PORT}
Jc = {JUNK_PACKET_COUNT}
Jmin = {JUNK_PACKET_MIN_SIZE}
Jmax = {JUNK_PACKET_MAX_SIZE}
S1 = {INIT_PACKET_JUNK_SIZE}
S2 = {RESPONSE_PACKET_JUNK_SIZE}
S3 = {COOKIE_REPLY_PACKET_JUNK_SIZE}
S4 = {TRANSPORT_PACKET_JUNK_SIZE}
H1 = {INIT_PACKET_MAGIC_HEADER}
H2 = {RESPONSE_PACKET_MAGIC_HEADER}
H3 = {UNDERLOAD_PACKET_MAGIC_HEADER}
H4 = {TRANSPORT_PACKET_MAGIC_HEADER}
EOF

# Ref: https://github.com/amnezia-vpn/amnezia-client/blob/4.8.12.6/client/server_scripts/awg/template.conf
cat <<EOF > "./${IFACE}_peer.conf.template"
[Interface]
Address = {REMOTE_ADDR_IPV4}/32, {REMOTE_ADDR_IPV6}/128
DNS = {PRIMARY_DNS}, {SECONDARY_DNS}
PrivateKey = {REMOTE_PRIVATE_KEY}
Jc = {JUNK_PACKET_COUNT}
Jmin = {JUNK_PACKET_MIN_SIZE}
Jmax = {JUNK_PACKET_MAX_SIZE}
S1 = {INIT_PACKET_JUNK_SIZE}
S2 = {RESPONSE_PACKET_JUNK_SIZE}
S3 = {COOKIE_REPLY_PACKET_JUNK_SIZE}
S4 = {TRANSPORT_PACKET_JUNK_SIZE}
H1 = {INIT_PACKET_MAGIC_HEADER}
H2 = {RESPONSE_PACKET_MAGIC_HEADER}
H3 = {UNDERLOAD_PACKET_MAGIC_HEADER}
H4 = {TRANSPORT_PACKET_MAGIC_HEADER}
I1 = {SPECIAL_JUNK_1}
I2 = {SPECIAL_JUNK_2}
I3 = {SPECIAL_JUNK_3}
I4 = {SPECIAL_JUNK_4}
I5 = {SPECIAL_JUNK_5}

[Peer]
PublicKey = ${LOCAL_PUBLIC_KEY}
PresharedKey = ${LOCAL_SHARED_KEY}
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = {LOCAL_ADDR}:{LOCAL_PORT}
PersistentKeepalive = 25
EOF
