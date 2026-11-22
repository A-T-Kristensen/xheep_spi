"""Compare the SPI host FSM bench output of the port (head) and the held-CS fix over a parameter matrix.

# owner-check: none — listed xheep_opentitan_spi_host (rtl, data, doc, lint/spi_host.vlt only, no dv/) and the review bench tb.sv — the bench runs one case per call, nothing runs a matrix

The fix changes only the case where a command for the same chip select arrives while CSB is held
(CSAAT=1) and its configuration differs. In the bench that is MODE 2 or MODE 4 with CPHA2 != CPHA
or CLKDIV2 != CLKDIV. Every other row must give byte-identical output on both builds.

The fix must also write every byte of both commands in every row: the bench sends two
bidirectional commands of LEN+1 bytes each, so the fix's wr_en total is 2 * (LEN + 1). This check
sees a fix that drops a byte, which a head-versus-fix comparison cannot see in the rows the fix
is allowed to change. A run that exits nonzero, times out or prints no TOTAL line is ERROR.
"""
import argparse
import itertools
import re
import subprocess
import sys

SIM_TIMEOUT_S = 120
SAME_CS_HELD_MODES = (2, 4)
MODES = (0, 1, 2, 3, 4)
CPHA_VALUES = (0, 1)
CLKDIV_PAIRS = ((1, 1), (3, 3), (1, 3))
SPEED_VALUES = (0, 2)
LEN_VALUES = (0, 2)
COMMANDS_PER_RUN = 2
TOTAL_WR_EN_PATTERN = re.compile(r'TOTAL accept=\d+ wr_en=(\d+)')


def run_sim(sim_path, plusargs):
  """Return (verdict, output) for one simulation run; verdict is OK or ERROR."""
  try:
    completed = subprocess.run([sim_path, *plusargs], capture_output=True, text=True, timeout=SIM_TIMEOUT_S, check=False)
  except subprocess.TimeoutExpired:
    return 'ERROR', 'timeout'
  output = '\n'.join(line for line in completed.stdout.splitlines() if not line.startswith('- '))
  if completed.returncode != 0 or TOTAL_WR_EN_PATTERN.search(output) is None:
    return 'ERROR', f'rc={completed.returncode} {output[-200:]}'
  return 'OK', output


def classify_row(head_result, fix_result, config_change_on_held_cs, expected_wr_en):
  """Return the class of one matrix row from both runs."""
  head_verdict, head_output = head_result
  fix_verdict, fix_output = fix_result
  if 'ERROR' in (head_verdict, fix_verdict):
    return 'error'
  if int(TOTAL_WR_EN_PATTERN.search(fix_output).group(1)) != expected_wr_en:
    return 'fix_drops_bytes'
  if head_output == fix_output:
    return 'same'
  if config_change_on_held_cs:
    return 'expected_diff'
  return 'unexpected_diff'


def matrix_rows():
  """Return the plusarg lists, the held-CS configuration-change flag and the expected wr_en total of every row."""
  rows = []
  for mode, cpha, cpha2, clkdiv_pair, speed, length in itertools.product(MODES, CPHA_VALUES, CPHA_VALUES, CLKDIV_PAIRS, SPEED_VALUES, LEN_VALUES):
    clkdiv, clkdiv2 = clkdiv_pair
    plusargs = [f'+MODE={mode}', f'+CPHA={cpha}', f'+CPHA2={cpha2}', f'+CLKDIV={clkdiv}', f'+CLKDIV2={clkdiv2}', f'+SPEED={speed}', f'+LEN={length}']
    config_change_on_held_cs = mode in SAME_CS_HELD_MODES and (cpha != cpha2 or clkdiv != clkdiv2)
    rows.append((plusargs, config_change_on_held_cs, COMMANDS_PER_RUN * (length + 1)))
  return rows


def main():
  """Run every matrix row on both builds, write one verdict line per row, and exit nonzero on a failure."""
  parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
  parser.add_argument('sim_dir', help='bench directory that holds obj2_head/sim_head and obj2_fix/sim_fix')
  parser.add_argument('out_tsv', help='table of one verdict line per matrix row')
  args = parser.parse_args()
  head_sim = f'{args.sim_dir}/obj2_head/sim_head'
  fix_sim = f'{args.sim_dir}/obj2_fix/sim_fix'
  counts = {'same': 0, 'expected_diff': 0, 'unexpected_diff': 0, 'fix_drops_bytes': 0, 'error': 0}
  lines = ['class\tconfig_change_on_held_cs\tplusargs\thead_total\tfix_total']
  for plusargs, config_change_on_held_cs, expected_wr_en in matrix_rows():
    head_result = run_sim(head_sim, plusargs)
    fix_result = run_sim(fix_sim, plusargs)
    row_class = classify_row(head_result, fix_result, config_change_on_held_cs, expected_wr_en)
    counts[row_class] += 1
    lines.append('\t'.join([row_class, str(int(config_change_on_held_cs)), ' '.join(plusargs), head_result[1].splitlines()[-1], fix_result[1].splitlines()[-1]]))
  with open(args.out_tsv, 'w', encoding='utf-8') as out_file:
    out_file.write('\n'.join(lines) + '\n')
  print(' '.join(f'{name}={count}' for name, count in counts.items()), f'rows={len(lines) - 1}')
  failed = counts['unexpected_diff'] + counts['fix_drops_bytes'] + counts['error']
  sys.exit(1 if failed else 0)


if __name__ == '__main__':
  main()
