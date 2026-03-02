#!/usr/bin/env python3
"""
struct_analyzer.py — C struct/bitfield layout + cache analysis tool

Usage examples:
  python3 tools/struct_analyzer.py layout "int cost; uint32_t a:21, b:4, c:7; uint64_t x:21, y:11; int score;"
  python3 tools/struct_analyzer.py bitfield "uint32_t rep_offset:21, short_offset:4, score:7; uint64_t rep_pos:21, match_len:11;"
  python3 tools/struct_analyzer.py cache --size 16 --arrivals 62 --cacheline 64
"""

import sys
import re

# ---------------------------------------------------------------------------
# Type sizes and alignment (LP64 / ARM64 / x86-64)
# ---------------------------------------------------------------------------
TYPE_INFO = {
    "char":          (1, 1), "unsigned char":      (1, 1), "signed char":      (1, 1),
    "short":         (2, 2), "unsigned short":     (2, 2),
    "int":           (4, 4), "unsigned int":       (4, 4), "signed int":       (4, 4),
    "long":          (8, 8), "unsigned long":      (8, 8),
    "long long":     (8, 8), "unsigned long long": (8, 8),
    "int8_t":        (1, 1), "uint8_t":            (1, 1),
    "int16_t":       (2, 2), "uint16_t":           (2, 2),
    "int32_t":       (4, 4), "uint32_t":           (4, 4),
    "int64_t":       (8, 8), "uint64_t":           (8, 8),
    "float":         (4, 4), "double":             (8, 8),
    "pointer":       (8, 8),
}

def align_up(val, align):
    return (val + align - 1) & ~(align - 1)

# ---------------------------------------------------------------------------
# Struct layout (regular fields, no bitfields)
# ---------------------------------------------------------------------------
def parse_fields(decl):
    fields = []
    for stmt in re.split(r';', decl):
        stmt = re.sub(r':\s*\d+', '', stmt).strip()
        if not stmt:
            continue
        m = re.match(r'^((?:unsigned |signed |long )*\w+(?:\s+long)?)\s+(\w+)$', stmt)
        if m:
            fields.append((m.group(1).strip(), m.group(2).strip()))
    return fields

def layout_struct(decl):
    fields = parse_fields(decl)
    offset = 0
    max_align = 1
    print(f"\n{'Field':<20} {'Type':<18} {'Size':>4} {'Align':>5} {'Offset':>6} {'End':>6} {'Pad':>4}")
    print("-" * 70)
    for (typ, name) in fields:
        info = TYPE_INFO.get(typ)
        if not info:
            print(f"  Unknown type: {typ}")
            continue
        size, align = info
        max_align = max(max_align, align)
        padded = align_up(offset, align)
        pad = padded - offset
        print(f"{name:<20} {typ:<18} {size:>4} {align:>5} {padded:>6} {padded+size:>6} {pad:>4}")
        offset = padded + size
    total = align_up(offset, max_align)
    tail_pad = total - offset
    print("-" * 70)
    print(f"{'Total size':<46} {total:>6}  (tail pad: {tail_pad})")
    print(f"Max alignment: {max_align}")
    return total

# ---------------------------------------------------------------------------
# Bitfield packing simulator
# ---------------------------------------------------------------------------
def parse_bitfields(decl):
    fields = []
    for stmt in re.split(r';', decl):
        stmt = stmt.strip()
        if not stmt:
            continue
        m = re.match(r'^((?:unsigned |signed |long )*\w+(?:\s+long)?)\s+(.+)$', stmt)
        if not m:
            continue
        typ = m.group(1).strip()
        for fld in re.split(r',', m.group(2)):
            fld = fld.strip()
            fm = re.match(r'(\w+)\s*:\s*(\d+)', fld)
            if fm:
                fields.append((typ, fm.group(1), int(fm.group(2))))
    return fields

def simulate_bitfields(decl):
    """
    Simulate C bitfield packing (C11):
    - Fields of same base type share a storage unit if they fit.
    - A field that doesn't fit OR a different type starts a new storage unit.
    """
    fields = parse_bitfields(decl)
    if not fields:
        print("No bitfields parsed.")
        print("Format: 'uint32_t a:21, b:4; uint64_t c:11;'")
        return

    print(f"\n{'Field':<20} {'Type':<12} {'Bits':>4} {'Unit#':>5} {'BitOff':>6} {'Spare':>6}")
    print("-" * 60)

    units = []
    cur_type = None
    cur_capacity = 0
    cur_used = 0
    unit_idx = -1

    for (typ, name, nbits) in fields:
        info = TYPE_INFO.get(typ)
        if not info:
            print(f"  Unknown type: {typ}")
            continue
        storage_bytes, _ = info
        capacity = storage_bytes * 8

        need_new = (typ != cur_type or cur_used + nbits > cur_capacity)

        if need_new:
            if unit_idx >= 0:
                units[unit_idx]['spare'] = cur_capacity - cur_used
            unit_idx += 1
            units.append({'type': typ, 'capacity': capacity, 'used': 0, 'fields': [], 'spare': 0})
            cur_type = typ
            cur_capacity = capacity
            cur_used = 0

        bit_offset = cur_used
        cur_used += nbits
        units[unit_idx]['used'] = cur_used
        units[unit_idx]['fields'].append(name)
        spare_now = cur_capacity - cur_used

        print(f"{name:<20} {typ:<12} {nbits:>4} {unit_idx:>5} {bit_offset:>6} {spare_now:>6}")

    if unit_idx >= 0:
        units[unit_idx]['spare'] = cur_capacity - cur_used

    print("-" * 60)

    # Compute total struct size
    total_bytes = 0
    max_align = 1
    print("\nStorage units:")
    for i, u in enumerate(units):
        sz, al = TYPE_INFO[u['type']]
        total_bytes = align_up(total_bytes, al) + sz
        max_align = max(max_align, al)
        status = f"FULL" if u['spare'] == 0 else f"{u['spare']} bits spare"
        print(f"  Unit {i}: {u['type']:12} {sz*8:3}-bit  used={u['used']:3}/{sz*8}  [{status}]  {u['fields']}")

    total_bytes = align_up(total_bytes, max_align)
    print(f"\nEstimated struct size: {total_bytes} bytes  (alignment: {max_align})")

    # Hints
    for i, u in enumerate(units):
        if u['spare'] > 0:
            print(f"  💡 Unit {i}: {u['spare']} spare bits → can add {u['spare']}-bit field of type {u['type']} with no size increase")

# ---------------------------------------------------------------------------
# Cache line analysis
# ---------------------------------------------------------------------------
def cache_analysis(struct_size, count, cacheline=64, l1_kb=64, l2_kb=512):
    total = struct_size * count
    per_line = cacheline // struct_size
    waste_per_line = cacheline % struct_size
    total_lines = (total + cacheline - 1) // cacheline

    print(f"\nCache line analysis")
    print(f"  Struct size:      {struct_size} bytes  ({struct_size*8} bits)")
    print(f"  Count:            {count} entries")
    print(f"  Array total:      {total} bytes  ({total / 1024:.2f} KB)")
    print(f"  Cache line:       {cacheline} bytes")
    print()
    print(f"  Entries per cache line:  {per_line}  (internal waste: {waste_per_line} bytes/line = {waste_per_line/cacheline*100:.1f}%)")
    print(f"  Cache lines needed:      {total_lines}")
    print()
    print(f"  Fits in L1 ({l1_kb:3}KB): {'✅ YES' if total <= l1_kb*1024 else '❌ NO '}")
    print(f"  Fits in L2 ({l2_kb:3}KB): {'✅ YES' if total <= l2_kb*1024 else '❌ NO '}")

    print(f"\n  Alternative sizes (count={count}, cacheline={cacheline}):")
    print(f"  {'Size':>6}  {'Total':>10}  {'Per line':>9}  {'Waste%':>7}  {'Lines':>7}  {'Delta':>12}")
    candidates = sorted(set([max(1, struct_size - 8), max(1, struct_size - 4),
                              struct_size, struct_size + 4, struct_size + 8,
                              8, 12, 16, 20, 24, 32, 48, 64]))
    for alt in candidates:
        if alt <= 0:
            continue
        alt_total = alt * count
        alt_per = cacheline // alt
        alt_waste = (cacheline % alt) / cacheline * 100
        alt_lines = (alt_total + cacheline - 1) // cacheline
        delta = f"{(alt_total - total):+d} B" if alt != struct_size else "(current)"
        marker = " ◀" if alt == struct_size else ""
        print(f"  {alt:>6}  {alt_total:>8}B  {alt_per:>9}  {alt_waste:>6.1f}%  {alt_lines:>7}  {delta:>12}{marker}")

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def usage():
    print(__doc__)
    sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        usage()

    cmd = sys.argv[1]

    if cmd == "layout":
        if len(sys.argv) < 3:
            usage()
        layout_struct(sys.argv[2])

    elif cmd == "bitfield":
        if len(sys.argv) < 3:
            usage()
        simulate_bitfields(sys.argv[2])

    elif cmd == "cache":
        import argparse
        p = argparse.ArgumentParser(prog="struct_analyzer.py cache")
        p.add_argument("--size",      type=int, required=True, help="struct size in bytes")
        p.add_argument("--arrivals",  type=int, required=True, help="number of entries")
        p.add_argument("--cacheline", type=int, default=64,    help="cache line size (default 64)")
        p.add_argument("--l1",        type=int, default=64,    help="L1 cache in KB (default 64)")
        p.add_argument("--l2",        type=int, default=512,   help="L2 cache in KB (default 512)")
        args = p.parse_args(sys.argv[2:])
        cache_analysis(args.size, args.arrivals, args.cacheline, args.l1, args.l2)

    else:
        usage()
