#!/bin/bash
# owner-check: none — splice_patch_section.py (scratchpad opentitan_611d56f) replaces a section but does not make one; the fork has no generator for spi_host.patch, whose sections are `git diff --abbrev=10` of upstream OpenTitan 611d56f against the fork file.
# Print the spi_host.patch section for one fork file: the diff of the upstream
# OpenTitan 611d56f blob against the given new file, under the upstream path
# hw/ip/spi_host/<fork_path>, with ten-digit abbreviated blob ids, as the
# existing sections are written.
# Usage: patch_section.sh UPSTREAM_REPO FORK_PATH NEW_FILE SCRATCH_DIR
# UPSTREAM_REPO is a Git repository whose HEAD holds the upstream tree. The
# script writes the new blob into its object store and uses a temporary index
# under SCRATCH_DIR, so it changes no working tree, real index or ref. The
# temporary index stays in SCRATCH_DIR for the scratch prune.
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "usage: patch_section.sh UPSTREAM_REPO FORK_PATH NEW_FILE SCRATCH_DIR" >&2
  exit 2
fi
upstream_repo="$1"
upstream_path="hw/ip/spi_host/$2"
new_file="$3"
scratch_dir="$4"

temporary_index=$(mktemp -p "$scratch_dir" index.XXXXXX)
new_blob=$(git -C "$upstream_repo" hash-object -w -- "$new_file")
GIT_INDEX_FILE="$temporary_index" git -C "$upstream_repo" read-tree HEAD
GIT_INDEX_FILE="$temporary_index" git -C "$upstream_repo" update-index --cacheinfo "100644,$new_blob,$upstream_path"
GIT_INDEX_FILE="$temporary_index" git -C "$upstream_repo" diff --cached --abbrev=10 -- "$upstream_path"
