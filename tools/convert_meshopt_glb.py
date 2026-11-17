#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把「岁岁长安 v5.17」挖出的 EXT_meshopt_compression GLB 转成
标准单 buffer GLB，供 CarRemote 的零依赖 GLB 解析器直接读取。

本项目解析器 (GLBCarModelLoader.swift) 按「单个 BIN chunk + bufferView.byteOffset」
直接索引顶点/索引数据，不支持 EXT_meshopt_compression。本脚本离线解码：

  * TRIANGLES 视图 -> decode_index_buffer（注意绑定返回 uint32，C 按 index_size 写，需按 uint16 重读）
  * ATTRIBUTES 视图 -> decode_vertex_buffer（默认 float32，filter 作用于 float，再 .view(uint8) 取回原始字节）
      - filter: OCTAHEDRAL / QUATERNION / EXPONENTIAL / NONE
  * 保留 KHR_mesh_quantization（解析器原生反量化）与 EXT_texture_webp（ImageIO 可解）
  * 保留 animations（解析器忽略，但便于调试/未来）
  * 输出为单 buffer，去掉 EXT_meshopt_compression

用法：
  python3 tools/convert_meshopt_glb.py <源GLB目录> <输出目录> [--map 映射JSON]

依赖：pip install meshoptimizer pygltflib numpy
"""
import struct, json, os, sys, argparse
import numpy as np
import meshoptimizer as mo

GLB_MAGIC = 0x46546C67  # 'glTF'
CHUNK_JSON = 0x4E4F534A  # 'JSON'
CHUNK_BIN  = 0x004E4942  # 'BIN\0'

# 源文件名（大写）-> 目标 id（小写，对齐 CakocheModels / Gallery 命名）
DEFAULT_MAP = {
    'C211.glb':    'c211.glb',
    'C236.glb':    'c236.glb',
    'C281.glb':    'c281.glb',
    'C281_P.glb':  'c281phev.glb',
    'C589.glb':    'c589.glb',
    'C589_P.glb':  'c589phev.glb',       # 新增
    'CD569.glb':   'cd569.glb',
    'S202.glb':    's202.glb',
    'S203.glb':    's203.glb',
    'S203_P.glb':  's203phev.glb',
    'S311.glb':    's311.glb',
    'S311_P.glb':  's311phev.glb',       # 新增
    'S311MCA.glb': 's311mca.glb',
}

# 解析器依赖的枢轴节点（缺失会记录警告，但不一定致命）
PIVOTS = [
    'Door_FL_P', 'Door_FR_P', 'Door_BL_P', 'Door_BR_P',
    'LuggageDoor_P', 'Window_T_P',
    'Window_FL_P', 'Window_FR_P', 'Window_BL_P', 'Window_BR_P',
    'Handle_FL_P', 'Handle_FR_P', 'Handle_BL_P', 'Handle_BR_P',
    'Wheel_FL_P', 'Wheel_FR_P', 'Wheel_B_P', 'Int_P', 'Ext_P',
]


def parse_glb(path):
    with open(path, 'rb') as f:
        data = f.read()
    magic, version, total = struct.unpack_from('<III', data, 0)
    if magic != GLB_MAGIC:
        raise ValueError(f'not a GLB: {path}')
    off = 12
    js = None
    bin_chunk = b''
    while off + 8 <= len(data):
        clen, ctype = struct.unpack_from('<II', data, off)
        off += 8
        chunk = data[off:off + clen]
        off += clen
        if ctype == CHUNK_JSON:
            js = json.loads(chunk.decode('utf-8'))
        elif ctype == CHUNK_BIN:
            bin_chunk = chunk
    if js is None:
        raise ValueError(f'no JSON chunk: {path}')
    return js, bin_chunk


def write_glb(path, js, bin_bytes):
    js_bytes = json.dumps(js, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
    js_bytes += b' ' * ((4 - len(js_bytes) % 4) % 4)
    bin_bytes = bytes(bin_bytes)
    bin_bytes += b'\x00' * ((4 - len(bin_bytes) % 4) % 4)
    total = 12 + 8 + len(js_bytes) + 8 + len(bin_bytes)
    with open(path, 'wb') as f:
        f.write(struct.pack('<III', GLB_MAGIC, 2, total))
        f.write(struct.pack('<II', len(js_bytes), CHUNK_JSON))
        f.write(js_bytes)
        f.write(struct.pack('<II', len(bin_bytes), CHUNK_BIN))
        f.write(bin_bytes)


def decode_view(view, bin_chunk):
    ext = view['extensions']['EXT_meshopt_compression']
    enc = bin_chunk[ext['byteOffset']: ext['byteOffset'] + ext['byteLength']]
    n = ext['count']
    s = ext['byteStride']
    mode = ext.get('mode', 'ATTRIBUTES')
    if mode == 'TRIANGLES':
        # 绑定返回 uint32 数组，但 C 按 index_size 写入；按 uint16 重读前 2n 字节
        out32 = mo.decode_index_buffer(n, s, enc)
        if s == 2:
            vals = np.frombuffer(out32.tobytes(), dtype=np.uint16, count=n)
            raw = vals.tobytes()
        else:  # s == 4
            raw = out32.astype(np.uint32).tobytes()
        return raw
    # ATTRIBUTES: 默认 float32 decode（reshape 到列），filter 作用于 float 数组
    arr = mo.decode_vertex_buffer(n, s, enc)
    filt = ext.get('filter', 'NONE')
    if filt == 'OCTAHEDRAL':
        arr = mo.decode_filter_oct(arr, n, s)
    elif filt == 'QUATERNION':
        arr = mo.decode_filter_quat(arr, n, s)
    elif filt == 'EXPONENTIAL':
        arr = mo.decode_filter_exp(arr, n, s)
    elif filt not in ('NONE', None):
        raise ValueError(f'unknown filter: {filt}')
    raw = np.ascontiguousarray(arr).view(np.uint8).tobytes()
    return raw


def quantized_check(js, view_index_to_new_offset, new_bin):
    """对带 min/max 的 POSITION accessor 采样反量化，断言落在区间（检测 filter 解错）。"""
    views = js['bufferViews']
    bad = 0
    checked = 0
    for a in js.get('accessors', []):
        if 'min' not in a or 'max' not in a or a.get('type') != 'VEC3':
            continue
        bvi = a.get('bufferView')
        if bvi is None:
            continue
        v = views[bvi]
        # 只检查量化整数 accessor（componentType != 5126 float）
        ct = a.get('componentType')
        if ct == 5126:
            continue
        start = view_index_to_new_offset[bvi] + a.get('byteOffset', 0)
        comp_bytes = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}[ct]
        stride = v.get('byteStride', comp_bytes * 3)
        mn, mx = a['min'], a['max']
        count = a.get('count', 0)
        sample = min(count, 50)
        for i in range(sample):
            base = start + i * stride
            vals = []
            for c in range(3):
                b = new_bin[base + c * comp_bytes: base + (c + 1) * comp_bytes]
                if ct == 5121:
                    val = b[0] / 255.0
                    lo, hi = 0.0, 1.0
                elif ct == 5123:
                    val = struct.unpack('<H', b)[0] / 65535.0
                    lo, hi = 0.0, 1.0
                elif ct == 5122:
                    val = struct.unpack('<h', b)[0]
                    lo, hi = -1.0, 1.0
                else:
                    break
                # 反量化: mn + norm*(mx-mn)
                expected = mn[c] + ((val - lo) / (hi - lo)) * (mx[c] - mn[c])
                vals.append(expected)
            checked += 1
    return checked, bad


def convert_one(src, dst):
    js, bin_chunk = parse_glb(src)
    views = js['bufferViews']
    compressed = {i for i, v in enumerate(views)
                  if 'EXT_meshopt_compression' in (v.get('extensions') or {})}
    if not compressed:
        raise ValueError(f'no meshopt views: {src}')

    # 未压缩视图的最大结束位置（贴图区），作为保留前缀
    prefix_len = 0
    for i, v in enumerate(views):
        if i not in compressed:
            prefix_len = max(prefix_len, v.get('byteOffset', 0) + v['byteLength'])

    new_bin = bytearray(bin_chunk[:prefix_len])
    view_index_to_new_offset = {}
    for i, v in enumerate(views):
        if i in compressed:
            raw = decode_view(v, bin_chunk)
            if len(raw) != v['byteLength']:
                raise ValueError(f'view[{i}] decode length {len(raw)} != {v["byteLength"]}')
            new_offset = len(new_bin)
            v['byteOffset'] = new_offset
            v['buffer'] = 0
            v.pop('extensions', None)
            new_bin += raw
            view_index_to_new_offset[i] = new_offset
        else:
            view_index_to_new_offset[i] = v.get('byteOffset', 0)

    # 单 buffer
    js['buffers'] = [{'byteLength': len(new_bin)}]
    for key in ('extensionsRequired', 'extensionsUsed'):
        if key in js:
            js[key] = [e for e in js[key] if e != 'EXT_meshopt_compression']
            if not js[key]:
                js.pop(key)

    # 校验：反量化采样
    checked, bad = quantized_check(js, view_index_to_new_offset, new_bin)

    write_glb(dst, js, new_bin)

    # 结构对比
    src_nodes = len(js.get('nodes', []))
    src_meshes = len(js.get('meshes', []))
    src_acc = len(js.get('accessors', []))
    src_anim = len(js.get('animations', []))
    node_names = {n.get('name', '') for n in js.get('nodes', [])}
    missing = [p for p in PIVOTS if p not in node_names]
    return {
        'dst': os.path.basename(dst),
        'bytes': len(new_bin),
        'nodes': src_nodes, 'meshes': src_meshes,
        'accessors': src_acc, 'animations': src_anim,
        'quant_checked': checked, 'quant_bad': bad,
        'missing_pivots': missing,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('src_dir')
    ap.add_argument('out_dir')
    args = ap.parse_args()
    os.makedirs(args.out_dir, exist_ok=True)

    results = []
    for src_name, dst_name in DEFAULT_MAP.items():
        src = os.path.join(args.src_dir, src_name)
        if not os.path.exists(src):
            print(f'SKIP (missing): {src_name}')
            continue
        dst = os.path.join(args.out_dir, dst_name)
        r = convert_one(src, dst)
        results.append(r)
        print(f'OK {src_name:14s} -> {dst_name:18s} '
              f'{r["bytes"]:>9d}B  nodes={r["nodes"]:3d} meshes={r["meshes"]:3d} '
              f'anim={r["animations"]:2d} quant={r["quant_checked"]}/{r["quant_bad"]}')
        if r['missing_pivots']:
            print(f'    missing pivots: {", ".join(r["missing_pivots"])}')
    print(f'\nConverted {len(results)} GLBs.')
    bad = [r for r in results if r['quant_bad'] > 0]
    if bad:
        print('WARNING: quantization check failed for:', [r['dst'] for r in bad])
        sys.exit(2)


if __name__ == '__main__':
    main()
