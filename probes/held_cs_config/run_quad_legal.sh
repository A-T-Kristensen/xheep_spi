#!/bin/bash
# owner-check: compare_head_fix.py — read its matrix and grader — it runs bidirectional commands only (DIR default 3) and grades on wr_en, so it cannot check legal Quad reads or writes
# Runs the held-CS bench (tb.sv) over legal Quad commands: Quad read (DIR=1)
# and Quad write (DIR=2), modes 0-4, CPHA and CPHA2 0/1, divider pairs
# (1,1) (3,3) (1,3) and LEN 0/2, on two builds: MAIN_SIM (the FSM of main) and
# TIP_SIM (the FSM of the PR tip). Usage: run_quad_legal.sh MAIN_SIM TIP_SIM OUT_TSV
# Build each with: verilator --binary --timing -j 1 -Wno-fatal -Wno-lint
#   -Wno-style -Iinc --top-module tb --Mdir obj_X -o sim_X stubs.sv
#   spi_host_cmd_pkg.sv X/fsm_main.sv tb.sv
# where X/fsm_main.sv is the FSM with its module renamed to fsm_main.
# Grades each row on the tip: pass when the totals give exactly 2*(LEN+1)
# strobes in the command direction and none in the other, two last strobes in
# that direction and, in rows that change the configuration on a held chip
# select (MODE 2 or 4 with CPHA2 != CPHA or CLKDIV2 != CLKDIV), two CS0
# windows with a CSB-high gap of at least (IDLE+1)*(CLKDIV+1) core cycles
# (IDLE is the bench default 1). Rows without such a change must give the same
# totals on both builds. A nonzero exit, a timeout or a missing TOTAL line is
# ERROR. Prints the verdict counts and exits nonzero unless every row passes.
# The main_windows column records the CS0 window count of the main build; the
# grade does not use it.
set -uo pipefail
main_sim="$1"
tip_sim="$2"
out_tsv="$3"
bench_idle=1

printf 'verdict\tconfig_change\tplusargs\tmain_total\ttip_total\tmain_windows\ttip_windows\ttip_gap\n' > "$out_tsv" || exit 1
for mode in 0 1 2 3 4; do
  for cpha in 0 1; do
    for cpha2 in 0 1; do
      for divider_pair in 1,1 3,3 1,3; do
        clkdiv=${divider_pair%,*}
        clkdiv2=${divider_pair#*,}
        for len in 0 2; do
          for dir in 1 2; do
            plusargs=("+MODE=$mode" "+CPHA=$cpha" "+CPHA2=$cpha2" "+CLKDIV=$clkdiv" "+CLKDIV2=$clkdiv2" "+SPEED=2" "+LEN=$len" "+DIR=$dir")
            main_out=$(timeout 60 "$main_sim" "${plusargs[@]}" 2>&1)
            main_rc=$?
            tip_out=$(timeout 60 "$tip_sim" "${plusargs[@]}" 2>&1)
            tip_rc=$?
            main_total=$(printf '%s\n' "$main_out" | grep '^TOTAL' | tail -1)
            tip_total=$(printf '%s\n' "$tip_out" | grep '^TOTAL' | tail -1)
            main_windows=$(printf '%s\n' "$main_out" | grep -c '^CS0 lead=')
            tip_windows=$(printf '%s\n' "$tip_out" | grep -c '^CS0 lead=')
            tip_gap=$(printf '%s\n' "$tip_out" | grep -o 'gap before CS0 = [0-9]*' | awk '{print $NF}' | tail -1)
            config_change=0
            if [[ ($mode == 2 || $mode == 4) && ($cpha != "$cpha2" || $clkdiv != "$clkdiv2") ]]; then
              config_change=1
            fi
            byte_count=$((2 * (len + 1)))
            if [[ $dir == 2 ]]; then
              expected="wr_en=$byte_count .*rd_en=0 last_read=0 last_write=2"
            else
              expected="wr_en=0 .*rd_en=$byte_count last_read=2 last_write=0"
            fi
            min_gap=$(((bench_idle + 1) * (clkdiv + 1)))
            verdict=pass
            if [[ $main_rc -ne 0 || $tip_rc -ne 0 || -z $main_total || -z $tip_total ]]; then
              verdict=ERROR
            elif ! printf '%s' "$tip_total" | grep -q -e "$expected"; then
              verdict=tip_count_fail
            elif [[ $config_change == 1 ]] && { [[ $tip_windows -ne 2 || -z $tip_gap ]] || ((tip_gap < min_gap)); }; then
              verdict=tip_window_fail
            elif [[ $config_change == 0 && "$main_total" != "$tip_total" ]]; then
              verdict=nochange_count_diff
            fi
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$verdict" "$config_change" "${plusargs[*]}" \
              "$main_total" "$tip_total" "$main_windows" "$tip_windows" "${tip_gap:--}" >> "$out_tsv" || exit 1
          done
        done
      done
    done
  done
done

tail -n +2 "$out_tsv" | cut -f1,2 | sort | uniq -c
row_count=$(tail -n +2 "$out_tsv" | wc -l)
pass_count=$(tail -n +2 "$out_tsv" | cut -f1 | grep -c '^pass$')
if [[ $row_count -eq 0 || $pass_count -ne $row_count ]]; then
  exit 1
fi
