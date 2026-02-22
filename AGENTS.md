Assistant Guide for PanicOS

Purpose
- Provide a fast-start guide for future sessions to understand, build, run, and safely modify PanicOS.
- Establish conventions: planning, tool usage, and mandatory README updates with verification steps after each change.

Quick Start
- Prereqs: `zig` (0.11+), `qemu-system-i386`, `grub2-mkrescue` or `grub-mkrescue`, `xorriso`, `ripgrep`.
- Build kernel: `zig build -Doptimize=ReleaseSmall -Dstrip=true`
- Build ISO (kernel + user apps): `scripts/mkiso.sh`
- Run ISO: `scripts/run-iso.sh`
- Shell basics: `help`, `ls|progs`, `run <name>`, `echo <text>`.

Repository Orientation
- Kernel sources: `src/*.zig`, `src/*.S`
- User apps: `user/apps/*.zig` (each exports `_start`)
- Syscalls: `int 0x80` implemented in `src/interrupts.S` and dispatched in `src/interrupts.zig`
- ELF loader: `src/elf.zig`
- Paging: `src/paging.zig`
- Shell: `src/shell.zig`
- Boot + toolchain: `build.zig`, `linker.ld`, `scripts/*`

Working Rules (Very Important)
- Plan: For multi-step tasks, use a short, clear plan and update it as you progress.
- Preamble: Before running commands, send a 1–2 sentence note describing what you’re about to do.
- Patches: Use `apply_patch` with minimal, targeted diffs; keep changes consistent with current style.
- Scope: Fix the problem at its root, avoid unrelated refactors or changes.
- Safety: Do not commit; do not add licenses; do not introduce network calls.
- Chunk reads: When viewing files, read max ~250 lines at a time.

Mandatory README Updates
- After every instruction you carry out (especially code changes), append to README.md under the Change Log:
  - What changed: short description.
  - Why: the issue or goal.
  - Files: list touched paths.
  - How to verify: exact commands to build/run/test behavior.
  - Date/time and your initials.
- For documentation-only updates, still add a Change Log entry and a verification note (e.g., “build succeeds; ISO rebuild ok”).

How to Verify Changes
- Build: `zig build -Doptimize=ReleaseSmall -Dstrip=true` (ensure success)
- ISO: `scripts/mkiso.sh` (ensure it produces `panicos.iso`)
- Boot smoke test: `scripts/run-iso.sh`, then in the shell:
  - `ls` shows expected programs
  - `run hello` prints “Hello from user via Zig!” and returns to shell
  - Repeat `run hello` to confirm stability
- Optional targeted checks:
  - If paging/loader touched: confirm repeated runs work; no #PF on second run
  - If syscalls touched: call `write`/`exit` from hello; inspect serial output

Common Task Playbooks
- Fix crash on second run:
  - Investigate `src/elf.zig` mappings and `src/paging.zig` teardown
  - Ensure user PT_LOAD pages use fresh physical frames
  - On exit, clear user PTEs and restore 0..12 MiB identity map (supervisor)
  - Update README Change Log with verification steps (build, ISO, repeated `run hello`)

- Add a new syscall:
  - Define number in `src/interrupts.zig` (SYS struct)
  - Implement logic in `syscall_dispatch_abi`
  - Add a wrapper in `user/lib/sys.zig`
  - Update README Change Log with how to test from a user app

- Add a new user app:
  - Create `user/apps/<name>.zig` exporting `_start`
  - Rebuild ISO; use shell `ls` then `run <name>`
  - Update README Change Log with the app name and test steps

Diagnostics
- Exceptions: `src/interrupts.zig` logs rich context; last record mirrored at phys 0x0009F000
- Serial log: `debugcon.log` (port 0xE9) and terminal output from QEMU

Etiquette
- Keep notes succinct; prefer actionable steps over prose.
- Always provide “How to verify” for any source change.

