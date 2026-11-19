#!/bin/bash
# owner-check: none — xheep_spi has no lint target and the x-heep Makefile lints the whole MCU — this lints the one changed file
# Lints the xheep_spi SPI host state machine with Verilator, patched (this
# job's src/, the fix/spi-host-divider-reload worktree) and unpatched (the
# copy in the x-heep tree sent as with/x-heep, x-heep main 2e12b161), so the
# patch is judged by the warnings it adds, not by the vendor code's own.
# Includes come from the x-heep tree: the lowRISC prim macros and the pulp
# common_cells assertions header the file includes.
# Prints one LINT line per file with its status and warning count, then the
# diagnostics, and exits nonzero when Verilator could not run or the patched
# file has more warnings than the unpatched one.
set -uo pipefail

xheep_dir="$JOB_DIR/with/x-heep"
patched_rtl="$PWD/vendor/lowrisc_opentitan_spi_host/rtl"
unpatched_rtl="$xheep_dir/hw/vendor/xheep/spi/vendor/lowrisc_opentitan_spi_host/rtl"
prim_include="$xheep_dir/hw/vendor/lowrisc/opentitan/hw/ip/prim/rtl"
common_cells_include="$xheep_dir/hw/vendor/pulp_platform/common_cells/include"
prim_generic_rtl="$xheep_dir/hw/vendor/lowrisc/opentitan/hw/ip/prim_generic/rtl"
# The primgen wrapper the state machine instantiates, sent as with/lint_support.
prim_flop_en_wrapper="$JOB_DIR/with/lint_support/prim_flop_en.sv"

source "$JOB_DIR/env/openwifi-hw.sh" || exit 1
if ! command -v verilator >/dev/null 2>&1; then
  echo "ERROR verilator not on PATH"
  exit 1
fi
verilator --version

# Lints one state-machine file against the packages it imports (prim_util_pkg
# from the x-heep tree, the register and command packages beside it); prints the
# warning count on stdout and writes the diagnostics to the given log.
lint_fsm() {
  local rtl_dir="$1"
  local log_file="$2"
  local lint_rc=0
  verilator --lint-only -Wall -j 1 -I"$prim_include" -I"$common_cells_include" \
    --top-module spi_host_fsm "$prim_include/prim_util_pkg.sv" "$rtl_dir/spi_host_reg_pkg.sv" \
    "$prim_generic_rtl/prim_generic_flop_en.sv" "$prim_flop_en_wrapper" \
    "$rtl_dir/spi_host_cmd_pkg.sv" "$rtl_dir/spi_host_fsm.sv" \
    > "$log_file" 2>&1 || lint_rc=$?
  echo "$lint_rc $(grep -c '^%Warning' "$log_file")"
}

read -r patched_rc patched_warnings < <(lint_fsm "$patched_rtl" "$JOB_DIR/lint_patched.log")
read -r unpatched_rc unpatched_warnings < <(lint_fsm "$unpatched_rtl" "$JOB_DIR/lint_unpatched.log")
echo "LINT patched rc=$patched_rc warnings=$patched_warnings"
echo "LINT unpatched rc=$unpatched_rc warnings=$unpatched_warnings"
echo "== patched diagnostics"
grep -e '^%' "$JOB_DIR/lint_patched.log" | head -40
echo "== unpatched diagnostics"
grep -e '^%' "$JOB_DIR/lint_unpatched.log" | head -40

if grep -q -e '^%Error' "$JOB_DIR/lint_patched.log" "$JOB_DIR/lint_unpatched.log"; then
  echo "VERDICT ERROR: Verilator reported errors"
  exit 1
fi
if [[ $patched_warnings -gt $unpatched_warnings ]]; then
  echo "VERDICT the patch adds warnings"
  exit 1
fi
echo "VERDICT the patch adds no warnings"
