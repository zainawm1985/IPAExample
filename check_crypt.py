import zipfile, struct, os, tempfile, shutil

ipa_path = r"c:\Users\x\Desktop\插件\拼多多-8.4.0.ipa"

print("=" * 60)
print("PDD IPA 砸壳检测")
print("=" * 60)
print(f"文件: {ipa_path}")
print(f"大小: {os.path.getsize(ipa_path)/1024/1024:.1f} MB")

# 1. 解压IPA查看Info.plist
tmp = tempfile.mkdtemp()
try:
    with zipfile.ZipFile(ipa_path, 'r') as zf:
        # 找Payload目录
        payload_files = [f for f in zf.namelist() if 'Payload/' in f]
        app_dir = None
        exe_name = None
        exe_path_in_zip = None
        
        for f in payload_files:
            if f.endswith('.app/Info.plist') and not '/Frameworks/' in f:
                app_dir = '/'.join(f.split('/')[:2])  # Payload/XXX.app
                with zf.open(f) as fh:
                    plist = fh.read()
                # 从Info.plist找可执行文件名
                # 简单文本搜索 CFBundleExecutable
                plist_str = plist.decode('utf-8', errors='ignore')
                import re
                m = re.search(r'CFBundleExecutable.*?<string>(.*?)</string>', plist_str)
                if m:
                    exe_name = m.group(1)
                # 也搜Bundle名
                m2 = re.search(r'CFBundleDisplayName.*?<string>(.*?)</string>', plist_str)
                display_name = m2.group(1) if m2 else "?"
                m3 = re.search(r'CFBundleIdentifier.*?<string>(.*?)</string>', plist_str)
                bundle_id = m3.group(1) if m3 else "?"
                print(f"\n📱 App信息:")
                print(f"   显示名: {display_name}")
                print(f"   BundleID: {bundle_id}")
                break
        
        if not exe_name:
            print("\n⚠️ 无法从Info.plist解析可执行文件名，尝试从目录结构推断...")
            # 备用：取app目录下和.app同名的文件
            app_name = os.path.basename(app_dir).replace('.app', '')
            exe_name = app_name
        
        exe_path_in_zip = f"{app_dir}/{exe_name}"
        print(f"   可执行文件: {exe_name}")
        print(f"   ZIP内路径: {exe_path_in_zip}")
        
        # 2. 提取可执行文件并分析
        print(f"\n🔍 分析Mach-O头...")
        zf.extract(exe_path_in_zip, tmp)
        exe_local = os.path.join(tmp, exe_path_in_zip)
        exe_sz = os.path.getsize(exe_local)
        print(f"   可执行文件大小: {exe_sz/1024/1024:.1f} MB")
        
        with open(exe_local, 'rb') as f:
            data = f.read()
        
        # 3. 解析Mach-O
        magic = struct.unpack_from('<I', data, 0)[0]
        FAT_MAGIC = 0xCAFEBABE
        FAT_CIGAM = 0xBEBAFECA
        MH_MAGIC_64 = 0xFEEDFACF
        
        crypt_entries = []
        
        def find_encryption_info(macho_data, base_offset):
            endian = '<'
            hdr = struct.unpack_from('<IIIIIIII', macho_data, base_offset)
            ncmds = hdr[4]
            sizeofcmds = hdr[5]
            hdr_size = 32
            offset = base_offset + hdr_size
            results = []
            while offset < base_offset + hdr_size + sizeofcmds:
                cmd_start = offset
                cmd_type, cmd_size = struct.unpack_from('<II', macho_data, offset)
                if cmd_type in (0x21, 0x2C):  # LC_ENCRYPTION_INFO or LC_ENCRYPTION_INFO_64
                    off, sz, cryptid = struct.unpack_from('<III', macho_data, cmd_start + 8)
                    results.append((off, sz, cryptid))
                offset = cmd_start + cmd_size
            return results
        
        if magic == FAT_MAGIC or magic == FAT_CIGAM:
            print(f"\n📦 FAT 通用二进制文件")
            nfat = struct.unpack_from('>I', data, 4)
            print(f"   切片数: {nfat}")
            endian = '>'
            off = 8
            archs = {12: "armv7", 0x0100000c: "arm64", 0x01000007: "x86_64", 7: "x86"}
            for i in range(nfat):
                cputype = struct.unpack_from(f'{endian}I', data, off)[0]
                cpusubtype = struct.unpack_from(f'{endian}I', data, off+4)[0]
                slice_off = struct.unpack_from(f'{endian}I', data, off+8)[0]
                slice_sz = struct.unpack_from(f'{endian}I', data, off+12)[0]
                arch = archs.get(cputype, f"0x{cputype:X}")
                print(f"\n--- 切片[{i}]: {arch} 偏移=0x{slice_off:X} 大小={slice_sz} ---")
                enc = find_encryption_info(data, slice_off)
                for e_off, e_sz, cryptid in enc:
                    status = "✅ 未加密 (cryptid=0)" if cryptid == 0 else "❌ 已加密 (FairPlay DRM)"
                    crypt_entries.append({
                        "arch": arch,
                        "off": e_off,
                        "size": e_sz,
                        "cryptid": cryptid,
                        "status": status
                    })
                    print(f"   {status} | offset=0x{e_off:X} size=0x{e_sz:X} ({e_sz/1024/1024:.1f}MB加密段)")
                off += 20
        elif magic == MH_MAGIC_64:
            print(f"\n📄 单一架构 Mach-O (arm64)")
            enc = find_encryption_info(data, 0)
            for e_off, e_sz, cryptid in enc:
                status = "✅ 未加密 (cryptid=0)" if cryptid == 0 else "❌ 已加密 (FairPlay DRM)"
                crypt_entries.append({
                    "arch": "arm64",
                    "off": e_off,
                    "size": e_sz,
                    "cryptid": cryptid,
                    "status": status
                })
                print(f"   {status} | offset=0x{e_off:X} size=0x{e_sz:X} ({e_sz/1024/1024:.1f}MB加密段)")
        
        # 4. 最终结论
        print("\n" + "=" * 60)
        all_decrypted = all(e['cryptid'] == 0 for e in crypt_entries)
        if all_decrypted:
            print("✅ 结论: 已砸壳！所有切片的cryptid都为0")
            print("   这个IPA可以直接用class-dump/Hopper分析")
            print("   可以注入dylib，Sideloadly/TrollStore可用")
        else:
            encrypted = [e for e in crypt_entries if e['cryptid'] != 0]
            print(f"❌ 结论: 未砸壳！{len(encrypted)}个加密切片:")
            for e in encrypted:
                print(f"   {e['arch']}: {e['status']} ({e['size']/1024/1024:.1f}MB加密)")
            print("   这个IPA需要先砸壳才能注入或分析")
            print("   建议: 从已越狱设备用frida-ios-dump重新提取")
        
        if crypt_entries:
            print("\n详细加密信息:")
            for e in crypt_entries:
                print(f"   架构={e['arch']} 加密偏移=0x{e['off']:X} 加密大小={e['size']/1024/1024:.1f}MB cryptid={e['cryptid']} → {e['status']}")

finally:
    shutil.rmtree(tmp, ignore_errors=True)
