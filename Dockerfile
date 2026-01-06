ARG ALPINE_VERSION=3.23.2
ARG GOLANG_VERSION=1.25.5

FROM golang:${GOLANG_VERSION}-alpine AS builder

WORKDIR /app/go

ARG GO_BRANCH=master
ARG GO_COMMIT=449d7cffd4adf86971bd679d0be5384b443e8be5
ARG GO_REPO=https://github.com/amnezia-vpn/amneziawg-go

RUN \
    apk add --update --no-cache build-base git; \
    git clone --branch "${GO_BRANCH}" "${GO_REPO}" .; \
    git reset --hard "${GO_COMMIT}"

ARG TARGETARCH TARGETOS

RUN \
    --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg \
    CGO_ENABLED=1 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -trimpath -ldflags '-s -w -linkmode external -extldflags "-fno-PIC -static"' -v -o ./amneziawg-go

WORKDIR /app/tools

ARG TOOLS_BRANCH=master
ARG TOOLS_COMMIT=5c6ffd6168f7c69199200a91803fa02e1b8c4152
ARG TOOLS_REPO=https://github.com/amnezia-vpn/amneziawg-tools

RUN \
    apk add --update --no-cache linux-headers; \
    git clone --branch "${TOOLS_BRANCH}" "${TOOLS_REPO}" .; \
    git reset --hard "${TOOLS_COMMIT}"; \
    cd src; make; cd -

FROM alpine:${ALPINE_VERSION}

COPY --from=builder --chmod=0755 /app/go/amneziawg-go               /usr/bin/amneziawg-go
COPY --from=builder --chmod=0755 /app/tools/src/wg                  /usr/bin/awg
COPY --from=builder --chmod=0755 /app/tools/src/wg-quick/linux.bash /usr/bin/awg-quick

RUN \
    ln -s /usr/bin/awg       /usr/bin/wg; \
    ln -s /usr/bin/awg-quick /usr/bin/wg-quick

RUN EXTRAS=" \
    bash \
    curl \
    dumb-init \
    iproute2 \
    iptables \
    iptables-legacy \
    iputils-ping \
    libcap \
    net-tools \
    openssl \
    vlan \
    "; apk add --update --no-cache --virtual .extras ${EXTRAS} && \
    mkdir -p /app/hooks/up /app/hooks/down /etc/amnezia

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

COPY --chmod=0755 entrypoint.sh /app/

WORKDIR /app

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["bash", "--", "/app/entrypoint.sh"]

LABEL org.opencontainers.image.source=https://github.com/vnxme/docker-awg-go
