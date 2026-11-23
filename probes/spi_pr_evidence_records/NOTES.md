# Notes on the SPI host PR evidence records

These notes say what three records of this branch show, and what they do not record. Read them before you cite one of the records.

## probes/held_cs_config/main_vs_fix.tsv

- The class column comes from `compare_head_fix.py`, which was written for the comparison of the first commit with the held chip-select fix. In that comparison, a difference in a row without a configuration change is unexpected.
- This table compares `main` with the fix, and the port lies between them. So the class name `unexpected_diff` here means only that the traces differ in a row without a configuration change.
- Checked on 2026-11-23: all 152 `unexpected_diff` rows have `config_change_on_held_cs` 0, and in each of them `head_total` equals `fix_total`. The 64 `expected_diff` rows are the configuration-change rows, and the 24 `same` rows have no change.

## probes/fullcyc_cpha1/sweep_csb_release.txt

- The file does not record its sweep key or the state machine that it ran on.
- The final recheck of tip de17a58d inferred the key as the bit delay, and the state machine from the time of the scratch build. Both stay unverified. The scratch build is removed, and this branch keeps no run command for the bench.
- Verilator on the laptop was 5.040 when it was read on 2026-11-22. The run did not record its version.
- A rerun must write the key, the state-machine commit and the Verilator version into the sweep header.

## probes/spi_pr_evidence_records/xsim_variants/

- These are the three state-machine files of the xsim send folder, saved on 2026-11-23 after the run. With `chs_spi_host_` renamed to `spi_host_`, neg has the blob of `main` 91acf0f3, port the blob of c1e8360b, and fix the blob of 0c66bf81.
- `xsim_fix_c33d_identity` fingerprints that folder by file names, sizes and modification times only (`offload.sh`, the `inventory_sha256` line), and the times were not kept. So these files are not proven to be the bytes that the server ran.
- The message of commit c541c699 calls them "the files that were sent". Read that as "the files of the send folder".

## probes/spi_pr_evidence_records/lint_tip_*.log

- Each log ends with "Exiting due to 50 warning(s)".
- The PR body states the file list of these runs and that no waiver file was used. No script on this branch records the command line.
