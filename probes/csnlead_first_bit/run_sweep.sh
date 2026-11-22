#!/usr/bin/env bash
# owner-check: one-off probe runner for the CSNLEAD first-bit bench; the SPI
# fork has no bench of its own, and the xheep_spi probes keep only tb_fullcyc.
#
# Builds tb_csnlead against the tip RTL copy and the fix RTL copy, then runs
# the CPHA=0 FIRSTBIT sweep and the CPHA=1 and FULLCYC=1 controls on both,
# one job at a time. Prints one line per run, prefixed with the variant, and
# keeps each run's full log under RUN_DIR.
# A failed build, a nonzero simulator exit or a missing RESULT line makes the
# final status nonzero; the other runs still go ahead.
#
# Usage: run_sweep.sh BENCH_DIR RUN_DIR   (RUN_DIR must not exist yet)
set -uo pipefail

bench_dir=${1:?usage: run_sweep.sh BENCH_DIR RUN_DIR}
run_dir=${2:?usage: run_sweep.sh BENCH_DIR RUN_DIR}
stub_dir="$bench_dir/probes/fullcyc_cpha1"
first_failure=0

mkdir "$run_dir" || exit 1

# Runs one simulation and prints its RESULT line with the variant prefix.
# Arguments: variant name, simulator binary, plusargs.
run_case() {
  local variant=$1
  local sim_binary=$2
  shift 2
  local run_log
  local sim_status
  run_log="$run_dir/${variant}_$(printf '%s' "$*" | tr ' +=' '_..').log"
  "$sim_binary" "$@" > "$run_log" 2>&1
  sim_status=$?
  if [[ $sim_status -ne 0 ]] || ! grep -q '^RESULT' "$run_log"; then
    echo "$variant RUN_ERROR status=$sim_status args=$* log=$run_log"
    first_failure=1
  else
    echo "$variant $(grep '^RESULT' "$run_log")"
  fi
}

for variant in tip fix; do
  obj_dir="$run_dir/obj_$variant"
  rtl_dir="$bench_dir/$variant"
  sim_binary="$obj_dir/Vtb_csnlead"
  if ! verilator --binary -j 1 --timing -Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-PINCONNECTEMPTY \
      -I"$stub_dir/stub_include" --top-module tb_csnlead --Mdir "$obj_dir" \
      "$stub_dir/stubs.sv" "$rtl_dir/spi_host_cmd_pkg.sv" "$rtl_dir/spi_host_fsm.sv" \
      "$rtl_dir/spi_host_shift_register.sv" "$bench_dir/tb_csnlead.sv" > "$run_dir/build_$variant.log" 2>&1; then
    echo "$variant BUILD_FAIL log=$run_dir/build_$variant.log"
    first_failure=1
    continue
  fi
  for csnlead in 0 1 3; do
    for first_bit in 0 4 8 12 16 20 24 28 32 36 40 48; do
      run_case "$variant" "$sim_binary" +CPHA=0 +CSNLEAD="$csnlead" +FIRSTBIT="$first_bit"
    done
  done
  for csnlead in 0 3; do
    run_case "$variant" "$sim_binary" +CPHA=1 +CSNLEAD="$csnlead"
    run_case "$variant" "$sim_binary" +CPHA=0 +FULLCYC=1 +CSNLEAD="$csnlead"
    run_case "$variant" "$sim_binary" +CPHA=1 +FULLCYC=1 +CSNLEAD="$csnlead"
  done
done
exit "$first_failure"
