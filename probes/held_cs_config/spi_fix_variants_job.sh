#!/bin/bash
# owner-check: openwifi-hw make lanes and offload.sh run — read spi_port_variants_job.sh, the job this copies — it hardcodes the neg and port variants; this job adds the held chip-select fix as a third variant through the same two lanes
# Runs the openwifi-hw SPI host digital-behaviour bench (xsim) on three state
# machine variants, each replacing chs_spi_host_fsm.sv in a copy of the
# Theshire source manifest:
#   neg   the unchanged x-heep fork FSM (xheep_spi main 35c6e5f), the control
#   port  the same FSM with OpenTitan aff83558d0 ported onto it
#         (xheep_opentitan_spi_host 2c87836, module prefix renamed)
#   fix   the port plus the held chip-select config_changed condition
#         (xheep_opentitan_spi_host c33deae, module prefix renamed)
# The bench has no held chip-select command that changes the configuration,
# so the fix lanes check that the fix changes nothing else this bench covers.
# Each variant runs two lanes:
#   all    the full case: every scenario, SPI modes 0 to 3 (CPHA=1 in modes 1
#          and 3) against the bench model, and the idle relaunch lead check
#   trail  the held_cs_switch_trail case: the WaitTrail time after a held
#          chip select that a command for another chip select ends
# Grades each lane on its xsim transcript, since xsim's exit status is not the
# bench verdict: detected (its fail signature and no PASS line), pass (the
# PASS line, no fail signature and make exit 0) or ERROR (anything else, or a
# reachability fatal in the trail lane).
# Expected: neg detected in both lanes, port and fix pass in both lanes (the
# port passed both on 2026-11-22, job spi_port_aff8).
# Prints one LANE line per lane, and exits nonzero when generation or the
# source check fails, or when a lane verdict differs from its expectation.
set -uo pipefail

variant_root="$JOB_DIR/with/spi_variants"
board_dir="$PWD/boards/zcu104_fmcs2"
theshire_dir="$JOB_DIR/with/theshire"
manifest="$board_dir/rtl/theshire_manifest/theshire_sources.list"
probe_dir="$JOB_DIR/with/probe"
probe_bench="boards/zcu104_fmcs2/verification/rtl/theshire/tb/hdl/chs_spi_host_digital_behavior_tb.sv"
variants=(neg port fix)
lanes=(all trail)
declare -A lane_target=([all]=sim-chs-spi-host-digital-behavior-xsim [trail]=sim-chs-spi-host-held-cs-switch-trail-xsim)
declare -A pass_signature=([all]='CHS_SPI_HOST_DIGITAL PASS all' [trail]='CHS_SPI_HOST_DIGITAL PASS held_cs_switch_trail')
declare -A fail_signature=([all]='CS lead too short' [trail]='WaitTrail after IdleCSBActive too short')
declare -A expected=([neg__all]=detected [neg__trail]=detected [port__all]=pass [port__trail]=pass [fix__all]=pass [fix__trail]=pass)
reach_signatures=('no WaitTrail directly after IdleCSBActive' 'SecondCs not held in IdleCSBActive' 'CS trail too short')
declare -A lane_pid
overall_rc=0

echo "PHASE generate"
(
  source "$JOB_DIR/env/theshire.sh" || exit 1
  make -C "$theshire_dir" CHS_BUILD_JOBS=4 fusesoc-setup-zcu104-wrapper-manifest
) > "$JOB_DIR/generate.log" 2>&1
generate_rc=$?
echo "generate_rc=$generate_rc"
tail -5 "$JOB_DIR/generate.log"
if [[ $generate_rc -ne 0 ]]; then
  overall_rc=1
fi

source "$JOB_DIR/env/openwifi-hw.sh" || exit 1

echo "PHASE source_check"
for variant in "${variants[@]}"; do
  sed -e "s#^\$THESHIRE_DIR/hw/ip/spi_host/rtl/chs_spi_host_fsm.sv\$#$variant_root/$variant/chs_spi_host_fsm.sv#" \
    "$manifest" > "$JOB_DIR/tmp/sources_$variant.list"
  if ! grep -q -F "$variant_root/$variant/chs_spi_host_fsm.sv" "$JOB_DIR/tmp/sources_$variant.list"; then
    echo "LANE $variant ERROR manifest line not replaced"
    exit 1
  fi
done
missing_count=0
while IFS= read -r source_line || [[ -n "$source_line" ]]; do
  case "$source_line" in
    ''|'#'*) continue ;;
  esac
  source_path="${source_line//\$THESHIRE_DIR/$theshire_dir}"
  if [[ ! -e "$source_path" ]]; then
    missing_count=$((missing_count + 1))
    if [[ $missing_count -le 20 ]]; then
      echo "MISSING $source_path"
    fi
  fi
done < "$JOB_DIR/tmp/sources_port.list"
echo "missing_sources=$missing_count"
if [[ $missing_count -ne 0 ]]; then
  overall_rc=1
fi

echo "PHASE probe_install"
if [[ ! -f "$probe_dir/$probe_bench" || ! -f "$probe_dir/held_cs_switch_trail_lane.mk" ]]; then
  echo "ERROR probe files missing under $probe_dir"
  exit 1
fi
cp -- "$probe_dir/$probe_bench" "$PWD/$probe_bench" || exit 1
cat -- "$probe_dir/held_cs_switch_trail_lane.mk" >> "$board_dir/scripts/make/verify/simulation/components.mk" || exit 1

# Prints the path of the lane's xsim transcript, or nothing when it is absent.
lane_xsim_log() {
  local lane_key="$1"
  find "$JOB_DIR/scratch/verify_$lane_key/xsim" -name 'xsim_chs_spi_host_digital_behavior_tb.log' 2>/dev/null | head -1
}

# Prints 1 when the fixed string is in the lane's xsim transcript, else 0.
# Only the transcript is searched: the scratch tree also holds the compiled
# snapshot, which contains every fatal message text of the bench.
lane_has() {
  local lane_key="$1"
  local signature="$2"
  local xsim_log
  xsim_log="$(lane_xsim_log "$lane_key")"
  if [[ -n "$xsim_log" ]] && grep -q -a -F -e "$signature" "$xsim_log"; then
    echo 1
  else
    echo 0
  fi
}

echo "PHASE lanes"
for variant in "${variants[@]}"; do
  for lane_name in "${lanes[@]}"; do
    lane_key="${variant}__${lane_name}"
    make -C "$board_dir" JOBS=1 "${lane_target[$lane_name]}" \
      THESHIRE_DIR="$theshire_dir" \
      THESHIRE_SOURCES_LIST="$JOB_DIR/tmp/sources_$variant.list" \
      VERIFY_TMP_ROOT="$JOB_DIR/scratch/verify_$lane_key" \
      > "$JOB_DIR/lane_$lane_key.log" 2>&1 &
    lane_pid["$lane_key"]=$!
  done
done

for variant in "${variants[@]}"; do
  for lane_name in "${lanes[@]}"; do
    lane_key="${variant}__${lane_name}"
    make_rc=0
    wait "${lane_pid[$lane_key]}" || make_rc=$?
    has_pass="$(lane_has "$lane_key" "${pass_signature[$lane_name]}")"
    has_fail="$(lane_has "$lane_key" "${fail_signature[$lane_name]}")"
    has_reach=0
    if [[ $lane_name == trail ]]; then
      for reach_signature in "${reach_signatures[@]}"; do
        if [[ $(lane_has "$lane_key" "$reach_signature") -eq 1 ]]; then
          has_reach=1
        fi
      done
    fi
    if [[ $has_reach -eq 1 ]]; then
      verdict=ERROR
    elif [[ $has_fail -eq 1 && $has_pass -eq 0 ]]; then
      verdict=detected
    elif [[ $has_pass -eq 1 && $has_fail -eq 0 && $make_rc -eq 0 ]]; then
      verdict=pass
    else
      verdict=ERROR
    fi
    if [[ $verdict == ERROR ]]; then
      overall_rc=1
    elif [[ ${expected[$lane_key]} != reported && $verdict != "${expected[$lane_key]}" ]]; then
      overall_rc=1
    fi
    echo "LANE $lane_key expected=${expected[$lane_key]} verdict=$verdict make_rc=$make_rc pass_line=$has_pass fail_line=$has_fail reach_fatal=$has_reach"
    xsim_log="$(lane_xsim_log "$lane_key")"
    if [[ -n "$xsim_log" ]]; then
      grep -a -e 'PASS' -e 'Fatal' -e 'FATAL' -e 'TRAIL' -e 'too short' "$xsim_log" | cut -c1-300 | sort -u | head -30
    else
      echo "  no xsim transcript under $JOB_DIR/scratch/verify_$lane_key"
      tail -5 "$JOB_DIR/lane_$lane_key.log"
    fi
  done
done
exit "$overall_rc"
