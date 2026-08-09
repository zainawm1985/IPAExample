import struct, os, re

path = r"c:\Users\x\Desktop\插件\抖音助手（xuu）_2.0-5.dylib"
with open(path, 'rb') as f:
    data = f.read()

print(f"文件大小: {len(data)} bytes ({len(data)/1024:.1f} KB)")
print(f"前4字节: {data[:4].hex()} (cffaedfe = MH_MAGIC_64 little-endian)")

# ========================
# 1. 确认加密状态
# ========================
print("\n" + "=" * 60)
print("1. 加密状态")
print("=" * 60)

# 解析load commands找LC_ENCRYPTION_INFO_64
endian = '<'
hdr = struct.unpack_from('<IIIIIIII', data, 0)
ncmds = hdr[4]
sizeofcmds = hdr[5]
offset = 32
cmds_end = offset + sizeofcmds

while offset < cmds_end:
    cmd_start = offset
    cmd_type, cmd_size = struct.unpack_from('<II', data, offset)
    offset += 8
    if cmd_type == 0x2C:  # LC_ENCRYPTION_INFO_64
        off, sz, cryptid = struct.unpack_from('<III', data, cmd_start + 8)
        status = "❌ 已加密 (FairPlay DRM)" if cryptid != 0 else "✅ 未加密 (cryptid=0)"
        print(f"  LC_ENCRYPTION_INFO_64: offset=0x{off:X} size=0x{sz:X}")
        print(f"  加密状态: {status}")
        print(f"  → 二进制可被直接分析（otool/class-dump/Hopper可读）")
        break
else:
    print("  未找到LC_ENCRYPTION_INFO_64 → 未加密")

# ========================
# 2. 提取所有可读字符串
# ========================
print("\n" + "=" * 60)
print("2. 关键字符串提取 (URL/类名/方法名/日志)")
print("=" * 60)

# 提取所有ASCII字符串 (>=4字符)
strings = []
i = 0
cur = []
while i < len(data):
    b = data[i]
    if 0x20 <= b < 0x7f:
        cur.append(chr(b))
    else:
        if len(cur) >= 4:
            strings.append(''.join(cur))
        cur = []
    i += 1
if len(cur) >= 4:
    strings.append(''.join(cur))

# 分类过滤
urls = [s for s in strings if s.startswith('http://') or s.startswith('https://')]
objc_sels = [s for s in strings if s.count(':') >= 1 and len(s) < 80 and not s.startswith('http') and not '/' in s[:5] and not s.startswith('@')]
log_msgs = [s for s in strings if any(k in s.lower() for k in ['nslog', 'log', 'error', 'fail', 'success', 'download', 'video', 'douyin', 'aweme', 'hook', 'tweak', 'xuu', 'dyzs'])]
class_names = [s for s in strings if re.match(r'^[A-Z][a-zA-Z]{3,30}View$', s) or re.match(r'^[A-Z][a-zA-Z]{3,30}Manager$', s) or re.match(r'^DYZS', s)]

print(f"\n--- URL ({len(urls)}个) ---")
for u in sorted(set(urls)):
    print(f"  {u}")

print(f"\n--- 自定义类名 ({len(set(class_names))}个) ---")
for c in sorted(set(class_names)):
    print(f"  {c}")

print(f"\n--- 日志/关键字符串 (含douyin/aweme/download/hook等, 前60个) ---")
interesting = [s for s in log_msgs if len(s) > 8 and len(s) < 200]
for s in sorted(set(interesting))[:60]:
    print(f"  {s}")

# ========================
# 3. 提取ObjC方法名 (from __objc_methname section)
# ========================
print("\n" + "=" * 60)
print("3. ObjC 方法名/选择器 (从字符串表提取)")
print("=" * 60)

# 找所有看起来像ObjC方法名的字符串
method_patterns = [
    r'^[a-z][a-zA-Z]+:$',           # foo:
    r'^[a-z][a-zA-Z]+:[a-z][a-zA-Z]*:.*$',  # foo:bar:
    r'^[a-z][a-zA-Z]+With[a-zA-Z]+:$',
    r'^set[A-Z][a-zA-Z]+:$',
    r'^is[A-Z][a-zA-Z]+$',
    r'^has[A-Z][a-zA-Z]+$',
    r'^init$',
    r'^dealloc$',
    r'^load$',
]

objc_methods = set()
for s in strings:
    for pat in method_patterns:
        if re.match(pat, s):
            objc_methods.add(s)
            break

# 也找DYZS/DouyinHelper相关
for s in strings:
    if any(k in s for k in ['DYZS', 'DouyinHelper', 'xuu', 'Aweme', 'AWE', 'TTVideo', 'FeedCell', 'Comment']):
        if len(s) < 120:
            objc_methods.add(s)

print(f"\n--- ObjC方法/选择器 (前100个共{len(objc_methods)}个) ---")
for m in sorted(objc_methods)[:100]:
    print(f"  {m}")

# ========================
# 4. 找特定抖音相关符号
# ========================
print("\n" + "=" * 60)
print("4. 抖音/Aweme 相关符号 (逆向线索)")
print("=" * 60)

aweme_related = set()
for s in strings:
    sl = s.lower()
    if any(k in sl for k in ['aweme', 'douyin', 'feedcell', 'comment', 'like', 'download', 'videoinfo',
                              'playervc', 'detailvc', 'homevc', 'tabbar', 'fullscreen',
                              'no_watermark', 'nowatermark', 'watermark', 'share', 'export',
                              'ffmpeg', 'avasset', 'avplayer', 'phasset', 'uipasteboard',
                              'nsfilemanager', 'downloadtask', 'session', 'afnetworking',
                              'md5', 'sha', 'encrypt', 'decrypt', 'sign', 'token',
                              'awkits', 'awkit', 'imkit', 'bytetoast', 'bytedance']):
        if 4 < len(s) < 150:
            aweme_related.add(s)

print(f"\n--- 抖音/下载/水印相关字符串 ({len(aweme_related)}个, 前80个) ---")
for s in sorted(aweme_related)[:80]:
    print(f"  {s}")
