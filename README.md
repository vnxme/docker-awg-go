# Summary

A set of container images of AmneziaWG-Go.

# Description

**AmneziaWG-Go** is an implementation of [Amnezia WireGuard](https://docs.amnezia.org/documentation/amnezia-wg/) in Go. It inherits the architectural simplicity and high performance of the original WireGuard implementation, but eliminates the identifiable network signatures that make WireGuard easily detectable by Deep Packet Inspection (DPI) systems.

# Software

The container images include the following **key software packages**:
- [amneziawg-go](https://github.com/amnezia-vpn/amneziawg-go) provides `amneziawg-go`
- [amneziawg-tools](https://github.com/amnezia-vpn/amneziawg-tools) provides `awg` and `awg-quick`

The following **extra software packages** are included as well:
- [bash](https://pkgs.alpinelinux.org/package/v3.23/main/x86_64/bash) and [bash-completion](https://pkgs.alpinelinux.org/package/v3.23/main/x86_64/bash-completion)
- [curl](https://pkgs.alpinelinux.org/package/v3.23/main/x86_64/curl)
- [dumb-init](https://pkgs.alpinelinux.org/package/v3.23/main/x86_64/dumb-init)
- [iproute2](https://pkgs.alpinelinux.org/package/v3.23/main/x86_64/iproute2)
- [iptables](https://pkgs.alpinelinux.org/package/v3.23/main/x86_64/iptables) and [iptables-legacy](https://pkgs.alpinelinux.org/package/v3.23/main/x86_64/iptables-legacy)
- [iputils-ping](https://pkgs.alpinelinux.org/package/v3.23/main/x86_64/iputils-ping)
- [libcap](https://pkgs.alpinelinux.org/package/v3.23/main/x86_64/libcap)
- [mandoc](https://pkgs.alpinelinux.org/package/v3.23/main/x86_64/mandoc)
- [net-tools](https://pkgs.alpinelinux.org/package/v3.23/main/x86_64/net-tools)
- [openssl](https://pkgs.alpinelinux.org/package/v3.23/main/x86_64/openssl)

# Platforms

The container images are based on [Alpine](https://hub.docker.com/_/alpine). The repository uses [Golang](https://hub.docker.com/_/golang) for multi-stage build and the [XX helpers](https://hub.docker.com/r/tonistiigi/xx) for AMD64-based cross-compilation. Below is a summary of the platforms supported by this repository and its dependencies.

| OS/Arch        | Alpine | Golang | XX  | AmneziaWG-Go |
|----------------|--------|--------|-----|--------------|
| linux/386      | Yes    | Yes    | Yes | Yes          |
| linux/amd64    | Yes    | Yes    | Yes | Yes          |
| linux/arm/v5   | No     | No     | Yes | No           |
| linux/arm/v6   | Yes    | Yes    | Yes | Yes          |
| linux/arm/v7   | Yes    | Yes    | Yes | Yes          |
| linux/arm64    | Yes    | Yes    | Yes | Yes          |
| linux/loong64  | No     | No     | Yes | No           |
| linux/mips     | No     | No     | Yes | No           |
| linux/mips64   | No     | No     | Yes | No           |
| linux/mips64le | No     | No     | Yes | No           |
| linux/mipsle   | No     | No     | Yes | No           |
| linux/ppc64le  | Yes    | Yes    | Yes | Yes          |
| linux/riscv64  | Yes    | Yes    | Yes | Yes          |
| linux/s390x    | Yes    | Yes    | Yes | Yes          |
