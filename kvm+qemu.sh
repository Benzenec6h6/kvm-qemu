#!/usr/bin/env bash
set -euo pipefail

### ── 設定 ────────────────────────────
ISO=".iso"
DISK=".qcow2"
DISK_SIZE="50G"
MEM=16384
CPU=5

OVMF_CODE="/usr/share/OVMF/OVMF_CODE_4M.fd"
OVMF_VARS="OVMF_VARS.fd"       # 作成後は絶対に上書きしない
SPICE_PORT=5900
### ──────────────────────────────────

# ---------- OVMF の存在確認 ----------
[[ -f $OVMF_CODE ]] || { echo "OVMF_CODE が見つかりません: $OVMF_CODE"; exit 1; }
[[ -f $OVMF_VARS ]] || { cp /usr/share/OVMF/OVMF_VARS_4M.fd "$OVMF_VARS"; }

# ---------- ルート qcow2 ----------
[[ -f $DISK ]] || qemu-img create -f qcow2 "$DISK" "$DISK_SIZE"

# ---------- 起動モード ----------
WITH_ISO=false
[[ ${1:-} == "--iso" ]] && WITH_ISO=true

# ---------- ドライブ定義 ----------
DRIVES=(
  -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE"
  -drive if=pflash,format=raw,file="$OVMF_VARS"
  # ルートディスク (bootindex=1) － 常に接続
  -drive if=none,id=disk0,file="$DISK",format=qcow2
  -device virtio-blk-pci,drive=disk0,bootindex=1
)

if $WITH_ISO; then
  # ISO (bootindex=2) － インストール時のみ
  DRIVES+=(
    -drive if=none,id=cd0,media=cdrom,readonly=on,file="$ISO"
    -device ide-cd,drive=cd0,bootindex=2
  )
fi

# ---------- QEMU 起動 ----------
echo "[+] Launch QEMU (ISO=$WITH_ISO)"
qemu-system-x86_64 \
  -enable-kvm \
  -machine q35,accel=kvm \
  -m "$MEM" \
  -smp "$CPU" \
  -cpu host \
  "${DRIVES[@]}" \
  -boot order=c \
  -netdev user,id=net0 -device virtio-net,netdev=net0 \
  -spice port=$SPICE_PORT,disable-ticketing=on \
  -device qxl-vga \
  -display none \
  &

QEMU_PID=$!
trap 'echo "[+] Cleaning up QEMU..."; kill $QEMU_PID 2>/dev/null || true' EXIT

sleep 1
echo "[+] Launching remote-viewer..."
remote-viewer "spice://127.0.0.1:$SPICE_PORT" || true

wait $QEMU_PID