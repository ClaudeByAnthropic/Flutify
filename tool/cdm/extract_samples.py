# fMP4 CENC 样本提取：解析 moof/traf/trun/senc/tenc → samples.bin（cdm_host 输入）。
# 用法：python tool/cdm/extract_samples.py <in.m4a> <samples.bin>
import struct, sys

def parse_boxes(data, start, end):
    boxes = []
    i = start
    while i + 8 <= end:
        size, typ = struct.unpack('>I4s', data[i:i+8])
        hdr = 8
        if size == 1:
            size = struct.unpack('>Q', data[i+8:i+16])[0]
            hdr = 16
        elif size == 0:
            size = end - i
        boxes.append((typ, i, i + hdr, i + size))
        i += size
    return boxes

def find(data, start, end, path):
    """按路径查找子 box，path 如 [b'traf', b'senc']"""
    boxes = parse_boxes(data, start, end)
    for typ, b_start, s, e in boxes:
        if typ == path[0]:
            if len(path) == 1:
                return (s, e)
            return find(data, s, e, path[1:])
    return None

def main():
    src, dst = sys.argv[1], sys.argv[2]
    data = open(src, 'rb').read()
    top = parse_boxes(data, 0, len(data))

    # tenc：默认 IV 尺寸与加密模式（version+flags 4B, reserved 1B, IsProtected 1B, IVsize 1B, KID 16B）
    tenc = find(data, 0, len(data), [b'moov', b'trak', b'mdia', b'minf', b'stbl', b'stsd', b'enca', b'sinf', b'schi', b'tenc'])
    default_iv_size = 8
    if tenc:
        body = data[tenc[0]:tenc[1]]
        default_iv_size = body[6]
        print('tenc: iv_size=%d' % default_iv_size)

    samples = []
    for typ, b_start, s, e in top:
        if typ != b'moof':
            continue
        # base_data_offset 或默认 = moof 起点（包含 box 头部）；trun data_offset 相对它
        traf = find(data, s, e, [b'traf'])
        if not traf:
            continue
        moof_samples = []
        tfhd_box = find(data, traf[0], traf[1], [b'tfhd'])
        base_off = b_start  # 默认 moof 起点
        default_size = 0
        if tfhd_box:
            body = data[tfhd_box[0]:tfhd_box[1]]
            flags = struct.unpack('>I', body[1:4])[0] if False else int.from_bytes(body[0:4], 'big') & 0xFFFFFF
            p = 4
            track_id = struct.unpack('>I', body[p:p+4])[0]; p += 4
            if flags & 0x1:  # base-data-offset-present
                base_off = struct.unpack('>Q', body[p:p+8])[0]; p += 8
            if flags & 0x2: p += 4  # sample-description-index
            if flags & 0x8:  # default-sample-size-present
                default_size = struct.unpack('>I', body[p:p+4])[0]
        senc_box = find(data, traf[0], traf[1], [b'senc'])
        ivs = []
        if senc_box:
            body = data[senc_box[0]:senc_box[1]]
            ver_flags = int.from_bytes(body[0:4], 'big')
            flags = ver_flags & 0xFFFFFF
            count = struct.unpack('>I', body[4:8])[0]
            p = 8
            for _ in range(count):
                iv = body[p:p+default_iv_size]; p += default_iv_size
                nsub = 0
                subs = []
                if flags & 0x2:  # use-subsample-encryption
                    nsub = struct.unpack('>H', body[p:p+2])[0]; p += 2
                    for _s in range(nsub):
                        clear, cipher = struct.unpack('>HI', body[p:p+6]); p += 6
                        subs.append((clear, cipher))
                ivs.append((iv, subs))

        # trun：样本尺寸与数据偏移
        idx_in_traf = 0
        for typ2, b2, s2, e2 in parse_boxes(data, traf[0], traf[1]):
            if typ2 != b'trun':
                continue
            body = data[s2:e2]
            ver_flags = int.from_bytes(body[0:4], 'big')
            flags = ver_flags & 0xFFFFFF
            count = struct.unpack('>I', body[4:8])[0]
            p = 8
            data_offset = 0
            if flags & 0x1:
                data_offset = struct.unpack('>i', body[p:p+4])[0]; p += 4
            if flags & 0x4: p += 4  # first-sample-flags
            off = base_off + data_offset
            for k in range(count):
                dur = 0; size = default_size
                if flags & 0x100: p += 4
                if flags & 0x200:
                    size = struct.unpack('>I', body[p:p+4])[0]; p += 4
                if flags & 0x400: p += 4
                if flags & 0x800: p += 4
                moof_samples.append((off, size))
                off += size
        # 本 moof 内配对：有 senc 的样本加密，否则明文（iv=None）
        for k, (off, size) in enumerate(moof_samples):
            iv, subs = ivs[k] if k < len(ivs) else (b'', [])
            samples.append((off, size, iv, subs))

    # 输出
    n = len(samples)
    enc = sum(1 for s in samples if s[2])
    print('样本=%d 其中加密=%d 明文=%d' % (n, enc, n - enc))
    with open(dst, 'wb') as out:
        out.write(struct.pack('<I', n))
        for off, size, iv, subs in samples:
            out.write(struct.pack('<I', len(iv)))
            out.write(iv)
            out.write(struct.pack('<I', len(subs)))
            for clear, cipher in subs:
                out.write(struct.pack('<II', clear, cipher))
            chunk = data[off:off+size]
            out.write(struct.pack('<I', len(chunk)))
            out.write(chunk)
    print('saved ->', dst)

if __name__ == '__main__':
    main()
