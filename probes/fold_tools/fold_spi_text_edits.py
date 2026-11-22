# owner-check: fold_text_edits.py and the xheep_spi patch tools — read both headers — the first does not regenerate spi_host.patch, the tools make and splice one section but fold no chain; this joins them
"""Fold literal text replacements into the SPI host commit chain, and regenerate
the spi_host.patch section of each edited file in each rebuilt commit.

Usage:
  fold_spi_text_edits.py FORK_REPO UPSTREAM_REPO TOOLS_DIR SCRATCH_DIR
                         EDITS_JSON MESSAGE_DIR COMMIT...

The edits and messages work as in fold_text_edits.py. For each commit, every
edited file is written to SCRATCH_DIR, its patch section is made with
TOOLS_DIR/patch_section.sh against UPSTREAM_REPO (OpenTitan 611d56f) and
spliced into that commit's spi_host.patch with splice_patch_section.py. The
script writes commits with git commit-tree, prints their SHAs and moves no ref.
"""

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
import fold_text_edits as fold  # noqa: E402

PATCH_PATH = "spi_host.patch"
UPSTREAM_PREFIX = "hw/ip/spi_host/"


def patch_section(tools_dir, upstream_repo, fork_path, new_text, scratch_dir):
  """Return the spi_host.patch section of fork_path for its new text."""
  with tempfile.NamedTemporaryFile("w", dir=scratch_dir, delete=False,
                                   suffix=".src") as source_file:
    source_file.write(new_text)
  result = subprocess.run(
    ["bash", str(Path(tools_dir) / "patch_section.sh"), upstream_repo,
     fork_path, source_file.name, scratch_dir],
    check=True, capture_output=True, text=True)
  if not result.stdout.startswith("diff --git "):
    raise SystemExit(f"no patch section for {fork_path}")
  return result.stdout


def edited_texts(repo, commit, edits):
  """Return {path: new text} for the edits that apply to commit."""
  texts = {}
  for edit in edits:
    path = edit["path"]
    if path not in texts:
      texts[path] = fold.git(repo, "show", f"{commit}:{path}").decode()
    count = texts[path].count(edit["old"])
    if count != 1:
      raise SystemExit(
        f"edit {edit['id']}: {count} matches in {commit[:8]}:{path}, need 1")
    texts[path] = texts[path].replace(edit["old"], edit["new"])
  return texts


def tree_with_texts(repo, commit, texts):
  """Return the SHA of commit's tree with each path set to its text."""
  with tempfile.TemporaryDirectory() as index_dir:
    env = dict(os.environ, GIT_INDEX_FILE=str(Path(index_dir) / "index"))
    fold.git(repo, "read-tree", commit, env=env)
    for path, text in texts.items():
      blob = fold.git(repo, "hash-object", "-w", "--stdin",
                      input_bytes=text.encode()).decode().strip()
      mode = fold.file_mode(repo, commit, path)
      fold.git(repo, "update-index", "--cacheinfo", f"{mode},{blob},{path}",
               env=env)
    return fold.git(repo, "write-tree", env=env).decode().strip()


def main():
  if len(sys.argv) < 8:
    raise SystemExit(__doc__)
  (repo, upstream_repo, tools_dir, scratch_dir, edits_path, message_dir,
   *chain_prefixes) = sys.argv[1:]
  sys.path.insert(0, tools_dir)
  import splice_patch_section  # noqa: E402

  edits = json.loads(Path(edits_path).read_text())
  chain = [fold.resolve(repo, prefix) for prefix in chain_prefixes]
  position = {prefix: index for index, prefix in enumerate(chain_prefixes)}
  unknown = {edit["first"] for edit in edits} - position.keys()
  if unknown:
    raise SystemExit(f"edits name commits outside the chain: {sorted(unknown)}")

  # Build every tree first, so that a failed match writes no commit.
  trees = []
  for index, commit in enumerate(chain):
    applied = [edit for edit in edits if position[edit["first"]] <= index]
    texts = edited_texts(repo, commit, applied)
    if texts:
      patch_text = fold.git(repo, "show", f"{commit}:{PATCH_PATH}").decode()
      for path, text in texts.items():
        section = patch_section(tools_dir, upstream_repo, path, text,
                                scratch_dir)
        patch_text = splice_patch_section.splice_section(
          patch_text, UPSTREAM_PREFIX + path, section)
      texts[PATCH_PATH] = patch_text
    trees.append(tree_with_texts(repo, commit, texts))

  parent = fold.resolve(repo, chain[0] + "^")
  for prefix, commit, tree in zip(chain_prefixes, chain, trees):
    message = fold.commit_message(repo, commit, prefix, message_dir)
    parent = fold.git(repo, "commit-tree", tree, "-p", parent,
                      input_bytes=message,
                      env=fold.identity_env(repo, commit)).decode().strip()
    print(f"{prefix} -> {parent} tree {tree}")


if __name__ == "__main__":
  main()
