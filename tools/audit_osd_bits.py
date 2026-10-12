#!/usr/bin/env python3
"""audit_osd_bits.py - status-bit overlap auditor for MiSTer CONF_STR.

osd_alloc.py's header regex only accepts `P<page><bank><1-2 bit chars>`, so it
shows `?` for (a) bracket-form lines like `P2o[54:52]` and (b) H/D/h/d prefixed
lines like `D0P0OOP` / `d0P2FC2`, and its conflict/ownership checks are blind
to them. This auditor parses those forms using the real OSD semantics
(verified against user_io.cpp):
  - leading H/D/h/d<flag> pairs are stripped
  - P<page> then bank: O=+0, o=+32; T/R (lower) / t/r (upper) = 1-bit action
  - char map: 0-9 -> 0-9, A-V -> 10-31
  - char form: 1 char = 1 bit, 2 chars = range [second:first] + bank offset
  - bracket form [hi:lo] or [n]: ABSOLUTE bits (bank ignored), hi = first
  - F/S/J/C/V/I carry no bits; titles/separators carry no bits

Usage:  audit_osd_bits.py FILE.sv
Prints: unparsed lines, per-bit conflicts, and the full ownership map.
Exits 1 if any bit is owned by more than one option.
"""
import re
import sys


def c2b(c):
    if c.isdigit():
        return int(c)
    if 'A' <= c <= 'V':
        return 10 + (ord(c) - ord('A'))
    return None


def main(path):
    t = open(path, encoding='utf-8', errors='replace').read()
    m = re.search(r'CONF_STR\s*=\s*\{([^}]*)\}', t, re.DOTALL)
    if not m:
        print('no CONF_STR found in %s' % path, file=sys.stderr)
        return 2
    # strip whole-line // comments only (NOT // inside label text like "NTSC //e")
    block = '\n'.join(l for l in m.group(1).split('\n')
                      if not l.strip().startswith('//'))
    lines = re.findall(r'"((?:[^"\\]|\\.)*)"', block)

    owner = {}
    unparsed = []
    for raw in lines:
        s = raw.strip().rstrip(';').strip()
        if not s or s.startswith('Apple-II'):
            continue
        p = s
        while len(p) > 2 and p[0] in 'HhDd':
            p = p[2:]
        if p[0] == 'P':
            p = p[2:] if len(p) > 1 else ''
        if not p or p[0] == '-':
            continue
        c0 = p[0]
        hdr = raw.split(',')[0]
        if c0 in 'FSJCVI':
            continue
        if c0 in 'TtRr':
            b = c2b(p[1])
            if b is None:
                unparsed.append(raw)
                continue
            owner.setdefault(b + (32 if c0 in 'tr' else 0), []).append(hdr)
            continue
        if c0 in 'Oo':
            off = 32 if c0 == 'o' else 0
            spec = p[1:]
            if spec.startswith('['):
                inner = spec[1:spec.index(']')]
                if ':' in inner:
                    # [hi:lo]: first number = hi (user_io.cpp reads end first)
                    hi_i, lo_i = (int(x) for x in inner.split(':'))
                    if hi_i > 127 or lo_i > 127 or hi_i < lo_i:
                        unparsed.append(raw)
                        continue
                else:
                    lo_i = hi_i = int(inner)
                    if hi_i > 127:
                        unparsed.append(raw)
                        continue
                for b in range(lo_i, hi_i + 1):
                    owner.setdefault(b, []).append(hdr)
            else:
                v1 = c2b(spec[0])
                if v1 is None:
                    unparsed.append(raw)
                    continue
                v2 = c2b(spec[1]) if len(spec) > 1 and c2b(spec[1]) is not None else None
                if v2 is not None:
                    lo_i, hi_i = min(v1, v2) + off, max(v1, v2) + off
                else:
                    lo_i = hi_i = v1 + off
                for b in range(lo_i, hi_i + 1):
                    owner.setdefault(b, []).append(hdr)
        else:
            unparsed.append(raw)

    if unparsed:
        print('=== UNPARSED (review these) ===')
        for u in unparsed:
            print('  ' + u.split(',')[0])
    conf = {b: l for b, l in owner.items() if len(l) > 1}
    print('=== CONFLICTS ===')
    if conf:
        for b, l in sorted(conf.items()):
            print('  bit %d: %s' % (b, ' vs '.join(l)))
    else:
        print('  none')
    print('=== ownership map ===')
    for b in sorted(owner):
        print('  bit %3d: %s' % (b, ','.join(owner[b])))
    return 1 if conf else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else 'Apple-II.sv'))
