#!/usr/bin/env python3
"""osd_alloc.py - MiSTer OSD CONF_STR status-bit allocation decoder.

Takes a MiSTer CONF_STR (a .sv file that contains one, or a raw string) and
decodes every option's status-bit allocation. This removes the guesswork when
adding/moving an OSD option: run it before and after a change and diff.

Encoding (verified against this project's known status[] usages):
  Option header:  P<page><bank><bits>
    <page>  : OSD page number (0-9) - menu organisation only.
    <bank>  : 'O' = lower bank (offset 0), 'o' = upper bank (offset +32).
    <bits>  : one char (1-bit) or two chars '<lo><hi>' (range [hi:lo]).
  Char -> bit (within the bank):
    '0'-'9' -> 0-9
    'A'-'Z' -> 10-35
    'a'-'z' -> 36-61
  Actual status bit = bank_offset + char_value.
  A two-char spec '<lo><hi>' covers [hi:lo] (hi-lo+1 bits).

Non-option lines:
  P<page>,<title>;   page title (no bits)
  P<page>-;          separator (no bits)

Usage:
  osd_alloc.py FILE.sv                 decode the CONF_STR in a .sv file
  osd_alloc.py --str '...{...}...'     decode a raw CONF_STR string
  osd_alloc.py FILE.sv --json          machine-readable output
  osd_alloc.py --diff A.sv B.sv        diff two allocations (added/removed/moved)
  osd_alloc.py FILE.sv --free          print free status bits (0-63)
  osd_alloc.py FILE.sv --find 63:62    check which option owns a bit range
"""

import sys
import re
import json


def char_to_bit(c):
    """Map a single option char to its in-bank bit value, or None."""
    if c.isdigit():
        return int(c)
    if 'A' <= c <= 'Z':
        return 10 + (ord(c) - ord('A'))
    if 'a' <= c <= 'z':
        return 36 + (ord(c) - ord('a'))
    return None


def extract_confstr_strings(text):
    """Return the list of quoted option strings from a CONF_STR block (or raw)."""
    m = re.search(r'CONF_STR\s*=\s*\{([^}]*)\}', text, re.DOTALL)
    block = m.group(1) if m else text
    return re.findall(r'"((?:[^"\\]|\\.)*)"', block)


def decode_option(opt_str):
    """Decode one option string.

    Returns a dict with keys: kind, page, label, values, and (for options)
    bank, lo, hi, bits (a set of status bit indices). Returns None for
    titles/separators.
    """
    s = opt_str.strip().rstrip(';').strip()
    parts = [p.strip() for p in s.split(',')]
    header = parts[0]
    label = parts[1] if len(parts) > 1 else ''
    values = parts[2:] if len(parts) > 2 else []

    # Page title: P<page>  (nothing after the page digit before the comma)
    if re.fullmatch(r'P\d', header):
        return {'kind': 'title', 'page': int(header[1]), 'label': label}
    # Separator: P<page>-
    if re.fullmatch(r'P\d-', header):
        return {'kind': 'sep', 'page': int(header[1])}

    m = re.fullmatch(r'P(\d)([Oo])([0-9A-Za-z]{1,2})', header)
    if not m:
        return {'kind': 'unknown', 'header': header, 'label': label}

    page = int(m.group(1))
    bank = m.group(2)
    bits_str = m.group(3)
    offset = 32 if bank == 'o' else 0

    vals = [char_to_bit(c) for c in bits_str]
    if any(v is None for v in vals):
        return {'kind': 'unknown', 'header': header, 'label': label}

    lo = min(vals)
    hi = max(vals)
    alo = offset + lo
    ahi = offset + hi
    if ahi > 63:
        return {'kind': 'oob', 'header': header, 'label': label,
                'lo': alo, 'hi': ahi}

    return {
        'kind': 'option',
        'page': page,
        'bank': 'upper' if bank == 'o' else 'lower',
        'lo': alo,
        'hi': ahi,
        'bits': set(range(alo, ahi + 1)),
        'label': label,
        'values': values,
        'header': header,
    }


def decode_all(strings):
    """Decode all option strings into a list of records (titles/seps included)."""
    out = []
    for st in strings:
        rec = decode_option(st)
        if rec is not None:
            rec['raw'] = st
            out.append(rec)
    return out


def find_conflicts(records):
    """Return a list of (bit, [labels]) for bits owned by >1 option."""
    owner = {}
    for r in records:
        if r.get('kind') != 'option':
            continue
        for b in r['bits']:
            owner.setdefault(b, []).append(r['label'] or r['header'])
    return {b: labels for b, labels in sorted(owner.items()) if len(labels) > 1}


def free_bits(records, width=64):
    used = set()
    for r in records:
        if r.get('kind') == 'option':
            used |= r['bits']
    return [b for b in range(width) if b not in used]


def format_bits(r):
    if r['lo'] == r['hi']:
        return 'status[%d]' % r['lo']
    return 'status[%d:%d]' % (r['hi'], r['lo'])


def render(records):
    lines = []
    for r in records:
        if r['kind'] == 'title':
            lines.append('  page %d: %s' % (r['page'], r['label']))
        elif r['kind'] == 'sep':
            lines.append('  ---')
        elif r['kind'] == 'option':
            nv = len(r['values'])
            nb = r['hi'] - r['lo'] + 1
            flag = '' if (nv <= (1 << nb)) else '  <-- %d values need >%d bits' % (nv, nb)
            lines.append('  %-8s %-14s %-10s %s%s' %
                         (r['header'], format_bits(r), r['bank'],
                          r['label'], flag))
        else:
            lines.append('  ? %-8s %s' % (r.get('header', '?'), r.get('label', '')))
    return '\n'.join(lines)


def load_records(path_or_str, as_str=False):
    text = path_or_str if as_str else open(path_or_str, 'r', encoding='utf-8',
                                           errors='replace').read()
    return decode_all(extract_confstr_strings(text))


def main(argv):
    args = argv[1:]
    as_str = False
    as_json = False
    show_free = False
    find_range = None
    diff = False

    positional = []
    i = 0
    while i < len(args):
        a = args[i]
        if a == '--str':
            as_str = True
        elif a == '--json':
            as_json = True
        elif a == '--free':
            show_free = True
        elif a == '--find':
            i += 1
            find_range = args[i]
        elif a == '--diff':
            diff = True
        else:
            positional.append(a)
        i += 1

    if diff:
        if len(positional) < 2:
            print('usage: osd_alloc.py --diff A.sv B.sv', file=sys.stderr)
            return 2
        ra = load_records(positional[0])
        rb = load_records(positional[1])
        ma = {r['header']: r for r in ra if r.get('kind') == 'option'}
        mb = {r['header']: r for r in rb if r.get('kind') == 'option'}
        for h in sorted(set(ma) | set(mb)):
            if h not in ma:
                print('  + %s  %s  (added)' % (h, format_bits(mb[h])))
            elif h not in mb:
                print('  - %s  %s  (removed)' % (h, format_bits(ma[h])))
            elif ma[h]['bits'] != mb[h]['bits']:
                print('  ~ %s  %s -> %s  (moved)' %
                      (h, format_bits(ma[h]), format_bits(mb[h])))
        # conflicts in the new one
        c = find_conflicts(rb)
        if c:
            print('  CONFLICTS in B:')
            for b, labels in c.items():
                print('    bit %d: %s' % (b, ' vs '.join(labels)))
        return 0

    if len(positional) < 1:
        print(__doc__)
        return 2
    records = load_records(positional[0], as_str=as_str)

    if as_json:
        print(json.dumps(records, indent=2, sort_keys=True))
        return 0

    print(render(records))
    conflicts = find_conflicts(records)
    if conflicts:
        print('\nCONFLICTS:')
        for b, labels in conflicts.items():
            print('  bit %d: %s' % (b, ' vs '.join(labels)))
    else:
        print('\nno bit conflicts')

    if show_free or find_range is None:
        fb = free_bits(records)
        print('free bits (%d): %s' %
              (len(fb), ' '.join(str(b) for b in fb) if fb else '(none)'))

    if find_range is not None:
        m = re.fullmatch(r'(\d+)(?::(\d+))?', find_range.strip())
        if not m:
            print('bad --find range: %s' % find_range, file=sys.stderr)
            return 2
        hi = int(m.group(1))
        lo = int(m.group(2)) if m.group(2) else hi
        want = set(range(lo, hi + 1))
        owners = []
        for r in records:
            if r.get('kind') == 'option' and (r['bits'] & want):
                owners.append('%s (%s)' % (r['header'], format_bits(r)))
        print('bits %s owned by: %s' %
              (find_range, ', '.join(owners) if owners else 'FREE'))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
