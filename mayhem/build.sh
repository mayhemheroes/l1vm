#!/usr/bin/env bash
#
# l1vm/mayhem/build.sh — build the L1VM (no-JIT) as the file-input fuzz target, plus the l1asm
# assembler used to generate a valid .l1obj seed.
#
# l1vm is a small 64-bit register VM in C. The fuzz surface is the VM LOADING and RUNNING an
# attacker-controlled bytecode object: `l1vm-nojit <name>` opens `<name>.l1obj`, parses the object
# header / code / data sections (vm/load-object.c), then executes the opcode stream (vm/main.c).
# We build the NO-JIT variant (vm/jit.h already sets JIT_COMPILER 0) so there is no asmjit / C++
# dependency — a plain C compile of the VM + lib-func helpers, exactly as vm/make-nojit.sh documents
# (-lm -ldl -lpthread, --export-dynamic for module dlopen). No SDL/optional modules are built; the
# loader+VM core is self-contained.
#
# The Mayhem target is FILE-INPUT (CLI), not a libFuzzer harness — the VM binary IS the reproducer
# (it takes one input file and runs it, crashing naturally). So there is no separate libFuzzer/
# standalone link step; /mayhem/l1vm-nojit serves as both the fuzz target and the standalone repro.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# Build knobs from the ENV, overridable. SANITIZER_FLAGS uses `=` (not `:=`) so an explicit empty
# value (--build-arg SANITIZER_FLAGS=) is honored → no-sanitizer build (the VM's natural crash).
# The VM links -lm/-ldl/-lpthread explicitly, so the empty-sanitizer build links cleanly too.
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g}"
# DWARF debug info — INDEPENDENT of the sanitizer off-switch, so an empty SANITIZER_FLAGS still
# yields a debuggable reproducer. clang-19's plain `-g` emits DWARF-5, which Mayhem's triage cannot
# read, so be EXPLICIT: `-gdwarf-3` (DWARF ≤ 3, SPEC §6.2 item 10). Threaded AFTER $SANITIZER_FLAGS
# below so its -gdwarf-3 overrides the -g the sanitizer flags carry. Default with `=` (not `:=`) so
# an explicit empty `--build-arg DEBUG_FLAGS=` is honored.
: "${DEBUG_FLAGS=-g -gdwarf-3}"
: "${CC:=clang}"
: "${MAYHEM_JOBS:=$(nproc)}"
export SANITIZER_FLAGS DEBUG_FLAGS CC MAYHEM_JOBS

cd "$SRC"

# Common link libs for the VM (per vm/make-nojit.sh): libm, libdl (module dlopen), pthread, and
# --export-dynamic so dynamically loaded modules can resolve VM symbols.
VM_LIBS="-lm -ldl -lpthread -Wl,--export-dynamic"
VM_WARN="-Wall -Wextra -Wno-unused-parameter -Wno-unused-variable -Wno-unused-but-set-variable"

# ---------------------------------------------------------------------------
# (1) FUZZ TARGET — the no-JIT VM, the PROJECT itself compiled WITH $SANITIZER_FLAGS so the loaded/
#     executed bytecode path is instrumented (ASan+UBSan, halting, by default). This is the
#     file-input Mayhem target at /mayhem/l1vm-nojit (also serves as the standalone reproducer).
# ---------------------------------------------------------------------------
( cd vm
  $CC $VM_WARN $SANITIZER_FLAGS $DEBUG_FLAGS \
      main.c load-object.c debugger.c \
      ../lib-func/string.c ../lib-func/code_datasize.c ../lib-func/memory_bounds.c \
      -o /mayhem/l1vm-nojit \
      $VM_LIBS -O1 -fomit-frame-pointer
)

# ---------------------------------------------------------------------------
# (2) ASSEMBLER — l1asm, built with NORMAL flags (not for fuzzing). Used below only to produce a
#     valid .l1obj seed from a tiny program, so the fuzzer/standalone start from a real object file
#     the loader fully parses. (Per assemb/make.sh.)
# ---------------------------------------------------------------------------
( cd assemb
  $CC -Wall -Wno-unused-variable \
      main.c ../lib-func/file.c ../vm/modules/file/file-sandbox.c checkd.c \
      ../lib-func/string.c ../lib-func/code_datasize.c \
      -o /tmp/l1asm -O1 -g
)

# ---------------------------------------------------------------------------
# (3) SEED — assemble a minimal valid program into mayhem/testsuite/minimal.l1obj. The program does
#     `intr0 255 0 0 0` (program-exit with retcode regi[0]=0): a clean run that exercises the full
#     load_object() parser (header, code section, data-info table, "infodata" trailer) AND the VM
#     dispatch loop to a normal EXIT. l1asm appends .l1obj to the basename. Only regenerate if the
#     committed seed isn't present (the seed is checked into mayhem/testsuite/).
# ---------------------------------------------------------------------------
mkdir -p "$SRC/mayhem/testsuite"
if [ ! -s "$SRC/mayhem/testsuite/minimal.l1obj" ]; then
  tmpd="$(mktemp -d)"
  cat > "$tmpd/minimal.l1asm" <<'L1ASM'
.data
.dend
.code
intr0 255 0 0 0
.cend
L1ASM
  ( cd "$tmpd" && /tmp/l1asm minimal >/dev/null 2>&1 || true )
  [ -s "$tmpd/minimal.l1obj" ] || { echo "build.sh: ERROR — l1asm did not produce a seed object" >&2; exit 1; }
  cp -f "$tmpd/minimal.l1obj" "$SRC/mayhem/testsuite/minimal.l1obj"
  rm -rf "$tmpd"
fi

echo "build.sh: built /mayhem/l1vm-nojit (sanitized file-input fuzz target + standalone reproducer)"
ls -l /mayhem/l1vm-nojit "$SRC/mayhem/testsuite/minimal.l1obj"
file /mayhem/l1vm-nojit 2>/dev/null || true
