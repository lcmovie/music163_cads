"""Read-only ARM64 Mach-O/signature audit, independent of the legacy pipeline."""
import argparse
import hashlib
import json
import struct
import uuid
from pathlib import Path

# Apple EXTERNAL_HEADERS/mach-o/loader.h. Never rewrite load commands here.
LC_SEGMENT_64 = 0x19
LC_DYSYMTAB = 0x0B
LC_ID_DYLIB = 0x0D
LC_CODE_SIGNATURE = 0x1D


def audit(path):
    data = Path(path).read_bytes()
    errors = []
    magic, cpu, subtype, kind, count, size, flags, reserved = struct.unpack_from('<8I', data)
    if magic != 0xFEEDFACF or cpu != 0x0100000C or kind != 6:
        errors.append('Expected thin ARM64 MH_DYLIB')
    end = 32 + size
    commands, segments = [], []
    signature = None
    image_uuid = None
    dependencies = []
    bind_ranges = None
    offset = 32
    for index in range(count):
        if offset + 8 > min(end, len(data)):
            errors.append('Load command header outside declared region')
            break
        cmd, length = struct.unpack_from('<II', data, offset)
        if length < 8 or length % 8 or offset + length > min(end, len(data)):
            errors.append(f'Invalid load command length at index {index}')
            break
        record = dict(index=index, offset=offset, command=hex(cmd), size=length)
        if cmd == LC_SEGMENT_64 and length >= 72:
            name = data[offset + 8:offset + 24].split(b'\0')[0].decode()
            va, vs, fo, fs = struct.unpack_from('<4Q', data, offset + 24)
            segments.append(dict(name=name, vmaddr=va, vmsize=vs, fileoff=fo, filesize=fs))
            if fo + fs > len(data):
                errors.append(f'Segment {name} outside file')
        elif cmd == 0x1B and length == 24:
            image_uuid = str(uuid.UUID(bytes=data[offset + 8:offset + 24]))
        elif cmd in (0x0C, 0x80000018, 0x8000001F, 0x80000023) and length >= 24:
            no = struct.unpack_from('<I', data, offset + 8)[0]
            if not 24 <= no < length:
                errors.append('Invalid dependency name offset')
            else:
                dependencies.append(data[offset + no:offset + length].split(b'\0')[0].decode(errors='replace'))
        elif cmd in (0x22, 0x80000022) and length == 48:
            bind_ranges = struct.unpack_from('<10I', data, offset + 8)
        elif cmd == LC_DYSYMTAB:
            record['name'] = 'LC_DYSYMTAB'
            if length != 80:
                errors.append(f'LC_DYSYMTAB size {length}, required 80')
        elif cmd == LC_ID_DYLIB:
            record['name'] = 'LC_ID_DYLIB'
            name_offset = struct.unpack_from('<I', data, offset + 8)[0] if length >= 24 else 0
            if not 24 <= name_offset < length:
                errors.append(f'LC_ID_DYLIB invalid name offset {name_offset}')
            else:
                name_bytes = data[offset + name_offset:offset + length]
                if b'\0' not in name_bytes:
                    errors.append('Unterminated install name')
                record['install_name'] = name_bytes.split(b'\0')[0].decode(errors='replace')
        elif cmd == LC_CODE_SIGNATURE and length == 16:
            signature = struct.unpack_from('<II', data, offset + 8)
        commands.append(record)
        offset += length
    if offset != end or len(commands) != count:
        errors.append('Load command count/size does not close')
    if sum(c['command'] == hex(LC_ID_DYLIB) for c in commands) != 1:
        errors.append('Expected exactly one LC_ID_DYLIB')
    if sum(c['command'] == hex(LC_CODE_SIGNATURE) for c in commands) != 1:
        errors.append('Expected exactly one LC_CODE_SIGNATURE')
    linkedit = next((s for s in segments if s['name'] == '__LINKEDIT'), None)
    if bind_ranges:
        for i in range(0, 10, 2):
            start, length = bind_ranges[i:i + 2]
            if length and (not linkedit or not (linkedit['fileoff'] <= start and start + length <= linkedit['fileoff'] + linkedit['filesize'])):
                errors.append(f'DYLD_INFO range {i // 2} outside __LINKEDIT')
    signature_info = None
    if not signature:
        errors.append('No code signature')
    else:
        start, length = signature
        signature_info = dict(offset=start, size=length, end=start + length)
        if not linkedit or not (linkedit['fileoff'] <= start and start + length <= linkedit['fileoff'] + linkedit['filesize']):
            errors.append('Code signature outside __LINKEDIT file range')
        if start + length > len(data):
            errors.append('Code signature outside file')
        else:
            blob = data[start:start + length]
            bm, bl, bc = struct.unpack_from('>3I', blob)
            if bm != 0xFADE0CC0 or bl > length:
                errors.append('Invalid signature SuperBlob')
            else:
                for i in range(bc):
                    slot, relative = struct.unpack_from('>II', blob, 12 + i * 8)
                    if slot != 0:
                        continue
                    cd = blob[relative:]
                    cm, cl, ver, cf, ho, io, ns, nc, limit = struct.unpack_from('>9I', cd)
                    hs, ht, platform, shift = cd[36:40]
                    if cm != 0xFADE0C02 or cl > len(cd) or shift > 20 or hs != 32 or ht != 2:
                        errors.append('Unsupported or invalid CodeDirectory')
                        continue
                    page = 1 << shift
                    if limit != start or nc != (limit + page - 1) // page or ho + nc * hs > cl:
                        errors.append('CodeDirectory coverage or hash table invalid')
                        continue
                    bad = []
                    for p in range(nc):
                        # The final partial page is hashed at its actual length, without zero padding.
                        chunk = data[p * page:min((p + 1) * page, limit)]
                        if hashlib.sha256(chunk).digest() != cd[ho + p * hs:ho + (p + 1) * hs]:
                            bad.append(p)
                    signature_info.update(code_directory_version=hex(ver), code_limit=limit,
                                          page_count=nc, mismatched_pages=bad)
                    if bad:
                        errors.append(f'SHA256 code page mismatch: {bad}')
    return dict(file=str(Path(path).resolve()), bytes=len(data), sha256=hashlib.sha256(data).hexdigest(), uuid=image_uuid,
                dependencies=dependencies,
                commands=commands, segments=segments, signature=signature_info, errors=errors,
                passed=not errors, scope='Selected structural and SHA256 checks; not proof of device compatibility')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('file')
    parser.add_argument('--json-out')
    args = parser.parse_args()
    result = audit(args.file)
    encoded = json.dumps(result, ensure_ascii=False, indent=2)
    if args.json_out:
        Path(args.json_out).write_text(encoded, encoding='utf-8')
    print(encoded)
    raise SystemExit(0 if result['passed'] else 1)
