"""Replace one file's section of a multi-file git patch with a new section, keeping every other byte.

Usage: python3 splice_patch_section.py PATCH_FILE SECTION_PATH NEW_SECTION_FILE

A section starts at the line `diff --git a/SECTION_PATH b/SECTION_PATH` and ends before the next
`diff --git` line or at the end of the file. The script refuses to write when the patch holds that
section zero times or more than once, so a wrong path never writes a patch.
"""
import sys

DIFF_HEADER_PREFIX = 'diff --git '


def splice_section(patch_text, section_path, new_section):
  """Return patch_text with the section of section_path replaced by new_section."""
  lines = patch_text.splitlines(keepends=True)
  header = f'{DIFF_HEADER_PREFIX}a/{section_path} b/{section_path}\n'
  starts = [index for index, line in enumerate(lines) if line == header]
  if len(starts) != 1:
    raise ValueError(f'expected one section for {section_path}, found {len(starts)}')
  start = starts[0]
  end = next((index for index in range(start + 1, len(lines)) if lines[index].startswith(DIFF_HEADER_PREFIX)), len(lines))
  return ''.join(lines[:start]) + new_section + ''.join(lines[end:])


def main():
  """Splice the new section into the patch file in place."""
  patch_path, section_path, new_section_path = sys.argv[1], sys.argv[2], sys.argv[3]
  with open(patch_path, encoding='utf-8', newline='') as patch_file:
    patch_text = patch_file.read()
  with open(new_section_path, encoding='utf-8', newline='') as section_file:
    new_section = section_file.read()
  spliced = splice_section(patch_text, section_path, new_section)
  with open(patch_path, 'w', encoding='utf-8', newline='') as patch_file:
    patch_file.write(spliced)


if __name__ == '__main__':
  main()
