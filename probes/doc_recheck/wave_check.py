"""Decode the Byte Select and Shift Register WaveJSON rows of doc/_index.md
and compare Byte Select with a cycle model of the RTL.

# owner-check: none — `ls ~/.local/bin`, `which wavedrom-cli`, loaded skills — no installed tool decodes WaveJSON per column against an RTL model

Byte Select model: prim_packer_fifo gen_unpack_mode at OpenTitan 611d56f
(InW 36, OutW 9) inside spi_host_byte_select.sv at the PR tip, with
byte_ready_i tied high as in the waveform.
Usage: python3 -I wave_check.py <doc file>
"""
import ast
import re
import sys

LANES_PER_WORD = 4  # FullDepth = 36 / 9
BITS_PER_BYTE = 8
ROW_PATTERN = re.compile(
  r'\{name:\s*"([^"]+)",\s*wave:\s*"([^"]+)"(?:,\s*data:\s*(\[[^\]]*\]|"[^"]*"))?')
BLOCK_PATTERN = re.compile(r'\{\{< wavejson >\}\}(.*?)\{\{< /wavejson >\}\}', re.S)


def decode_row(wave, data_items):
  """Return the per-column values of one wave string, and unused data items."""
  remaining = list(data_items)
  values = []
  current = None
  for symbol in wave:
    if symbol in '2345':
      current = remaining.pop(0) if remaining else 'MISSING'
    elif symbol != '.':
      current = symbol
    values.append(current)
  return values, remaining


def rows_of_block(block):
  """Return {row name: (column values, unused data)} for one waveform block."""
  rows = {}
  for match in ROW_PATTERN.finditer(block):
    name, wave, data_text = match.groups()
    data_items = []
    if data_text:
      parsed = ast.literal_eval(data_text)
      data_items = parsed if isinstance(parsed, list) else [parsed]
    rows[name] = decode_row(wave, data_items)
  return rows


def byte_select_model(word_valid, words, byte_enables, flush):
  """Return per-column (word_ready_o, byte_valid_o, byte_o hex, depth_q)."""
  empty = [(0, 0)] * LANES_PER_WORD
  depth_q, ptr_q, data_q, clr_q = 0, 0, empty, 0
  columns = []
  for idx, valid_symbol in enumerate(word_valid):
    wready = int(depth_q == 0 and not clr_q)
    rvalid = int(depth_q != 0 and not clr_q)
    lane_enable, lane_byte = data_q[ptr_q]
    byte_ready = 1  # byte_ready_i high; do_drain only adds to it
    load = int(valid_symbol == '1') & wready
    pull = rvalid & byte_ready
    clear_status = int((byte_ready and depth_q == 1) or clr_q)
    columns.append((wready, rvalid & lane_enable, '%02X' % lane_byte, depth_q))
    if clear_status:
      depth_q, ptr_q, data_q = 0, 0, empty
    else:
      if load:
        word = int(words[idx].split("'h")[1], 16)
        enables = int(byte_enables[idx].split("'b")[1], 2)
        data_q = [((enables >> lane) & 1, (word >> (BITS_PER_BYTE * lane)) & 0xff)
                  for lane in range(LANES_PER_WORD)]
        depth_q = LANES_PER_WORD
      elif pull:
        depth_q -= 1
      if pull and not load:
        ptr_q += 1
    clr_q = int(flush[idx] == '1')
  return columns


def main():
  text = open(sys.argv[1]).read()
  for block in BLOCK_PATTERN.findall(text):
    if 'Byte Select Operation' in block:
      tag = 'BS'
    elif 'Shift Register During Standard SPI' in block:
      tag = 'SR'
    else:
      continue
    rows = rows_of_block(block)
    for name, (values, unused) in rows.items():
      print(tag, name.ljust(24), ' '.join(str(value) for value in values), 'unused=%s' % unused)
    if tag == 'BS':
      model = byte_select_model(rows['word_valid_i'][0], rows['word_i[31:0]'][0],
                                rows['word_be_i[3:0]'][0], rows['byte_flush_i'][0])
      for position, label in enumerate(('word_ready_o', 'byte_valid_o', 'byte_o', 'depth_q')):
        print('BS model', label.ljust(15), ' '.join(str(column[position]) for column in model))


main()
