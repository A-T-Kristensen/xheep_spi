#!/bin/bash
# owner-check: none — xheep_opentitan_spi_host has no lint target and its core needs lowrisc:prim cores it does not hold — this lints the real top spi_host over its full file list from the x-heep vendored dependencies
# Lints and elaborates the spi_host top of one RTL tree with Verilator -Wall,
# once with the repository waiver file and once without it (the census).
# --lint-only builds the whole hierarchy under --top-module, so an elaboration
# error shows here. Usage: lint_top.sh RTL_TREE LOG_PREFIX, where RTL_TREE holds
# rtl/ and lint/ of one revision. Prints one LINT line per run with the
# Verilator exit status, the warning count and the error count, and exits
# nonzero when Verilator reports an error in either run.
set -uo pipefail
tree_dir="$1"
log_prefix="$2"
vendor_dir=/home/andreas/gitlab_esl/x-heep/hw/vendor
prim_rtl="$vendor_dir/lowrisc/opentitan/hw/ip/prim/rtl"
prim_generic_rtl="$vendor_dir/lowrisc/opentitan/hw/ip/prim_generic/rtl"
reg_if="$vendor_dir/pulp_platform/register_interface"
common_cells_include="$vendor_dir/pulp_platform/common_cells/include"
flop_en_wrapper=/home/andreas/gitlab_esl/theshire/ai_ops/tmp/2026-11-19_xheep-fix-prs_150106/spi/lint_support/prim_flop_en.sv
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1

source_files=(
  "$prim_rtl/prim_util_pkg.sv"
  "$prim_rtl/prim_alert_pkg.sv"
  "$vendor_dir/lowrisc/opentitan/hw/top_earlgrey/rtl/top_pkg.sv"
  "$vendor_dir/lowrisc/opentitan/hw/ip/spi_device/rtl/spi_device_reg_pkg.sv"
  "$vendor_dir/lowrisc/opentitan/hw/ip/spi_device/rtl/spi_device_pkg.sv"
  "$reg_if/src/reg_intf.sv"
  "$tree_dir/rtl/spi_host_reg_pkg.sv"
  "$tree_dir/rtl/spi_host_cmd_pkg.sv"
  "$prim_generic_rtl/prim_generic_flop_en.sv"
  "$prim_generic_rtl/prim_generic_flop.sv"
  "$prim_generic_rtl/prim_generic_buf.sv"
  "$flop_en_wrapper"
  "$script_dir/prim_buf.sv"
  "$script_dir/prim_flop.sv"
  "$prim_rtl/prim_subreg_arb.sv"
  "$prim_rtl/prim_subreg.sv"
  "$prim_rtl/prim_subreg_ext.sv"
  "$prim_rtl/prim_fifo_sync.sv"
  "$prim_rtl/prim_packer_fifo.sv"
  "$prim_rtl/prim_intr_hw.sv"
  "$prim_rtl/prim_diff_decode.sv"
  "$prim_rtl/prim_alert_sender.sv"
  "$reg_if/src/reg_demux.sv"
  "$prim_generic_rtl/prim_generic_flop_2sync.sv"
  "$script_dir/prim_flop_2sync.sv"
  /home/andreas/gitlab_esl/x-heep/hw/core-v-mini-mcu/include/xheep_reg_pkg.sv
)
for rtl_name in spi_host_shift_register spi_host_byte_select spi_host_byte_merge spi_host_fsm \
  spi_host_core spi_host_command_queue spi_host_data_fifos spi_host_reg_top spi_host_window spi_host; do
  source_files+=("$tree_dir/rtl/$rtl_name.sv")
done
source_files+=("$script_dir/spi_host_lint_top.sv")

any_error=0

# Runs one lint pass; extra arguments (the waiver file) go before the sources.
run_lint() {
  local label="$1"
  shift
  local log_file="${log_prefix}_${label}.log"
  local lint_rc=0
  verilator --lint-only -Wall -Wno-fatal -j 1 -I"$prim_rtl" -I"$common_cells_include" -I"$reg_if/include" \
    --top-module spi_host_lint_top "$@" "${source_files[@]}" > "$log_file" 2>&1 || lint_rc=$?
  local warning_count error_count
  warning_count=$(grep -c '^%Warning' "$log_file") || true
  error_count=$(grep -c '^%Error' "$log_file") || true
  echo "LINT $label rc=$lint_rc warnings=$warning_count errors=$error_count log=$log_file"
  if [ "$lint_rc" -ne 0 ] || [ "$error_count" -ne 0 ]; then
    any_error=1
  fi
}

run_lint waivers "$tree_dir/lint/spi_host.vlt"
run_lint census
exit "$any_error"
