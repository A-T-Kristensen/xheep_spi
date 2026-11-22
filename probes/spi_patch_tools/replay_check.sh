#!/bin/bash
# owner-check: none — the fork README gives only the manual replay steps, and the earlier replay records in the scratchpad hold results, not a script.
# Replay spi_host.patch of one fork commit on upstream OpenTitan 611d56f and
# compare every retained file with the fork file at that commit.
# Usage: replay_check.sh UPSTREAM_REPO FORK_REPO FORK_COMMIT SCRATCH_DIR
# Retained files are all files of FORK_COMMIT except README.md and
# spi_host.patch. The replay tree is a new folder under SCRATCH_DIR, left for
# the scratch prune. Prints one line per mismatch and a summary
# "REPLAY <commit> retained=N match=M sections=S"; exits 1 when the patch does
# not apply, when a file differs, or when no retained file was compared.
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "usage: replay_check.sh UPSTREAM_REPO FORK_REPO FORK_COMMIT SCRATCH_DIR" >&2
  exit 2
fi
upstream_repo="$1"
fork_repo="$2"
fork_commit="$3"
scratch_dir="$4"

work_dir=$(mktemp -d -p "$scratch_dir" replay.XXXXXX)
git -C "$upstream_repo" archive HEAD | tar -x -C "$work_dir"
git -C "$fork_repo" show "$fork_commit:spi_host.patch" > "$work_dir/spi_host.patch"
section_count=$(grep -c '^diff --git ' "$work_dir/spi_host.patch" || true)
if ! (cd "$work_dir" && git apply spi_host.patch) 2> "$work_dir/apply.err"; then
  echo "APPLY failed for $fork_commit"
  cat "$work_dir/apply.err"
  exit 1
fi

retained_count=0
match_count=0
mapfile -t fork_paths < <(git -C "$fork_repo" ls-tree -r --name-only "$fork_commit")
if [[ ${#fork_paths[@]} -eq 0 ]]; then
  echo "LIST failed for $fork_commit"
  exit 1
fi
for fork_path in "${fork_paths[@]}"; do
  if [[ "$fork_path" == README.md || "$fork_path" == spi_host.patch ]]; then
    continue
  fi
  retained_count=$((retained_count + 1))
  fork_blob=$(git -C "$fork_repo" rev-parse "$fork_commit:$fork_path")
  replay_blob=$(git hash-object -- "$work_dir/hw/ip/spi_host/$fork_path" 2> /dev/null || echo missing)
  if [[ "$fork_blob" == "$replay_blob" ]]; then
    match_count=$((match_count + 1))
  else
    echo "MISMATCH $fork_path"
  fi
done

echo "REPLAY $fork_commit retained=$retained_count match=$match_count sections=$section_count"
if [[ $retained_count -eq 0 || $match_count -ne $retained_count ]]; then
  exit 1
fi
