#!/bin/bash
# owner-check: probes/spi_host_top_lint/lint_top.sh — read it on xheep_spi wip/xheep-fix-prs — it always passes -Wno-fatal and uses laptop paths; this job adds the warnings-fatal passes over the same file list inside a sent bundle
# Usage: job_fatal_lint.sh TREE...   (each TREE is a folder trees/TREE/ with rtl/ and lint/)
# Lints the full spi_host top of each named RTL tree, for example main 91acf0f3
# and a PR tip, with Verilator -Wall in three passes each:
#   fatal_waivers  warnings fatal, with the repository waiver file lint/spi_host.vlt
#   fatal_census   warnings fatal, without the waiver file
#   census         warnings non-fatal, without the waiver file (the earlier census)
# Prints one LINT line per pass with the Verilator exit status, the warning and
# error counts and the warning classes. A nonzero Verilator status is the
# measured result, not a job failure. The job exits nonzero only when no
# tree is named, a named tree is missing, Verilator is missing or a pass
# wrote no Verilator output. Run from the
# bundle root; each pass truncates its own log, so no earlier result remains.
set -uo pipefail
# On an EPFL host, Verilator 5.040 (the laptop's version) is under /softs.
server_verilator_dir=/softs/verilator/v5.040/bin
if [ -x "$server_verilator_dir/verilator" ]; then
  PATH="$server_verilator_dir:$PATH"
fi
bundle_dir="$(pwd)"
vendor_dir="$bundle_dir/vendor"
prim_rtl="$vendor_dir/lowrisc/opentitan/hw/ip/prim/rtl"
prim_generic_rtl="$vendor_dir/lowrisc/opentitan/hw/ip/prim_generic/rtl"
reg_if="$vendor_dir/pulp_platform/register_interface"
common_cells_include="$vendor_dir/pulp_platform/common_cells/include"
harness_dir="$bundle_dir/harness"
job_failed=0

if ! command -v verilator > /dev/null 2>&1; then
  echo "ERROR: verilator is not on PATH"
  exit 2
fi
echo "VERILATOR $(verilator --version)"

# Runs the three passes over one RTL tree under trees/<name>/.
run_tree() {
  local tree_name="$1"
  local tree_dir="$bundle_dir/trees/$tree_name"
  local source_files=(
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
    "$harness_dir/prim_flop_en.sv"
    "$harness_dir/prim_buf.sv"
    "$harness_dir/prim_flop.sv"
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
    "$harness_dir/prim_flop_2sync.sv"
    "$bundle_dir/xheep_include/xheep_reg_pkg.sv"
  )
  local rtl_name
  for rtl_name in spi_host_shift_register spi_host_byte_select spi_host_byte_merge spi_host_fsm \
    spi_host_core spi_host_command_queue spi_host_data_fifos spi_host_reg_top spi_host_window spi_host; do
    source_files+=("$tree_dir/rtl/$rtl_name.sv")
  done
  source_files+=("$harness_dir/spi_host_lint_top.sv")

  local pass_name log_file lint_rc warning_count error_count class_counts
  local extra_args
  for pass_name in fatal_waivers fatal_census census; do
    extra_args=()
    if [ "$pass_name" = census ]; then
      extra_args+=(-Wno-fatal)
    fi
    if [ "$pass_name" = fatal_waivers ]; then
      extra_args+=("$tree_dir/lint/spi_host.vlt")
    fi
    log_file="$bundle_dir/out_${tree_name}_${pass_name}.log"
    lint_rc=0
    verilator --lint-only -Wall -j 1 -I"$prim_rtl" -I"$common_cells_include" -I"$reg_if/include" \
      --top-module spi_host_lint_top "${extra_args[@]}" "${source_files[@]}" > "$log_file" 2>&1 \
      || lint_rc=$?
    if [ ! -s "$log_file" ] && [ "$lint_rc" -ne 0 ]; then
      echo "ERROR: $tree_name $pass_name rc=$lint_rc wrote no output"
      job_failed=1
      continue
    fi
    warning_count=$(grep -c '^%Warning' "$log_file") || true
    error_count=$(grep -c '^%Error' "$log_file") || true
    class_counts=$(grep -o '^%Warning-[A-Z0-9_]*' "$log_file" | sort | uniq -c \
      | awk '{ printf "%s:%s ", substr($2, 10), $1 }') || true
    echo "LINT $tree_name $pass_name rc=$lint_rc warnings=$warning_count errors=$error_count classes=$class_counts"
  done
}

tree_names=("$@")
if [ "${#tree_names[@]}" -eq 0 ]; then
  echo "ERROR: name at least one tree under trees/, for example 91acf0f3"
  exit 2
fi
for tree_name in "${tree_names[@]}"; do
  if [ ! -d "$bundle_dir/trees/$tree_name/rtl" ]; then
    echo "ERROR: trees/$tree_name/rtl does not exist"
    job_failed=1
    continue
  fi
  run_tree "$tree_name"
done
exit "$job_failed"
