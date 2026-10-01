#!/usr/bin/env python3
import argparse, json, struct, sys
from pathlib import Path

MH_MAGIC_64 = 0xFEEDFACF
LC_SEGMENT_64 = 0x19
ZN44_MAGIC0 = 0x3148435441504E5A
ZN44_MAGIC1 = 0x3154495543524944
ZNTV_MAGIC0 = 0x31564C4156544E5A
ZNTV_MAGIC1 = 0x3154455346464F56
STATIC_HEADER_SIZE = 64
STATIC_ENTRY_SIZE = 128
TYPED_HEADER_SIZE = 64
TYPED_ENTRY_SIZE = 128


def cstr(b):
    return b.split(b'\0', 1)[0].decode('utf-8', 'replace')


def align8(v):
    return (v + 7) & ~7


def parse(path):
    data = Path(path).read_bytes()
    if len(data) < 32:
        raise ValueError('Mach-O too small')
    magic, cputype, cpusubtype, filetype, ncmds, sizeofcmds, flags, reserved = struct.unpack_from('<IIIIIIII', data, 0)
    if magic != MH_MAGIC_64:
        raise ValueError(f'not thin Mach-O 64: magic=0x{magic:08X}')
    lc_off, lc_end = 32, 32 + sizeofcmds
    if lc_end > len(data):
        raise ValueError('load commands out of file')
    owned = None
    off = lc_off
    for _ in range(ncmds):
        if off + 8 > lc_end:
            raise ValueError('truncated load command')
        cmd, cmdsize = struct.unpack_from('<II', data, off)
        if cmdsize < 8 or off + cmdsize > lc_end:
            raise ValueError('invalid load command size')
        if cmd == LC_SEGMENT_64 and cmdsize >= 72:
            segname = cstr(data[off+8:off+24])
            vmaddr, vmsize, fileoff, filesize = struct.unpack_from('<QQQQ', data, off+24)
            nsects = struct.unpack_from('<I', data, off+64)[0]
            sec_off = off + 72
            if segname == '__ZNDATA':
                for i in range(nsects):
                    s = sec_off + i * 80
                    if s + 80 > off + cmdsize:
                        raise ValueError('section table out of command')
                    sectname = cstr(data[s:s+16])
                    secseg = cstr(data[s+16:s+32])
                    addr, size = struct.unpack_from('<QQ', data, s+32)
                    sec_fileoff = struct.unpack_from('<I', data, s+48)[0]
                    if sectname == '__zndata' and secseg == '__ZNDATA':
                        owned = dict(segment_fileoff=fileoff, segment_filesize=filesize,
                                     section_offset=sec_fileoff, section_size=size,
                                     section_addr=addr, segment_vmaddr=vmaddr,
                                     section_field_offset=s)
                        break
        off += cmdsize
    if not owned:
        raise ValueError('missing __ZNDATA/__zndata')
    so = owned['section_offset']
    ss = owned['section_size']
    if so + ss > len(data):
        raise ValueError('__zndata out of file')
    if ss < STATIC_HEADER_SIZE:
        raise ValueError('__zndata too small for static header')
    sm0, sm1, sver, scount, sentry, sflags = struct.unpack_from('<QQIIII', data, so)
    if (sm0, sm1) != (ZN44_MAGIC0, ZN44_MAGIC1):
        raise ValueError(f'bad static magic: 0x{sm0:016X}/0x{sm1:016X}')
    if sentry != STATIC_ENTRY_SIZE:
        raise ValueError(f'bad static entrySize={sentry}')
    static_used = STATIC_HEADER_SIZE + scount * STATIC_ENTRY_SIZE
    to = so + align8(static_used)
    if to + TYPED_HEADER_SIZE > so + ss:
        raise ValueError('typed header not present in __zndata')
    tm0, tm1, tver, tcount, tentry, tflags = struct.unpack_from('<QQIIII', data, to)
    if (tm0, tm1) != (ZNTV_MAGIC0, ZNTV_MAGIC1):
        raise ValueError(f'bad typed magic: 0x{tm0:016X}/0x{tm1:016X}')
    if tentry != TYPED_ENTRY_SIZE:
        raise ValueError(f'bad typed entrySize={tentry}')
    if tcount > 256:
        raise ValueError(f'typed count too large: {tcount}')
    end = to + TYPED_HEADER_SIZE + tcount * TYPED_ENTRY_SIZE
    if end > so + ss:
        raise ValueError('typed entries exceed __zndata')
    entries = []
    base = to + TYPED_HEADER_SIZE
    for i in range(tcount):
        e = base + i*TYPED_ENTRY_SIZE
        rva, minv, maxv, stepv, defv = struct.unpack_from('<Qdddd', data, e)
        control = struct.unpack_from('<I', data, e+40)[0]
        value_type = cstr(data[e+44:e+52])
        title = cstr(data[e+52:e+116])
        if control not in (0, 1):
            raise ValueError(f'entry {i}: invalid control={control}')
        if value_type not in {'I8','U8','I16','U16','I32','U32','I64','U64','F32','F64'}:
            raise ValueError(f'entry {i}: invalid type={value_type!r}')
        if control == 0 and not (maxv > minv and stepv > 0):
            raise ValueError(f'entry {i}: invalid slider range')
        entries.append(dict(index=i, rva=f'0x{rva:X}', valueType=value_type,
                            control='slider' if control == 0 else 'number',
                            min=minv, max=maxv, step=stepv, default=defv, title=title))
    return dict(path=str(path), fileSize=len(data), zndata=owned,
                static=dict(version=sver, count=scount, entrySize=sentry, flags=sflags),
                typed=dict(version=tver, count=tcount, entrySize=tentry, flags=tflags, entries=entries))


def main():
    ap = argparse.ArgumentParser(description='Verify M5.11 Typed Value metadata in generated Mach-O')
    ap.add_argument('macho')
    ap.add_argument('--json', action='store_true')
    ap.add_argument('--require-count', type=int)
    ns = ap.parse_args()
    try:
        result = parse(ns.macho)
        if ns.require_count is not None and result['typed']['count'] != ns.require_count:
            raise ValueError(f"typed count {result['typed']['count']} != required {ns.require_count}")
    except Exception as e:
        print(f'FAIL: {e}', file=sys.stderr)
        return 1
    if ns.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(f"PASS: {ns.macho}")
        print(f"  __zndata offset=0x{result['zndata']['section_offset']:X} size=0x{result['zndata']['section_size']:X}")
        print(f"  static entries={result['static']['count']} typed entries={result['typed']['count']}")
        for e in result['typed']['entries']:
            print(f"  [{e['index']}] {e['title']} {e['rva']} {e['valueType']} {e['control']} min={e['min']} max={e['max']} step={e['step']} default={e['default']}")
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
