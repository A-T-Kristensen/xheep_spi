#!/bin/bash
# Proves two renamed copies of spi_host_fsm equivalent with Yosys equiv_make,
# which pairs the registers of the two copies by name, then equiv_simple and
# equiv_induct over the paired state. Both copies have the same registers, so
# a pass means that every output and every paired register gets the same next
# value from every common state.
# Usage: equiv_pair.sh GOLD_MODULE GATE_MODULE
#   The files are work_dir/GOLD_MODULE.sv and work_dir/GATE_MODULE.sv.
# Prints PROVEN, NOT PROVEN (with the unproven count) or ERROR. Exit status:
# 0 proven, 1 not proven, 2 the run could not decide (Yosys error, timeout).
set -uo pipefail
if [[ $# -ne 2 ]]; then
  echo "usage: $0 GOLD_MODULE GATE_MODULE" >&2
  exit 2
fi
gold_module="$1"
gate_module="$2"
script_dir="$(dirname "$(readlink -f "$0")")"
work_dir="$script_dir/w"
xheep_dir=/home/andreas/gitlab_esl/x-heep
prim_include="$xheep_dir/hw/vendor/lowrisc/opentitan/hw/ip/prim/rtl"
common_cells_include="$xheep_dir/hw/vendor/pulp_platform/common_cells/include"
prim_generic_rtl="$xheep_dir/hw/vendor/lowrisc/opentitan/hw/ip/prim_generic/rtl"
# One log per run, so an earlier verdict cannot be read as this run's.
log_file="$work_dir/equiv_${gold_module}_vs_${gate_module}_$(date +%Y%m%dT%H%M%S).log"
yosys_rc=0
# Yosys ends a command at a newline, so read_slang stays on one line.
# read_slang already gives one flat module per top. A flatten here would keep
# only one of the two tops, and equiv_make would then find no gold module.
timeout 600 yosys -l "$log_file" -q -m slang -p "
  read_slang -I$prim_include -I$common_cells_include $prim_include/prim_util_pkg.sv $script_dir/spi_host_reg_pkg.sv $script_dir/spi_host_cmd_pkg.sv $prim_generic_rtl/prim_generic_flop_en.sv $script_dir/prim_flop_en.sv $work_dir/$gold_module.sv $work_dir/$gate_module.sv --top $gold_module --top $gate_module;
  proc; opt_clean; async2sync;
  equiv_make $gold_module $gate_module equiv_top;
  hierarchy -top equiv_top;
  equiv_simple -seq 5;
  equiv_induct -seq 5;
  equiv_status" > /dev/null 2>&1 || yosys_rc=$?
echo "yosys rc=$yosys_rc"
grep -a -E 'Found [0-9]+ \$equiv cells|unproven \$equiv cells|Equivalence successfully proven|ERROR' "$log_file" | tail -4
if [[ $yosys_rc -ne 0 ]]; then
  echo "ERROR $gold_module $gate_module: yosys did not finish (status $yosys_rc)"
  exit 2
fi
if grep -q -a 'Equivalence successfully proven' "$log_file"; then
  echo "PROVEN $gold_module $gate_module"
  exit 0
fi
if grep -q -a -E 'unproven \$equiv cells' "$log_file"; then
  echo "NOT PROVEN $gold_module $gate_module"
  exit 1
fi
echo "ERROR $gold_module $gate_module: equiv_status printed no verdict"
exit 2
