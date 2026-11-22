"""Insert a new file section into a multi-file git patch, before the section of another file.

Usage: python3 insert_patch_section.py PATCH_FILE BEFORE_PATH NEW_SECTION_FILE

The companion of splice_patch_section.py, which replaces a section that exists. The script refuses
to write when the patch already holds a section for the new file, or holds the section of
BEFORE_PATH zero times or more than once, so a wrong path never writes a patch.
"""
import sys

DIFF_HEADER_PREFIX = 'diff --git '


def insert_section(patch_text, before_path, new_section):
  """Return patch_text with new_section placed before the section of before_path."""
  new_lines = new_section.splitlines(keepends=True)
  if not new_lines or not new_lines[0].startswith(DIFF_HEADER_PREFIX):
    raise ValueError('the new section does not start with a diff --git line')
  lines = patch_text.splitlines(keepends=True)
  if new_lines[0] in lines:
    raise ValueError(f'the patch already holds {new_lines[0].strip()}')
  before_header = f'{DIFF_HEADER_PREFIX}a/{before_path} b/{before_path}\n'
  starts = [index for index, line in enumerate(lines) if line == before_header]
  if len(starts) != 1:
    raise ValueError(f'expected one section for {before_path}, found {len(starts)}')
  return ''.join(lines[:starts[0]]) + new_section + ''.join(lines[starts[0]:])


def main():
  """Insert the new section into the patch file in place."""
  patch_path, before_path, new_section_path = sys.argv[1], sys.argv[2], sys.argv[3]
  with open(patch_path, encoding='utf-8', newline='') as patch_file:
    patch_text = patch_file.read()
  with open(new_section_path, encoding='utf-8', newline='') as section_file:
    new_section = section_file.read()
  inserted = insert_section(patch_text, before_path, new_section)
  with open(patch_path, 'w', encoding='utf-8', newline='') as patch_file:
    patch_file.write(inserted)


if __name__ == '__main__':
  main()
