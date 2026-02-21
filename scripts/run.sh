#!/usr/bin/env bash
set -euo pipefail

zig build

qemu-system-i386 \
  -kernel zig-out/bin/panicos \
  -serial stdio \
  -no-reboot \
  -no-shutdown \
  -monitor none \
  -display none

