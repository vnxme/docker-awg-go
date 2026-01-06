ARG ALPINE_VERSION=3.23.2
ARG GOLANG_VERSION=1.25.5

FROM golang:${GOLANG_VERSION}-alpine AS builder

ARG TARGETARCH TARGETOS

WORKDIR /app/go

ARG GO_BRANCH=master
ARG GO_COMMIT=449d7cffd4adf86971bd679d0be5384b443e8be5
ARG GO_REPO=https://github.com/amnezia-vpn/amneziawg-go

# Ref: https://github.com/amnezia-vpn/amneziawg-go/blob/v0.2.16/Dockerfile
RUN \
    --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg \
    apk add --update --no-cache build-base git; \
    git clone --branch "${GO_BRANCH}" "${GO_REPO}" .; \
    git reset --hard "${GO_COMMIT}"; \
    CGO_ENABLED=1 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -trimpath -ldflags '-s -w -linkmode external -extldflags "-fno-PIC -static"' -v -o ./amneziawg-go

WORKDIR /app/tools

ARG TOOLS_BRANCH=master
ARG TOOLS_COMMIT=5c6ffd6168f7c69199200a91803fa02e1b8c4152
ARG TOOLS_REPO=https://github.com/amnezia-vpn/amneziawg-tools

# Ref: https://github.com/amnezia-vpn/amneziawg-tools/blob/v1.0.20250903/.github/workflows/linux-build.yml
RUN \
    apk add --update --no-cache build-base git linux-headers; \
    git clone --branch "${TOOLS_BRANCH}" "${TOOLS_REPO}" .; \
    git reset --hard "${TOOLS_COMMIT}"; \
    cd src; make; cd -

WORKDIR /app/export

# Ref: https://github.com/amnezia-vpn/amneziawg-tools/blob/v1.0.20250903/.github/workflows/linux-build.yml
# Ref: https://github.com/amnezia-vpn/amneziawg-tools/blob/v1.0.20250903/src/Makefile
RUN \
    mkdir -p ./bin ./completion ./man; \
    mv /app/go/amneziawg-go                               ./bin/amneziawg-go; \
    mv /app/tools/src/wg                                  ./bin/awg; \
    mv /app/tools/src/wg-quick/linux.bash                 ./bin/awg-quick; \
    cp /app/tools/src/completion/wg.bash-completion       ./completion/awg; \
    cp /app/tools/src/completion/wg-quick.bash-completion ./completion/awg-quick; \
    cp /app/tools/src/man/wg.8                            ./man/awg.8; \
    cp /app/tools/src/man/wg-quick.8                      ./man/awg-quick.8

FROM alpine:${ALPINE_VERSION}

COPY --chmod=0755 entrypoint.sh /app/
COPY --from=builder /app/export /app/import

WORKDIR /app

# Ref: https://github.com/amnezia-vpn/amneziawg-tools/blob/v1.0.20250903/.github/workflows/linux-build.yml
# Ref: https://github.com/amnezia-vpn/amneziawg-tools/blob/v1.0.20250903/src/Makefile
RUN DEPS=" \
    bash \
    bash-completion \
    curl \
    dumb-init \
    iproute2 \
    iptables \
    iptables-legacy \
    iputils-ping \
    libcap \
    mandoc \
    net-tools \
    openssl \
    vlan \
    "; \
    apk add --update --no-cache --virtual .deps ${DEPS}; \
    mkdir -p /usr/share/bash-completion/completions /usr/share/man/man8; \
    chmod 0755 ./import/bin/*; \
    chmod 0644 ./import/completion/* ./import/man/*; \
    mv ./import/bin/*        /usr/bin/; \
    mv ./import/completion/* /usr/share/bash-completion/completions/; \
    mv ./import/man/*        /usr/share/man/man8/; \
    ln -s /usr/bin/awg                                     /usr/bin/wg; \
    ln -s /usr/bin/awg-quick                               /usr/bin/wg-quick; \
    ln -s /usr/share/man/man8/awg.8                        /usr/share/man/man8/wg.8; \
    ln -s /usr/share/man/man8/awg-quick.8                  /usr/share/man/man8/wg-quick.8; \
    ln -s /usr/share/bash-completion/completions/awg       /usr/share/bash-completion/completions/wg; \
    ln -s /usr/share/bash-completion/completions/awg-quick /usr/share/bash-completion/completions/wg-quick; \
    rm -rf ./import

#Ref: https://github.com/amnezia-vpn/amnezia-client/blob/4.8.11.4/client/server_scripts/awg/Dockerfile
RUN echo -e " \n\
    fs.file-max = 51200 \n\
    \n\
    net.core.rmem_max = 67108864 \n\
    net.core.wmem_max = 67108864 \n\
    net.core.netdev_max_backlog = 250000 \n\
    net.core.somaxconn = 4096 \n\
    \n\
    net.ipv4.tcp_syncookies = 1 \n\
    net.ipv4.tcp_tw_reuse = 1 \n\
    net.ipv4.tcp_tw_recycle = 0 \n\
    net.ipv4.tcp_fin_timeout = 30 \n\
    net.ipv4.tcp_keepalive_time = 1200 \n\
    net.ipv4.ip_local_port_range = 10000 65000 \n\
    net.ipv4.tcp_max_syn_backlog = 8192 \n\
    net.ipv4.tcp_max_tw_buckets = 5000 \n\
    net.ipv4.tcp_fastopen = 3 \n\
    net.ipv4.tcp_mem = 25600 51200 102400 \n\
    net.ipv4.tcp_rmem = 4096 87380 67108864 \n\
    net.ipv4.tcp_wmem = 4096 65536 67108864 \n\
    net.ipv4.tcp_mtu_probing = 1 \n\
    net.ipv4.tcp_congestion_control = hybla \n\
    # for low-latency network, use cubic instead \n\
    # net.ipv4.tcp_congestion_control = cubic \n\
    " | sed -e 's/^\s\+//g' | tee -a /etc/sysctl.conf && \
    mkdir -p /etc/security && \
    echo -e " \n\
    * soft nofile 51200 \n\
    * hard nofile 51200 \n\
    " | sed -e 's/^\s\+//g' | tee -a /etc/security/limits.conf

RUN \
    mkdir -p /etc/amnezia/amneziawg; \
    chmod 0700 /etc/amnezia/amneziawg; \
    cd /etc/amnezia/amneziawg; \
    LOCAL_PRIVATE_KEY="$(wg genkey)"; \
    echo "${LOCAL_PRIVATE_KEY}" > ./wg0_local_private.key; \
    LOCAL_PUBLIC_KEY="$(echo "${LOCAL_PRIVATE_KEY}" | wg pubkey)"; \
    echo "${LOCAL_PUBLIC_KEY}" > ./wg0_local_public.key; \
    LOCAL_SHARED_KEY="$(wg genpsk)"; \
    echo "${LOCAL_SHARED_KEY}" > ./wg0_shared.key; \
    echo -e "\n\
    [Interface]\n\
    PrivateKey = ${LOCAL_PRIVATE_KEY}\n\
    Address = $AWG_SUBNET_IP/$WIREGUARD_SUBNET_CIDR\n\
    ListenPort = $AWG_SERVER_PORT\n\
    Jc = $JUNK_PACKET_COUNT\n\
    Jmin = $JUNK_PACKET_MIN_SIZE\n\
    Jmax = $JUNK_PACKET_MAX_SIZE\n\
    S1 = $INIT_PACKET_JUNK_SIZE\n\
    S2 = $RESPONSE_PACKET_JUNK_SIZE\n\
    H1 = $INIT_PACKET_MAGIC_HEADER\n\
    H2 = $RESPONSE_PACKET_MAGIC_HEADER\n\
    H3 = $UNDERLOAD_PACKET_MAGIC_HEADER\n\
    H4 = $TRANSPORT_PACKET_MAGIC_HEADER\n\
    " | sed -e 's/^\s\+//g' > ./wg0.conf; \
    echo -e "\n\
    [Interface]\n\
    Address = $WIREGUARD_CLIENT_IP/32\n\
    DNS = $PRIMARY_DNS, $SECONDARY_DNS\n\
    PrivateKey = $WIREGUARD_CLIENT_PRIVATE_KEY\n\
    Jc = $JUNK_PACKET_COUNT\n\
    Jmin = $JUNK_PACKET_MIN_SIZE\n\
    Jmax = $JUNK_PACKET_MAX_SIZE\n\
    S1 = $INIT_PACKET_JUNK_SIZE\n\
    S2 = $RESPONSE_PACKET_JUNK_SIZE\n\
    S3 = $COOKIE_REPLY_PACKET_JUNK_SIZE\n\
    S4 = $TRANSPORT_PACKET_JUNK_SIZE\n\
    H1 = $INIT_PACKET_MAGIC_HEADER\n\
    H2 = $RESPONSE_PACKET_MAGIC_HEADER\n\
    H3 = $UNDERLOAD_PACKET_MAGIC_HEADER\n\
    H4 = $TRANSPORT_PACKET_MAGIC_HEADER\n\
    I1 = $SPECIAL_JUNK_1\n\
    I2 = $SPECIAL_JUNK_2\n\
    I3 = $SPECIAL_JUNK_3\n\
    I4 = $SPECIAL_JUNK_4\n\
    I5 = $SPECIAL_JUNK_5\n\
    \n\
    [Peer]\n\
    PublicKey = ${LOCAL_PUBLIC_KEY}\n\
    PresharedKey = ${LOCAL_SHARED_KEY}\n\
    AllowedIPs = 0.0.0.0/0, ::/0\n\
    Endpoint = $SERVER_IP_ADDRESS:$AWG_SERVER_PORT\n\
    PersistentKeepalive = 25\n\
    " | sed -e 's/^\s\+//g' > ./wg0.peer.conf.template

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["bash", "--", "/app/entrypoint.sh"]
