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

# References:
# https://github.com/tonistiigi/xx/blob/v1.9.0/README.md
# https://github.com/amnezia-vpn/amneziawg-go/blob/v0.2.16/Dockerfile
# https://github.com/amnezia-vpn/amneziawg-tools/blob/v1.0.20250903/.github/workflows/linux-build.yml
# https://github.com/amnezia-vpn/amneziawg-tools/blob/v1.0.20250903/src/Makefile
# https://github.com/amnezia-vpn/amnezia-client/blob/4.8.12.6/client/server_scripts/awg/Dockerfile

ARG ALPINE_VERSION=3.23.2
ARG GOLANG_VERSION=1.25.5
ARG XXTOOL_VERSION=1.9.0

FROM --platform=$BUILDPLATFORM tonistiigi/xx:${XXTOOL_VERSION} AS xx

FROM --platform=$BUILDPLATFORM golang:${GOLANG_VERSION}-alpine AS builder

RUN apk --update --no-cache add build-base clang git lld

COPY --from=xx / /

ARG TARGETARCH TARGETOS TARGETPLATFORM TARGETVARIANT

WORKDIR /app/go

ARG GO_BRANCH=master
ARG GO_COMMIT=449d7cffd4adf86971bd679d0be5384b443e8be5
ARG GO_REPO=https://github.com/amnezia-vpn/amneziawg-go

RUN \
    --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg \
    xx-info env && \
    xx-apk add --update --no-cache build-base && \
    git clone --branch "${GO_BRANCH}" "${GO_REPO}" . && \
    git reset --hard "${GO_COMMIT}" && \
    CGO_ENABLED=1 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    xx-go build -trimpath -ldflags '-s -w -linkmode external -extldflags "-fno-PIC -static"' -v -o ./amneziawg-go && \
    xx-verify --static ./amneziawg-go

WORKDIR /app/tools

ARG TOOLS_BRANCH=master
ARG TOOLS_COMMIT=5c6ffd6168f7c69199200a91803fa02e1b8c4152
ARG TOOLS_REPO=https://github.com/amnezia-vpn/amneziawg-tools

RUN \
    xx-info env && \
    xx-apk add --update --no-cache build-base linux-headers && \
    git clone --branch "${TOOLS_BRANCH}" "${TOOLS_REPO}" . && \
    git reset --hard "${TOOLS_COMMIT}" && \
    cd src && CC="xx-clang --static" make && \
    xx-verify --static ./wg

WORKDIR /app/export

RUN \
    mkdir -p bin com man && \
    cp /app/go/amneziawg-go                               ./bin/amneziawg-go && \
    cp /app/tools/src/wg                                  ./bin/awg && \
    cp /app/tools/src/wg-quick/linux.bash                 ./bin/awg-quick && \
    cp /app/tools/src/completion/wg.bash-completion       ./com/awg && \
    cp /app/tools/src/completion/wg-quick.bash-completion ./com/awg-quick && \
    cp /app/tools/src/man/wg.8                            ./man/awg.8 && \
    cp /app/tools/src/man/wg-quick.8                      ./man/awg-quick.8

FROM alpine:${ALPINE_VERSION}

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
    "; \
    apk add --update --no-cache --virtual .deps ${DEPS}; \
    ln -s /usr/bin/awg                                     /usr/bin/wg && \
    ln -s /usr/bin/awg-quick                               /usr/bin/wg-quick && \
    ln -s /usr/share/man/man8/awg.8                        /usr/share/man/man8/wg.8 && \
    ln -s /usr/share/man/man8/awg-quick.8                  /usr/share/man/man8/wg-quick.8 && \
    ln -s /usr/share/bash-completion/completions/awg       /usr/share/bash-completion/completions/wg && \
    ln -s /usr/share/bash-completion/completions/awg-quick /usr/share/bash-completion/completions/wg-quick && \
    mkdir -p /etc/amnezia/amneziawg && \
    chmod 0700 /etc/amnezia/amneziawg

COPY --from=builder --chmod=0644 /app/export/com/* /usr/share/bash-completion/completions/
COPY --from=builder --chmod=0644 /app/export/man/* /usr/share/man/man8/
COPY --from=builder --chmod=0755 /app/export/bin/* /usr/bin/

COPY --chmod=0644 limits.conf /etc/security/limits.conf
COPY --chmod=0644 sysctl.conf /etc/sysctl.d/50-awg.conf
COPY --chmod=0755 *.sh /app/

WORKDIR /app

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["bash", "--", "/app/entrypoint.sh"]
