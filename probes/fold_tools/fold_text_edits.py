# owner-check: git tree-filter rewrite and wip_save.py — `command -v git-filter-repo` (absent), wip_save.py header — the tree filter asserts no single match per tree and writes backup refs, wip_save.py only stacks commits
"""Fold literal text replacements into an existing commit chain.

Each edit names a file, an old string, a new string and the first commit of
the chain whose tree gets the edit. Every later tree gets it too. The old
string must occur exactly once in the file of each tree that gets the edit,
or the script stops before it writes any commit. The script writes new
commits with git commit-tree and prints their SHAs; it moves no ref.

Usage:
  fold_text_edits.py REPO EDITS_JSON MESSAGE_DIR COMMIT...

COMMIT... is the chain from oldest to newest. MESSAGE_DIR may hold
msg_<prefix>.txt, where <prefix> is the edit-list prefix of a chain commit;
that file replaces the commit message. Author and committer identity and
dates are kept.
"""

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

IDENTITY_FORMAT = "%an%x00%ae%x00%aI%x00%cn%x00%ce%x00%cI"
IDENTITY_VARIABLES = [
  "GIT_AUTHOR_NAME", "GIT_AUTHOR_EMAIL", "GIT_AUTHOR_DATE",
  "GIT_COMMITTER_NAME", "GIT_COMMITTER_EMAIL", "GIT_COMMITTER_DATE"]


def git(repo, *args, input_bytes=None, env=None):
  """Return the stdout bytes of one git command in repo."""
  return subprocess.run(
    ["git", "-C", repo, *args], input=input_bytes, env=env,
    check=True, capture_output=True).stdout


def resolve(repo, rev):
  """Return the full SHA of the commit that rev names."""
  return git(repo, "rev-parse", "--verify", rev + "^{commit}").decode().strip()


def edited_blob(repo, commit, path, edits):
  """Return the SHA of the blob of path in commit after its edits."""
  text = git(repo, "show", f"{commit}:{path}").decode()
  for edit in edits:
    count = text.count(edit["old"])
    if count != 1:
      raise SystemExit(
        f"edit {edit['id']}: {count} matches in {commit[:8]}:{path}, need 1")
    text = text.replace(edit["old"], edit["new"])
  return git(repo, "hash-object", "-w", "--stdin",
             input_bytes=text.encode()).decode().strip()


def file_mode(repo, commit, path):
  """Return the tree mode of path in commit."""
  entry = git(repo, "ls-tree", commit, "--", path).decode().split()
  if not entry:
    raise SystemExit(f"{path} is missing in {commit[:8]}")
  return entry[0]


def edited_tree(repo, commit, edits_by_path):
  """Return the SHA of commit's tree with the edits applied."""
  with tempfile.TemporaryDirectory() as index_dir:
    env = dict(os.environ, GIT_INDEX_FILE=str(Path(index_dir) / "index"))
    git(repo, "read-tree", commit, env=env)
    for path, edits in edits_by_path.items():
      blob = edited_blob(repo, commit, path, edits)
      mode = file_mode(repo, commit, path)
      git(repo, "update-index", "--cacheinfo", f"{mode},{blob},{path}",
          env=env)
    return git(repo, "write-tree", env=env).decode().strip()


def identity_env(repo, commit):
  """Return an environment that keeps commit's author and committer."""
  fields = git(repo, "log", "-1", f"--format={IDENTITY_FORMAT}",
               commit).decode().rstrip("\n").split("\0")
  return dict(os.environ, **dict(zip(IDENTITY_VARIABLES, fields)))


def commit_message(repo, commit, prefix, message_dir):
  """Return the override message for prefix, or commit's own message."""
  override = Path(message_dir) / f"msg_{prefix}.txt"
  if override.is_file():
    return override.read_bytes()
  # The raw object keeps the message bytes; `git log --format=%B` appends a
  # newline, which would change every rebuilt commit that has no override.
  raw_commit = git(repo, "cat-file", "commit", commit)
  return raw_commit.split(b"\n\n", 1)[1]


def main():
  if len(sys.argv) < 5:
    raise SystemExit(__doc__)
  repo, edits_path, message_dir, *chain_prefixes = sys.argv[1:]
  edits = json.loads(Path(edits_path).read_text())
  chain = [resolve(repo, prefix) for prefix in chain_prefixes]
  position = {prefix: index for index, prefix in enumerate(chain_prefixes)}
  unknown = {edit["first"] for edit in edits} - position.keys()
  if unknown:
    raise SystemExit(f"edits name commits outside the chain: {sorted(unknown)}")

  # Build every tree first, so that a failed match writes no commit.
  trees = []
  for index, commit in enumerate(chain):
    edits_by_path = {}
    for edit in edits:
      if position[edit["first"]] <= index:
        edits_by_path.setdefault(edit["path"], []).append(edit)
    trees.append(edited_tree(repo, commit, edits_by_path))

  parent = resolve(repo, chain[0] + "^")
  for prefix, commit, tree in zip(chain_prefixes, chain, trees):
    message = commit_message(repo, commit, prefix, message_dir)
    parent = git(repo, "commit-tree", tree, "-p", parent,
                 input_bytes=message,
                 env=identity_env(repo, commit)).decode().strip()
    print(f"{prefix} -> {parent} tree {tree}")


if __name__ == "__main__":
  main()
