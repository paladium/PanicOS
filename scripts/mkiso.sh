#!/usr/bin/env bash
# Debuggable ISO build helper for PanicOS
set -euo pipefail
set -x

# Build the kernel (release small to avoid huge debug sections)
time zig build -Doptimize=ReleaseSmall -Dstrip=true

# Build user program(s) (clean old outputs to avoid stale binaries)
pushd user >/dev/null
rm -rf zig-out .zig-cache
time zig build -Doptimize=ReleaseSmall -Dstrip=true
popd >/dev/null

# Prepare ISO root
ISO_DIR=build/iso
KERNEL_BIN=zig-out/bin/panicos
rm -rf "$ISO_DIR"
mkdir -p "$ISO_DIR/boot/grub"

install -m 0644 "$KERNEL_BIN" "$ISO_DIR/boot/panicos"

# Install all user apps
mkdir -p "$ISO_DIR/boot"
for app in user/zig-out/bin/*; do
  [ -f "$app" ] || continue
  base=$(basename "$app")
  install -m 0644 "$app" "$ISO_DIR/boot/$base"
done
# Generate GRUB config with all modules
CFG="$ISO_DIR/boot/grub/grub.cfg"
cat > "$CFG" <<'EOF'
set timeout=0
set default=0
serial --unit=0 --speed=115200 --word=8 --parity=no --stop=1
terminal_input serial
terminal_output serial

menuentry "PanicOS" {
    multiboot /boot/panicos
EOF

for app in user/zig-out/bin/*; do
  [ -f "$app" ] || continue
  base=$(basename "$app")
  echo "    module /boot/$base $base" >> "$CFG"
done
echo "    boot" >> "$CFG"
echo "}" >> "$CFG"

# Create ISO via grub2-mkrescue or grub-mkrescue
GRUB_MKRESCUE=""
if command -v grub2-mkrescue >/dev/null 2>&1; then
  GRUB_MKRESCUE="grub2-mkrescue"
elif command -v grub-mkrescue >/dev/null 2>&1; then
  GRUB_MKRESCUE="grub-mkrescue"
else
  echo "Neither grub2-mkrescue nor grub-mkrescue found. Please install GRUB tools and xorriso." >&2
  exit 1
fi

# Make xorriso chatty for debugging if needed
export XORRISO_OPTIONS="-v"

# If BIOS module dir is available, point mkrescue to it to avoid scanning
GRUB_MODDIR=""
if [ -d /usr/lib/grub/i386-pc ]; then
  GRUB_MODDIR="-d /usr/lib/grub/i386-pc"
fi

# On some distros, passing -v helps surface progress; also set a volume label
time "$GRUB_MKRESCUE" $GRUB_MODDIR -v -o panicos.iso "$ISO_DIR"

echo "Created panicos.iso"
