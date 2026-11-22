"""Resolve each regref shortcode of an SPI host doc against the hjson register description.

A reference REGISTER.FIELD passes only when FIELD is a field of REGISTER itself,
not a field name that occurs somewhere in the hjson.
"""
import re
import sys

import hjson

INTERRUPT_REGISTERS = ('INTR_STATE', 'INTR_ENABLE', 'INTR_TEST')


def register_field_map(desc):
  """Return a dict from upper-case register name to its set of upper-case field names."""
  register_fields = {}
  interrupt_names = [entry['name'].upper() for entry in desc.get('interrupt_list', [])]
  for intr_register in INTERRUPT_REGISTERS:
    register_fields[intr_register] = set(interrupt_names)
  for entry in desc['registers']:
    if 'multireg' in entry:
      multireg = entry['multireg']
      register_fields[multireg['name'].upper()] = {
        field.get('name', multireg['name']).upper() for field in multireg['fields']}
    elif 'window' in entry:
      register_fields[entry['window']['name'].upper()] = set()
    elif 'name' in entry:
      register_fields[entry['name'].upper()] = {
        field.get('name', entry['name']).upper() for field in entry.get('fields', [])}
  return register_fields


def main(hjson_path, doc_path):
  register_fields = register_field_map(hjson.load(open(hjson_path)))
  doc_text = open(doc_path).read()
  references = sorted(set(re.findall(r'regref "([^"]*)"', doc_text)))
  for reference in references:
    parts = reference.split('.')
    register_name = parts[0].upper()
    if register_name not in register_fields:
      print('NO_REGISTER', reference)
    elif len(parts) > 1 and parts[1].upper() not in register_fields[register_name]:
      print('NO_FIELD', reference, sorted(register_fields[register_name]))
  print('checked', len(references), 'distinct references')
  for register_name in ('EVENT_ENABLE', 'CONTROL', 'ERROR_STATUS'):
    print(register_name, sorted(register_fields.get(register_name, [])))
  print('broken_shortcodes', re.findall(r'\{\{ +<', doc_text))


if __name__ == '__main__':
  main(sys.argv[1], sys.argv[2])
