**PanicOS**

- **Goal:** A minimal Zig-based 32‑bit hobby OS that boots via Multiboot, prints over serial/VGA, and can run simple userland programs in ring 3. The near‑term target is a tiny userspace “hello” that prints via a syscall and exits.

**Status (Working)**

- Boots with GRUB (Multiboot v1) and runs a Zig kernel.
- Serial (COM1) and VGA text console are initialized; a dual‑output logger prints to both.
- GDT with kernel/user segments; IDT with exception stubs and IRQs; PIC remapped; PIT timer and PS/2 keyboard enabled.
- Paging + TSS enabled; ring‑3 entry is stable. Syscalls (int 0x80) work: `write`, `exit` (idles CPU). VGA is no longer writable from user; output goes through `write`.
- ISR/IRQ return paths use 32‑bit `iret`; #GP/#PF/#UD diagnostics added. SSE/XMM is enabled early so Zig’s generated code can use it safely.
- Minimal kernel shell with line editing (Enter, Backspace) and an `echo` command.
- Keyboard: simple scancode→ASCII map (US, unshifted) and a small ring buffer; shell polls via `intr.kbd_getch()`.
- QEMU run script opens a window, captures keyboard, and routes serial to your terminal.

**Layout**

- `build.zig`: Zig build file for a freestanding i386 kernel (ELF32) with a custom linker script.
- `linker.ld`: Places Multiboot header at start of `.text`, loads at 1 MiB, and discards debug sections.
- `src/boot.S`: Multiboot header and 32‑bit entry, basic stack, GDT/IDT helpers, paging/TLB helpers, and user‑mode enter thunk.
- `src/kernel.zig`: Kernel entry (`kmain`), initializes logger, GDT/IDT, PIC/PIT/keyboard, then sets up paging+TSS and attempts ring‑3 entry.
- `src/io.S`: Port I/O (`inb`/`outb`).
- `src/vga.zig`: VGA text mode console with scrolling and color.
- `src/logger.zig`: Dual logger (serial + VGA) with levels and simple hex dump.
- `src/gdt.zig`: GDT setup with kernel/user segments and TSS slot.
- `src/tss.zig`: TSS struct and initialization (kernel stack for privilege transitions).
- `src/idt.zig`: IDT builder; exception stubs 0..31; IRQ0 (PIT), IRQ1 (keyboard); syscall gate reserved at int 0x80.
- `src/interrupts.S`: ISR/IRQ assembly stubs with proper prologue/epilogue and 32‑bit `iret` returns; minimal int 0x80 entry stub.
- `src/interrupts.zig`: PIC remap, PIT init, PS/2 keyboard enable; common handlers. On exceptions, logs rich diagnostics and halts.
- `src/paging.zig`: Page directory/tables, identity mapping 0..12 MiB, helpers to map user pages with correct U/S and R/W bits, enable paging.
- `src/user.zig`: Minimal user‑mode demo mapping (code + stack + VGA) and entry call. Currently used for bring‑up; triggers the remaining exception.
- `grub/grub.cfg`: GRUB config to load the kernel.
- `scripts/mkiso.sh`: Builds `panicos.iso` via `grub2-mkrescue` (falls back to `grub-mkrescue`).
- `scripts/run-iso.sh`: Runs QEMU with serial on stdio, PS/2 keyboard (`-device isa-kbd`), and a GTK display; writes debug console (0xE9) to `debugcon.log`.

**Dependencies**

- `zig` 0.11+ (tested with Zig’s current std build API).
- `qemu-system-i386`.
- `grub2-mkrescue` (or `grub-mkrescue`) and `xorriso`.

**Build & Run**

- Build kernel optimized: `zig build -Doptimize=ReleaseSmall`
- Create ISO: `scripts/mkiso.sh`
- Run QEMU: `scripts/run-iso.sh`
  - Serial is on your terminal; VGA opens a GTK window. Click to focus for keyboard input.
  - QEMU debug console (port 0xE9) logs to `debugcon.log`.

**Dev Workflow (Always Do This After Changes)**

- Inner loop: `zig build`
  - Validates the kernel compiles after every code change (Zig + asm).
  - Catches ABI/layout mistakes early (e.g., ISR frames, syscall args).
- Outer loop: `scripts/mkiso.sh && scripts/run-iso.sh`
  - Rebuilds the GRUB ISO and boots it in QEMU to test runtime behavior.
  - Watch serial output in your terminal; check `debugcon.log` for 0xE9 writes.
- Re-run quickly after edits:
  - Only code change: `zig build`.
  - Kernel boot/runtime change: `zig build && scripts/mkiso.sh && scripts/run-iso.sh`.
- Clean builds (if caches get stale): `rm -rf .zig-cache zig-out build panicos.iso debugcon.log`
  - Then: `zig build && scripts/mkiso.sh && scripts/run-iso.sh`.

**Shell Usage**

- At boot you’ll see a prompt `> `.
- Type `echo hello world` and press Enter to print `hello world`.
- Backspace edits the current line; Enter submits it.
- Unknown commands print `Unknown command: <name>`.

**Switching To The Ring‑3 Demo**

- The kernel currently starts the shell by default. To run the earlier userland demo instead:
  - Edit `src/kernel.zig` and replace `shell.run();` with `user.map_and_enter();`.
  - Rebuild and run: `zig build && scripts/mkiso.sh && scripts/run-iso.sh`.
  - The demo issues `write` and `exit` syscalls from ring‑3.

**Syscall ABI**

- Call gate: `int 0x80` (IDT entry 128), DPL=3.
- Registers:
  - `EAX`: syscall number.
  - `EBX`, `ECX`, `EDX`: up to three arguments.
  - Return value in `EAX`.
- Implemented syscalls:
  - `1 = write(fd, buf, len)`: ignores `fd` for now, prints to serial + VGA, returns bytes written.
  - `2 = exit(code)`: logs and enters kernel idle (enables interrupts, then `hlt` forever).
  - `3 = yield()`: no-op placeholder for cooperative scheduling.
- Notes:
  - The ISR snapshots user registers from the PUSHAD frame before loading kernel segments, to avoid clobbering `EAX`.
  - Userland must pass valid user pointers; the kernel copies from `ECX` for `len` bytes.

**QEMU Notes**

- The run script uses `-machine pc -device isa-kbd -display gtk` to ensure a PS/2 keyboard is present and captured.
- If you prefer headless, change `-display gtk` to `-display none`, but then keyboard input won’t reach the guest. Alternatively, add a curses runner.
- Serial output uses `-serial stdio`. The debug console is `-debugcon file:debugcon.log -global isa-debugcon.iobase=0xe9`.

**Troubleshooting**

- No serial output: ensure your terminal shows QEMU’s stdio; try `scripts/run-iso.sh` directly.
- Keyboard not working: verify the QEMU window is focused; the script uses `-device isa-kbd` with the default i8042 from `-machine pc`.
- Exceptions: the handler logs and halts to avoid floods. See “Debugging Aids” below for what gets printed and how to inspect the persistent trap record.

**Debugging Aids**

- Exception logs include: `VEC`, `ERR`, `EIP`, `CS`, `EFL`, and always `SS`, `DS`, `CR0`, `CR3`, `CR4`.
- #PF page faults: logs `CR2` (fault address) and decodes error bits (P/W/U).
- #GP general protection: decodes error code into `SEL`, `IDX`, and flags (Ext/IDT/GDT/LDT).
- #UD invalid opcode: dumps 16 bytes at `EIP` and at `EIP-8` to identify the faulting instruction.
- Persistent record: the last exception context is stored at physical `0x0009F000` (identity mapped). In the QEMU monitor, run `xp /9wx 0x9f000` to read: magic, vec, err, eip, cs, eflags, uesp, uss, cr2.
- Pre‑iret trace: just before dropping to ring 3 the kernel logs the exact `EIP/CS/ESP/SS` it will iret to.

**Current Limitations**

- Demo userland is a tiny in‑memory blob; there’s no loader yet.
- Syscalls and a scheduler are not implemented (int 0x80 is stubbed).
- No file system; no process isolation beyond basic paging setup.
- VGA is mapped writable to user for the demo (not secure; temporary).

**Next Steps**

- Shell: add `help`, `clear`, `reboot`, basic command table, and Shift/caps handling.
- Syscalls: honor `fd` in `write` (e.g., 1=stdout, 2=stderr), basic error returns.
- Minimal userland: a small user CRT and a Zig “hello” that uses `write`/`exit` instead of poking VGA.
- ELF32 loader: map PT_LOAD segments of a single static binary bundled in the ISO (simple initrd blob).
- Scheduling: PIT‑driven round‑robin for a few user tasks; save/restore user regs on preemption.
- Memory management: a kernel heap (bump/arena) and a physical frame allocator to support new mappings; grow user stack with guard pages.
- Isolation and hygiene: proper TSS I/O map (block user I/O), separate user/kernel virtual regions, and optional “higher‑half” kernel.
- Polishing: VGA panic screen and clearer panic/assert helpers; serial write paths safe in IRQ/syscall context.

**Roadmap To “Run Simple Userland Programs”**

1) Ring‑3 bring‑up: stable iret, diagnostics, SSE enable. ✅
2) Syscalls (int 0x80) and tiny user CRT to call `write`/`exit`.
3) Minimal ELF32 loader; embed a `hello` user binary in the ISO.
4) Simple scheduler (PIT‑based) for 2–3 user tasks.
5) Kernel heap + frame allocator to support more mappings.

With these in place, PanicOS meets the core goal and can run small userland programs alongside the kernel.
