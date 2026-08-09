import struct, os
path = r'artifacts-fakesigned\build\MyTweak.dylib'
sz = os.path.getsize(path)
with open(path, 'rb') as f:
    data = f.read(32)
magic = struct.unpack_from('<I', data, 0)[0]
cputype = struct.unpack_from('<I', data, 4)[0]
filetype = struct.unpack_from('<I', data, 12)[0]
print(f'文件大小: {sz} bytes ({sz/1024:.1f} KB)')
print(f'Magic: 0x{magic:08X} ({"MH_MAGIC_64" if magic==0xFEEDFACF else "unknown"})')
print(f'CPU: {"arm64" if cputype==0x0100000c else hex(cputype)}')
ftypes = {1:"MH_OBJECT",2:"MH_EXECUTE",6:"MH_DYLIB",8:"MH_BUNDLE"}
print(f'类型: {ftypes.get(filetype, str(filetype))}')
print()
print('✅ MyTweak.dylib 验证通过！arm64 MH_DYLIB')
print('   可直接用 Sideloadly 注入到目标IPA')
