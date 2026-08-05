import struct
import sys

path = r"c:\Users\x\Desktop\插件\抖音助手（xuu）_2.0-5.dylib"
with open(path, 'rb') as f:
    data = f.read()

print(f"文件大小: {len(data)} bytes ({len(data)/1024:.1f} KB)")
print(f"前16字节 (hex): {data[:16].hex()}")

# Mach-O magic numbers
MH_MAGIC = 0xFEEDFACE
MH_CIGAM = 0xCEFAEDFE
MH_MAGIC_64 = 0xFEEDFACF
MH_CIGAM_64 = 0xCFFAEDFE
FAT_MAGIC = 0xCAFEBABE
FAT_CIGAM = 0xBEBAFECA

magic = struct.unpack_from('<I', data, 0)[0]
print(f"\nMagic number: 0x{magic:08X}")

def parse_macho_header(data, base_offset):
    submagic = struct.unpack_from('<I', data, base_offset)[0]
    print(f"  Sub-magic: 0x{submagic:08X}")
    
    filetypes = {1:"MH_OBJECT", 2:"MH_EXECUTE", 3:"MH_FVMLIB", 4:"MH_CORE",
                 5:"MH_PRELOAD", 6:"MH_DYLIB", 7:"MH_DYLINKER", 8:"MH_BUNDLE",
                 9:"MH_DYLIB_STUB", 10:"MH_DSYM", 11:"MH_KEXT_BUNDLE"}
    
    if submagic in (MH_MAGIC_64, MH_CIGAM_64):
        is_64 = True
        endian = '<' if submagic == MH_MAGIC_64 else '>'
        hdr = struct.unpack_from(f'{endian}IIIIIIII', data, base_offset)
        hdr_size = 32
    elif submagic in (MH_MAGIC, MH_CIGAM):
        is_64 = False
        endian = '<' if submagic == MH_MAGIC else '>'
        hdr = struct.unpack_from(f'{endian}IIIIIII', data, base_offset)
        hdr_size = 28
    else:
        print(f"  未知的Mach-O magic: 0x{submagic:08X}")
        return None
    
    magic_n, cputype, cpusubtype, filetype, ncmds, sizeofcmds, flags = hdr[:7]
    arch_map = {
        (12, 0): "armv7", (12, 9): "armv7s", (12, 11): "armv7k",
        (0x0100000c, 0): "arm64", (0x0100000c, 2): "arm64e",
        (7, 0): "x86", (0x01000007, 3): "x86_64", (0x01000007, 4): "x86_64h",
    }
    arch = arch_map.get((cputype, cpusubtype), f"cpu{cputype}:sub{cpusubtype}")
    
    print(f"  架构: {arch}")
    print(f"  文件类型: {filetypes.get(filetype, str(filetype))}")
    print(f"  加载命令数: {ncmds}")
    print(f"  加载命令总大小: {sizeofcmds} bytes")
    print(f"  Flags: 0x{flags:08X}")
    
    # 解析加载命令
    offset = base_offset + hdr_size
    cmds_end = offset + sizeofcmds
    dylibs = []
    install_name = None
    rpaths = []
    reexports = []
    lc_values = {}
    
    while offset < cmds_end:
        cmd_start = offset
        cmd_type, cmd_size = struct.unpack_from(f'{endian}II', data, offset)
        offset += 8
        
        # LC_DYLIB (0xC): 6, LC_LOAD_DYLIB=0xC, LC_ID_DYLIB=0xD, LC_RPATH=0x1C, LC_REEXPORT_DYLIB=0x1F
        LC_LOAD_DYLIB = 0xC
        LC_ID_DYLIB = 0xD
        LC_RPATH = 0x1C
        LC_REEXPORT_DYLIB = 0x1F
        LC_LOAD_WEAK_DYLIB = 0x80000018
        LC_ENCRYPTION_INFO = 0x21
        LC_ENCRYPTION_INFO_64 = 0x2C
        LC_BUILD_VERSION = 0x32
        LC_UUID = 0x1B
        LC_CODE_SIGNATURE = 0x1D
        LC_SEGMENT_64 = 0x19
        LC_SEGMENT = 0x1
        
        lc_name = {
            0x1: "LC_SEGMENT", 0x2: "LC_SYMTAB", 0x3: "LC_SYMSEG", 0x4: "LC_THREAD",
            0x5: "LC_UNIXTHREAD", 0x6: "LC_LOADFVMLIB", 0x7: "LC_IDFVMLIB",
            0x8: "LC_IDENT", 0x9: "LC_FVMFILE", 0xA: "LC_PREPAGE", 0xB: "LC_DYSYMTAB",
            0xC: "LC_LOAD_DYLIB", 0xD: "LC_ID_DYLIB", 0xE: "LC_LOAD_DYLINKER",
            0xF: "LC_ID_DYLINKER", 0x10: "LC_PREBOUND_DYLIB", 0x11: "LC_ROUTINES",
            0x12: "LC_SUB_FRAMEWORK", 0x13: "LC_SUB_UMBRELLA", 0x14: "LC_SUB_CLIENT",
            0x15: "LC_SUB_LIBRARY", 0x16: "LC_TWOLEVEL_HINTS", 0x17: "LC_PREBIND_CKSUM",
            0x18: "LC_LOAD_WEAK_DYLIB", 0x19: "LC_SEGMENT_64", 0x1A: "LC_ROUTINES_64",
            0x1B: "LC_UUID", 0x1C: "LC_RPATH", 0x1D: "LC_CODE_SIGNATURE",
            0x1E: "LC_SEGMENT_SPLIT_INFO", 0x1F: "LC_REEXPORT_DYLIB",
            0x21: "LC_ENCRYPTION_INFO", 0x2C: "LC_ENCRYPTION_INFO_64",
            0x32: "LC_BUILD_VERSION", 0x80000018: "LC_LOAD_WEAK_DYLIB",
        }.get(cmd_type, f"LC_{cmd_type:#x}")
        
        if cmd_type in (LC_LOAD_DYLIB, LC_ID_DYLIB, LC_REEXPORT_DYLIB, LC_LOAD_WEAK_DYLIB):
            # struct dylib_command: offset, timestamp, current_version, compatibility_version
            name_offset = struct.unpack_from(f'{endian}I', data, cmd_start + 8)[0]
            name_start = cmd_start + name_offset
            name_bytes = data[name_start:cmd_start + cmd_size]
            name = name_bytes.split(b'\x00', 1)[0].decode('utf-8', errors='replace')
            
            if cmd_type == LC_ID_DYLIB:
                install_name = name
                print(f"\n  [LC_ID_DYLIB] 安装名: {name}")
            elif cmd_type == LC_LOAD_DYLIB:
                dylibs.append(name)
                print(f"  [LC_LOAD_DYLIB] 依赖: {name}")
            elif cmd_type == LC_REEXPORT_DYLIB:
                reexports.append(name)
                print(f"  [LC_REEXPORT_DYLIB] 重导出: {name}")
            elif cmd_type == LC_LOAD_WEAK_DYLIB:
                dylibs.append(name + " (weak)")
                print(f"  [LC_LOAD_WEAK_DYLIB] 弱依赖: {name}")
                
        elif cmd_type == LC_RPATH:
            path_offset = struct.unpack_from(f'{endian}I', data, cmd_start + 8)[0]
            path_start = cmd_start + path_offset
            path_bytes = data[path_start:cmd_start + cmd_size]
            rpath = path_bytes.split(b'\x00', 1)[0].decode('utf-8', errors='replace')
            rpaths.append(rpath)
            print(f"  [LC_RPATH] 运行路径: {rpath}")
            
        elif cmd_type in (LC_ENCRYPTION_INFO, LC_ENCRYPTION_INFO_64):
            off, size, cryptid = struct.unpack_from(f'{endian}III', data, cmd_start + 8)
            print(f"  [{lc_name}] offset=0x{off:X} size=0x{size:X} cryptid={cryptid} {'(加密)' if cryptid != 0 else '(未加密)'}")
            
        elif cmd_type == LC_CODE_SIGNATURE:
            dataoff, datasize = struct.unpack_from(f'{endian}II', data, cmd_start + 8)
            print(f"  [LC_CODE_SIGNATURE] dataoff=0x{dataoff:X} datasize=0x{datasize:X}")
            
        elif cmd_type == LC_UUID:
            uuid_bytes = data[cmd_start + 8:cmd_start + 8 + 16]
            uuid_str = '-'.join([uuid_bytes[:4].hex(), uuid_bytes[4:6].hex(), uuid_bytes[6:8].hex(),
                                 uuid_bytes[8:10].hex(), uuid_bytes[10:].hex()]).upper()
            print(f"  [LC_UUID] {uuid_str}")
            
        elif cmd_type in (LC_SEGMENT, LC_SEGMENT_64):
            name_bytes = data[cmd_start + 8:cmd_start + 8 + 16]
            seg_name = name_bytes.split(b'\x00', 1)[0].decode('ascii', errors='replace')
            if is_64:
                vmaddr, vmsize, fileoff, filesize, maxprot, initprot, nsects, flags_s = \
                    struct.unpack_from(f'{endian}QQQQIIII', data, cmd_start + 24)
            else:
                vmaddr, vmsize, fileoff, filesize, maxprot, initprot, nsects, flags_s = \
                    struct.unpack_from(f'{endian}IIIIIIII', data, cmd_start + 24)
            seg_prot_r = 'R' if (initprot & 1) else '-'
            seg_prot_w = 'W' if (initprot & 2) else '-'
            seg_prot_x = 'X' if (initprot & 4) else '-'
            if seg_name in ("__TEXT", "__DATA", "__LINKEDIT"):
                print(f"  [{lc_name}] {seg_name} vm=0x{vmaddr:X}-0x{vmaddr+vmsize:X} file=0x{fileoff:X}-0x{fileoff+filesize:X} prot={seg_prot_r}{seg_prot_w}{seg_prot_x} sections={nsects}")
        
        offset = cmd_start + cmd_size
    
    print(f"\n=== 摘要 ===")
    print(f"安装名 (install name): {install_name}")
    print(f"依赖库总数: {len(dylibs)}")
    for d in dylibs:
        print(f"  - {d}")
    if reexports:
        print(f"重导出库: {len(reexports)}")
        for r in reexports:
            print(f"  - {r}")
    if rpaths:
        print(f"@rpath 列表: {len(rpaths)}")
        for r in rpaths:
            print(f"  - {r}")
    
    return {
        "install_name": install_name,
        "dylibs": dylibs,
        "rpaths": rpaths,
        "arch": arch,
        "filetype": filetype,
        "is_64": is_64,
    }

if magic == FAT_MAGIC or magic == FAT_CIGAM:
    print("-> 这是 FAT (通用二进制) 文件")
    nfat_arch = struct.unpack_from('>I' if magic==FAT_MAGIC else '<I', data, 4)[0]
    print(f"   包含 {nfat_arch} 个架构切片\n")
    offset = 8
    endian = '>' if magic==FAT_MAGIC else '<'
    for i in range(nfat_arch):
        cputype, cpusubtype, offset2, size, align = struct.unpack_from(f'{endian}IIIII', data, offset)
        offset += 20
        arch_map2 = {
            (12, 0): "armv7", (12, 9): "armv7s",
            (0x0100000c, 0): "arm64", (0x0100000c, 2): "arm64e",
            (7, 0): "x86", (0x01000007, 3): "x86_64",
        }
        arch_name = arch_map2.get((cputype, cpusubtype), f"cpu{cputype}:sub{cpusubtype}")
        print(f"========== 架构切片 [{i}]: {arch_name} ==========")
        print(f"  文件内偏移: 0x{offset2:X}, 大小: {size} bytes")
        parse_macho_header(data, offset2)
        print()

elif magic in (MH_MAGIC, MH_CIGAM, MH_MAGIC_64, MH_CIGAM_64):
    print("-> 这是单一架构 Mach-O 文件\n")
    parse_macho_header(data, 0)
else:
    print(f"无法识别的文件格式，magic=0x{magic:08X}")
    # 尝试ZIP?
    if data[:4] == b'PK\x03\x04':
        print("-> 这看起来是ZIP文件")
