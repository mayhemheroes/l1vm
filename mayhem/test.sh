#!/usr/bin/env bash
# l1vm/mayhem/test.sh — GOLDEN / known-answer oracle for koder77/l1vm.
#
# l1vm ships NO unit-test suite and NO in-tree example programs (the upstream `prog/*.l1com`
# samples are a SEPARATE network download, deliberately off-limits here). So this oracle is fully
# self-contained: it assembles tiny hand-written `.l1asm` programs (mayhem/testdata/*.l1asm) with
# the in-tree assembler `l1asm`, runs the resulting `.l1obj` under the NO-JIT VM, and DIFFs the
# program's stdout against a committed golden file (mayhem/testdata/golden/<name>.out).
#
# Both binaries are rebuilt INDEPENDENTLY here with the project's NORMAL flags (NOT the sanitizer/
# fuzz build that mayhem/build.sh produces) so the oracle exercises the real shipped behavior and
# does not false-fail on benign UB that the fuzz build's UBSan would halt on.
#
# The cases assert EXACT computed stdout, not merely "exited 0":
#   * print_int — loads the constant 42 from .data (loada) and PRINTI's it  -> "42\n"
#   * add_int   — loads 40 and 2, addi's them, PRINTI's the sum             -> "42\n"
# Each case exercises the object loader (vm/load-object.c), the data section, the loada opcode and
# the intr0 print/exit interrupts (vm/main.c). A no-op / exit(0) "patch", or any change that breaks
# data loading, arithmetic, or the print interrupts, yields empty or mismatched stdout and FAILS.
# The VM is run with `-q` (silent) so only the program's own output reaches stdout; goldens were
# captured from this freshly-built binary and verified byte-stable across repeated runs.
set -uo pipefail

# clang/gcc reject SOURCE_DATE_EPOCH='' (empty); must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"

# SRC is /mayhem in the commit image; default to this checkout's repo root so the suite also runs
# straight from a developer checkout (mayhem/ is one level below the repo root).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${SRC:=$(cd "$HERE/.." && pwd)}"
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

TESTDATA="$SRC/mayhem/testdata"
GOLDEN="$TESTDATA/golden"
[ -d "$GOLDEN" ] || { echo "missing golden dir $GOLDEN — wrong tree?" >&2; emit_ctrf "l1vm-golden" 0 1; exit 2; }
[ -f "$SRC/assemb/main.c" ] || { echo "missing assembler source $SRC/assemb — wrong tree?" >&2; emit_ctrf "l1vm-golden" 0 1; exit 2; }

: "${CC:=cc}"
export CC

# Build the assembler (l1asm) and the no-JIT VM with NORMAL flags (per assemb/make.sh and
# vm/make-nojit.sh), staged to private paths so the oracle is independent of mayhem/build.sh output.
ASM="$SRC/l1asm-test"
VM="$SRC/l1vm-nojit-test"
VM_LIBS=( -lm -ldl -lpthread -Wl,--export-dynamic )

"$CC" -w \
  "$SRC/assemb/main.c" "$SRC/lib-func/file.c" "$SRC/vm/modules/file/file-sandbox.c" \
  "$SRC/assemb/checkd.c" "$SRC/lib-func/string.c" "$SRC/lib-func/code_datasize.c" \
  -o "$ASM" -O1 >/tmp/l1vm-test-asm.log 2>&1 || {
    echo "test.sh: normal-flags assembler build failed:" >&2; tail -40 /tmp/l1vm-test-asm.log >&2
    emit_ctrf "l1vm-golden" 0 1; exit 2
  }

"$CC" -w \
  "$SRC/vm/main.c" "$SRC/vm/load-object.c" "$SRC/vm/debugger.c" \
  "$SRC/lib-func/string.c" "$SRC/lib-func/code_datasize.c" "$SRC/lib-func/memory_bounds.c" \
  -o "$VM" "${VM_LIBS[@]}" -O1 >/tmp/l1vm-test-vm.log 2>&1 || {
    echo "test.sh: normal-flags VM build failed:" >&2; tail -40 /tmp/l1vm-test-vm.log >&2
    emit_ctrf "l1vm-golden" 0 1; exit 2
  }
[ -x "$ASM" ] && [ -x "$VM" ] || { echo "test.sh: build produced no l1asm/l1vm binary" >&2; emit_ctrf "l1vm-golden" 0 1; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

passed=0; failed=0

# run_case <name>
# Assembles mayhem/testdata/<name>.l1asm -> <name>.l1obj, runs it under the no-JIT VM (-q), and
# diffs the program's stdout against mayhem/testdata/golden/<name>.out. The program MUST assemble,
# exit 0, AND match the golden byte-for-byte, else the case fails.
run_case() {
  local name="$1"
  local src="$TESTDATA/$name.l1asm" gold="$GOLDEN/$name.out"
  local got="$WORK/$name.out" err="$WORK/$name.err" rc

  if [ ! -f "$src" ];  then echo "FAIL $name: missing source $src" >&2;  failed=$((failed+1)); return; fi
  if [ ! -f "$gold" ]; then echo "FAIL $name: missing golden $gold" >&2; failed=$((failed+1)); return; fi

  # l1asm appends .l1obj to the basename; assemble inside $WORK so we never touch the source tree.
  cp -f "$src" "$WORK/$name.l1asm"
  if ! ( cd "$WORK" && "$ASM" "$name" >"$err.asm" 2>&1 ); then
    echo "FAIL $name: assembly failed" >&2; sed 's/^/    /' "$err.asm" >&2
    failed=$((failed+1)); return
  fi
  if [ ! -s "$WORK/$name.l1obj" ]; then
    echo "FAIL $name: assembler produced no .l1obj" >&2; failed=$((failed+1)); return
  fi

  "$VM" "$WORK/$name" -q > "$got" 2>"$err"; rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "FAIL $name: VM exited $rc (expected 0)" >&2; sed 's/^/    /' "$err" >&2
    failed=$((failed+1)); return
  fi
  if diff -u "$gold" "$got" > "$WORK/$name.diff" 2>&1; then
    echo "PASS $name"; passed=$((passed+1))
  else
    echo "FAIL $name: stdout differs from golden" >&2
    head -20 "$WORK/$name.diff" | sed 's/^/    /' >&2
    failed=$((failed+1))
  fi
}

run_case print_int
run_case add_int

emit_ctrf "l1vm-golden" "$passed" "$failed"
