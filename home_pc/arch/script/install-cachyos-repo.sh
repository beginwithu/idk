#!/usr/bin/env bash

# CachyOS Repository Auto-Installer
# For Arch Linux and Arch-based distributions

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

REPO_URL="https://mirror.cachyos.org/repo/x86_64/cachyos"
CACHYOS_KEY="F3B607488DB35A47"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error: This script must be run as root${NC}" >&2
    exit 1
fi

for cmd in pacman pacman-key curl tar awk; do
    if ! command -v "$cmd" &>/dev/null; then
        echo -e "${RED}Error: Required command '$cmd' not found.${NC}" >&2
        exit 1
    fi
done

detect_cpu_arch() {
    local ld_so="/lib/ld-linux-x86-64.so.2"
    [[ -x "$ld_so" ]] || ld_so="/usr/lib/ld-linux-x86-64.so.2"

    local hwcaps=""
    if [[ -x "$ld_so" ]]; then
        hwcaps="$("$ld_so" --help 2>/dev/null || true)"
    fi

    if grep -q "x86-64-v4 (supported, searched)" <<< "$hwcaps"; then
        echo "v4"
    elif grep -q "x86-64-v3 (supported, searched)" <<< "$hwcaps"; then
        echo "v3"
    else
        echo "baseline"
    fi
}

get_latest_pkg_url() {
    local index_html="$1"
    local pkg_prefix="$2"
    local filename

    filename="$(printf '%s\n' "$index_html" \
        | grep -oE "${pkg_prefix}-[0-9][^\"'<>[:space:]]*\.pkg\.tar\.zst" \
        | sort -uV \
        | tail -n 1 || true)"

    if [[ -z "$filename" ]]; then
        echo -e "${RED}Error: Could not resolve latest package for '${pkg_prefix}'${NC}" >&2
        exit 1
    fi

    echo "${REPO_URL}/${filename}"
}

echo -e "${GREEN}=== CachyOS Repository Installer ===${NC}"
echo
echo -e "${YELLOW}Select installation method:${NC}"
echo "1) Automated (recommended) - Downloads official CachyOS script"
echo "2) Manual - Adds repos directly"
read -rp "Enter choice [1-2]: " choice

case "$choice" in
    1)
        echo -e "${GREEN}Downloading official CachyOS repo installer...${NC}"
        curl -fsSL "https://mirror.cachyos.org/cachyos-repo.tar.xz" -o "${TMP_DIR}/cachyos-repo.tar.xz"
        tar -xf "${TMP_DIR}/cachyos-repo.tar.xz" -C "$TMP_DIR"

        echo -e "${GREEN}Running official installer...${NC}"
        (
            cd "${TMP_DIR}/cachyos-repo"
            bash ./cachyos-repo.sh
        )
        ;;
    2)
        echo -e "${YELLOW}Detecting CPU architecture...${NC}"
        ARCH="$(detect_cpu_arch)"
        echo -e "${GREEN}Detected: x86-64 (${ARCH})${NC}"

        echo -e "${YELLOW}Importing CachyOS signing key...${NC}"
        pacman-key --recv-keys "$CACHYOS_KEY" --keyserver keyserver.ubuntu.com
        pacman-key --lsign-key "$CACHYOS_KEY"

        echo -e "${YELLOW}Fetching latest keyring and mirrorlist package URLs...${NC}"
        INDEX_HTML="$(curl -fsSL "${REPO_URL}/")"

        PKGS=(
            "$(get_latest_pkg_url "$INDEX_HTML" "cachyos-keyring")"
            "$(get_latest_pkg_url "$INDEX_HTML" "cachyos-mirrorlist")"
        )

        if [[ "$ARCH" == "v4" ]]; then
            PKGS+=("$(get_latest_pkg_url "$INDEX_HTML" "cachyos-v4-mirrorlist")")
        elif [[ "$ARCH" == "v3" ]]; then
            PKGS+=("$(get_latest_pkg_url "$INDEX_HTML" "cachyos-v3-mirrorlist")")
        fi

        echo -e "${YELLOW}Installing CachyOS keyring and mirrorlists...${NC}"
        pacman -U --noconfirm "${PKGS[@]}"

        echo -e "${YELLOW}Configuring repositories in /etc/pacman.conf...${NC}"
        REPO_CONFIG=""
        if [[ "$ARCH" == "v4" ]]; then
            REPO_CONFIG="[cachyos-v4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist

[cachyos-core-v4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist

[cachyos-extra-v4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist

"
        elif [[ "$ARCH" == "v3" ]]; then
            REPO_CONFIG="[cachyos-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

[cachyos-core-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

[cachyos-extra-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

"
        fi

        REPO_CONFIG+="[cachyos]
Include = /etc/pacman.d/cachyos-mirrorlist"

        if grep -qE '^\[cachyos(-v[34])?\]' /etc/pacman.conf; then
            echo -e "${YELLOW}CachyOS repositories are already configured in /etc/pacman.conf${NC}"
        else
            BACKUP_FILE="/etc/pacman.conf.bak.$(date +%Y%m%d-%H%M%S)"
            cp -a /etc/pacman.conf "$BACKUP_FILE"
            echo -e "${GREEN}Backup created: ${BACKUP_FILE}${NC}"

            TMP_CONF="${TMP_DIR}/pacman.conf"
            REPO_BLOCK="$REPO_CONFIG" awk '
                !inserted && /^\[core\][[:space:]]*$/ {
                    printf "%s\n\n", ENVIRON["REPO_BLOCK"]
                    inserted = 1
                }
                { print }
                END {
                    if (!inserted) {
                        printf "\n%s\n", ENVIRON["REPO_BLOCK"]
                    }
                }
            ' /etc/pacman.conf > "$TMP_CONF"

            chmod --reference=/etc/pacman.conf "$TMP_CONF"
            mv "$TMP_CONF" /etc/pacman.conf
            echo -e "${GREEN}Repositories inserted above [core] in /etc/pacman.conf${NC}"
        fi

        read -rp "Sync databases and upgrade system now (pacman -Syu)? [Y/n]: " do_upgrade
        if [[ "${do_upgrade:-Y}" =~ ^[Yy]$ ]]; then
            pacman -Syu
        else
            echo -e "${YELLOW}Skipped upgrade. Run 'sudo pacman -Syu' before installing packages.${NC}"
        fi
        ;;
    *)
        echo -e "${RED}Invalid choice${NC}" >&2
        exit 1
        ;;
esac

echo
echo -e "${GREEN}=== Installation Complete ===${NC}"
