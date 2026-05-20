#!/bin/bash
# TinyAI QEMU launcher — boot qemuarm64 TinyAI image
# Usage:
#   ./qemu-tinyai.sh                    Auto-detect and boot
#   ./qemu-tinyai.sh --model ext4       Attach model data partition
#   ./qemu-tinyai.sh --ssh-port 2222    Forward host:2222 -> guest:22
#   ./qemu-tinyai.sh --help

set -e

# ── Defaults ──────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SEARCH_DIR="${1:-${SCRIPT_DIR}}"

MACHINE="virt"
CPU="cortex-a57"
SMP="4"
MEM="2G"
CONSOLE="ttyAMA0"
SSH_PORT="2222"
ATTACH_MODEL="false"
MODEL_IMAGE="tinyai-model-image-qemuarm64.ext4"

# ── Colors ────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[0;33m'
RED='\033[0;31m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

info()  { printf "${GREEN}%s${NC}\n" "$*"; }
warn()  { printf "${YELLOW}%s${NC}\n" "$*"; }
err()   { printf "${RED}%s${NC}\n" "$*" >&2; }
header(){ printf "\n${BOLD}${CYAN}━━━ %s ━━━${NC}\n" "$*"; }

# ── Parse args ────────────────────────────────────────────────────────

usage() {
    cat <<EOF
TinyAI QEMU launcher — boot qemuarm64 TinyAI image

Usage: $(basename "$0") [OPTIONS] [search-dir]

Options:
  --model           Attach model data partition (tinyai-model-image-qemuarm64.ext4)
  --ssh-port PORT   Forward host PORT to guest SSH (default: 2222)
  --no-ssh          Disable SSH port forwarding
  --mem SIZE        RAM for guest (default: 2G)
  --smp N           Number of CPU cores (default: 4)
  --help            Show this help

If search-dir is omitted, the script searches its own directory and cwd.
EOF
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h) usage ;;
        --model)    ATTACH_MODEL="true"; shift ;;
        --ssh-port) SSH_PORT="$2"; shift 2 ;;
        --no-ssh)   SSH_PORT=""; shift ;;
        --mem)      MEM="$2"; shift 2 ;;
        --smp)      SMP="$2"; shift 2 ;;
        *)          SEARCH_DIR="$1"; shift ;;
    esac
done

# ── Find artifacts ────────────────────────────────────────────────────

find_artifact() {
    local pattern="$1"
    local dirs="${SEARCH_DIR} ${SCRIPT_DIR} ${PWD}"
    for d in $dirs; do
        local found; found=$(find "$d" -maxdepth 1 -name "$pattern" -type f 2>/dev/null | head -1)
        if [ -n "$found" ]; then
            echo "$found"
            return 0
        fi
    done
    return 1
}

header "TinyAI QEMU Launcher"
echo

# Kernel
KERNEL=$(find_artifact "Image" ) || KERNEL=$(find_artifact "Image.gz" ) || true
if [ -z "$KERNEL" ]; then
    err "Kernel image not found (Image / Image.gz)"
    err "Searched: ${SEARCH_DIR} ${SCRIPT_DIR} ${PWD}"
    exit 1
fi
info "✓ Kernel: $(basename "$KERNEL")"

# Rootfs (prefer cpio.gz for initramfs boot)
ROOTFS=$(find_artifact "*qemuarm64*cpio.gz" ) || ROOTFS=$(find_artifact "*.cpio.gz" ) || true
if [ -z "$ROOTFS" ]; then
    err "Rootfs image not found (*.cpio.gz)"
    err "Searched: ${SEARCH_DIR} ${SCRIPT_DIR} ${PWD}"
    exit 1
fi
info "✓ Rootfs: $(basename "$ROOTFS")"

# Optional: model ext4
MODEL=""
if [ "$ATTACH_MODEL" = "true" ]; then
    MODEL=$(find_artifact "$MODEL_IMAGE" ) || MODEL=$(find_artifact "tinyai-model-image*.ext4" ) || true
    if [ -z "$MODEL" ]; then
        warn "⚠ Model image not found ($MODEL_IMAGE) — skipping"
    else
        info "✓ Model:  $(basename "$MODEL")"
    fi
fi

# Check QEMU availability
QEMU_BIN=""
for bin in qemu-system-aarch64 qemu-system-aarch64-static; do
    if command -v "$bin" >/dev/null 2>&1; then
        QEMU_BIN="$bin"
        break
    fi
done
if [ -z "$QEMU_BIN" ]; then
    err "qemu-system-aarch64 not found. Install it:"
    err "  apt install qemu-system-arm    (Debian/Ubuntu)"
    err "  dnf install qemu-system-aarch64 (Fedora)"
    exit 1
fi
info "✓ QEMU:   $QEMU_BIN"

# Check CPU feature support
CPU_SUPPORT=$("$QEMU_BIN" -cpu help 2>/dev/null | grep -c "cortex-a57" || true)
if [ "$CPU_SUPPORT" -eq 0 ]; then
    warn "⚠ cortex-a57 not in CPU list, falling back to 'max'"
    CPU="max"
fi

echo
header "Boot Configuration"
printf "  Machine:   %s\n" "$MACHINE"
printf "  CPU:       %s\n" "$CPU"
printf "  SMP:       %s\n" "$SMP"
printf "  Memory:    %s\n" "$MEM"
printf "  Console:   %s\n" "$CONSOLE"
if [ -n "$SSH_PORT" ]; then
    printf "  SSH fwd:   host:${SSH_PORT} → guest:22\n"
else
    printf "  SSH fwd:   (disabled)\n"
fi
if [ -n "$MODEL" ]; then
    printf "  Data disk: %s\n" "$(basename "$MODEL")"
fi
echo

# ── Build QEMU command ────────────────────────────────────────────────

declare -a QEMU_ARGS

QEMU_ARGS+=(
    -machine "$MACHINE"
    -cpu "$CPU"
    -smp "$SMP"
    -m "$MEM"
    -nographic
)

# Kernel + initramfs
QEMU_ARGS+=(
    -kernel "$KERNEL"
    -initrd "$ROOTFS"
    -append "console=${CONSOLE},115200"
)

# Network: user-mode with SSH forwarding
if [ -n "$SSH_PORT" ]; then
    QEMU_ARGS+=(
        -netdev "user,id=net0,hostfwd=tcp::${SSH_PORT}-:22"
        -device virtio-net-pci,netdev=net0
    )
else
    QEMU_ARGS+=(
        -netdev user,id=net0
        -device virtio-net-pci,netdev=net0
    )
fi

# Optional: model data disk
if [ -n "$MODEL" ]; then
    QEMU_ARGS+=(
        -drive "file=${MODEL},format=raw,if=virtio"
    )
fi

# ── Boot ──────────────────────────────────────────────────────────────

info "Starting QEMU..."
info "  To exit: Ctrl-A X"
if [ -n "$SSH_PORT" ]; then
    info "  SSH:    ssh root@localhost -p ${SSH_PORT}"
fi
if [ -n "$MODEL" ]; then
    info "  Model disk attached as /dev/vdb"
    info "  On guest: mkdir -p /data && mount /dev/vdb /data"
fi
echo

set -x
exec "$QEMU_BIN" "${QEMU_ARGS[@]}"
