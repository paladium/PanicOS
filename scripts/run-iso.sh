#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f panicos.iso ]]; then
  echo "ISO not found. Building it first..." >&2
  scripts/mkiso.sh
fi

qemu-system-i386 \
  -cdrom panicos.iso \
  -machine pc \
  -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
  -debugcon file:debugcon.log -global isa-debugcon.iobase=0xe9 \
  -serial stdio \
  -display none \
  -no-reboot \
  -no-shutdown \
  -monitor none
