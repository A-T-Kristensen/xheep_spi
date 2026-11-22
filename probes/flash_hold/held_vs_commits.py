# owner-check: offload.sh holds remote job trees by its own listing and cannot see laptop refs (its header, "Which commits release the hold"); this one-off compares that listing with blobs of named commits.
"""Compare the files of an offload hold list with the blobs of git commits.

Usage: held_vs_commits.py HELD_TSV REPO REV [REV ...]

HELD_TSV has lines "file<TAB>repo<TAB>path<TAB>sha256". The script prints how
many held files each revision matches by sha256 at the same path, then the
count and the paths of the files that no revision matches.
"""

import hashlib
import subprocess
import sys


def blob_sha256_by_path(repo_path, revision):
  """Return {path: sha256 hex} for every blob in the tree of revision."""
  tree_listing = subprocess.run(
    ["git", "-C", repo_path, "ls-tree", "-r", "-z", revision],
    check=True, capture_output=True).stdout
  object_ids = []
  paths = []
  for entry in tree_listing.split(b"\0"):
    if not entry:
      continue
    meta, path = entry.split(b"\t", 1)
    _mode, kind, object_id = meta.split(b" ")
    if kind == b"blob":
      object_ids.append(object_id)
      paths.append(path.decode())
  batch_output = subprocess.run(
    ["git", "-C", repo_path, "cat-file", "--batch"],
    input=b"".join(object_id + b"\n" for object_id in object_ids),
    check=True, capture_output=True).stdout
  sha_by_path = {}
  offset = 0
  for path in paths:
    header_end = batch_output.index(b"\n", offset)
    size_bytes = int(batch_output[offset:header_end].split(b" ")[2])
    content_start = header_end + 1
    content = batch_output[content_start:content_start + size_bytes]
    sha_by_path[path] = hashlib.sha256(content).hexdigest()
    offset = content_start + size_bytes + 1
  return sha_by_path


def held_files_from_tsv(held_tsv):
  """Return [(path, sha256)] for the file rows of an offload hold list."""
  held_files = []
  with open(held_tsv, encoding="utf-8") as held_handle:
    for line in held_handle:
      fields = line.rstrip("\n").split("\t")
      if fields[0] == "file":
        held_files.append((fields[2], fields[3]))
  return held_files


def main():
  held_tsv, repo_path, revisions = sys.argv[1], sys.argv[2], sys.argv[3:]
  held_files = held_files_from_tsv(held_tsv)
  sha_by_revision = {rev: blob_sha256_by_path(repo_path, rev) for rev in revisions}
  match_count_by_revision = {rev: 0 for rev in revisions}
  unmatched_paths = []
  for path, held_sha in held_files:
    matching_revisions = [rev for rev in revisions if sha_by_revision[rev].get(path) == held_sha]
    for rev in matching_revisions:
      match_count_by_revision[rev] += 1
    if not matching_revisions:
      unmatched_paths.append(path)
  print(f"held files: {len(held_files)}")
  for rev in revisions:
    print(f"match {rev}: {match_count_by_revision[rev]}")
  print(f"unmatched: {len(unmatched_paths)}")
  for path in unmatched_paths:
    print(f"  {path}")


if __name__ == "__main__":
  main()
