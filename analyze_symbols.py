import struct

path = r"c:\Users\x\Desktop\插件\抖音助手（xuu）_2.0-5.dylib"
with open(path, 'rb') as f:
    data = f.read()

# Mach-O constants
MH_MAGIC_64 = 0xFEEDFACF
LC_SEGMENT_64 = 0x19
LC_SYMTAB = 0x2
LC_DYSYMTAB = 0xB
endian = '<'  # little endian for arm64

# 找符号表
base = 0
hdr = struct.unpack_from('<IIIIIIII', data, base)
ncmds = hdr[4]
sizeofcmds = hdr[5]
hdr_size = 32

offset = base + hdr_size
cmds_end = offset + sizeofcmds

linkedit_vmaddr = None
linkedit_fileoff = None
symtab_off = None
symtab_nsyms = None
strtab_off = None
strtab_size = None

# 获取__LINKEDIT的vm和file偏移映射
while offset < cmds_end:
    cmd_start = offset
    cmd_type, cmd_size = struct.unpack_from('<II', data, offset)
    offset += 8
    
    if cmd_type == LC_SEGMENT_64:
        name_bytes = data[cmd_start + 8:cmd_start + 8 + 16]
        seg_name = name_bytes.split(b'\x00', 1)[0].decode('ascii', errors='replace')
        vmaddr, vmsize, fileoff, filesize = struct.unpack_from('<QQQQ', data, cmd_start + 24)
        if seg_name == "__LINKEDIT":
            linkedit_vmaddr = vmaddr
            linkedit_fileoff = fileoff
            print(f"__LINKEDIT: vm=0x{vmaddr:X} fileoff=0x{fileoff:X}")
    elif cmd_type == LC_SYMTAB:
        symoff, nsyms, stroff, strsize = struct.unpack_from('<IIII', data, cmd_start + 8)
        symtab_off = symoff
        symtab_nsyms = nsyms
        strtab_off = stroff
        strtab_size = strsize
        print(f"LC_SYMTAB: symoff=0x{symoff:X} nsyms={nsyms} stroff=0x{stroff:X} strsize=0x{strsize:X}")
    
    offset = cmd_start + cmd_size

# 读取符号
if symtab_off and strtab_off:
    # nlist_64: struct nlist_64 { union { uint32_t n_strx; } n_un; uint8_t n_type; uint8_t n_sect; int16_t n_desc; uint64_t n_value; };
    # size = 4 + 1 + 1 + 2 + 8 = 16
    print("\n========== 关键符号 ==========")
    
    constructors = []
    ms_hooks = []
    exports = []
    objc_classes = []
    objc_methods = []
    
    for i in range(symtab_nsyms):
        sym_offset = symtab_off + i * 16
        if sym_offset + 16 > len(data):
            break
        n_strx, n_type, n_sect, n_desc, n_value = struct.unpack_from('<IBBHQ', data, sym_offset)
        
        if n_strx >= strtab_size:
            continue
        str_offset = strtab_off + n_strx
        name_bytes = data[str_offset:str_offset + 512]
        if b'\x00' in name_bytes:
            name = name_bytes.split(b'\x00', 1)[0].decode('utf-8', errors='replace')
        else:
            name = name_bytes.decode('utf-8', errors='replace')
        
        # N_TYPE mask = 0x0E, N_EXT = 0x01
        n_type_stripped = n_type & 0x0E
        is_external = (n_type & 0x01) != 0
        
        if not name:
            continue
        
        name_lower = name.lower()
        
        # 找constructor
        if "constructor" in name_lower or name.startswith("_init") or "initialize" in name_lower:
            constructors.append((name, f"0x{n_value:X}"))
        
        # 找MSHook... CydiaSubstrate hooks
        if name.startswith("_MS") or "MSHook" in name or "hook" in name_lower:
            ms_hooks.append((name, f"0x{n_value:X}"))
        
        # 找%hook / logos / 默认注入入口
        if "logos" in name_lower:
            exports.append((name, f"0x{n_value:X}"))
        
        # Objc相关
        if name.startswith("_OBJC_CLASS_$_") or name.startswith("_OBJC_METACLASS_$_"):
            if len(objc_classes) < 50:
                objc_classes.append(name)
        
        # +load, constructor
        if "load" == name_lower or name in ("+[TestObject load]",):
            exports.append((name, f"0x{n_value:X}"))
        
        if "douyin" in name_lower or "aweme" in name_lower:
            if len(objc_methods) < 50:
                objc_methods.append((name, f"0x{n_value:X}"))
    
    print(f"\n--- Constructor / 初始化入口 (可能含Tweak注入点) ---")
    for name, val in constructors[:40]:
        print(f"  {val}  {name}")
    
    print(f"\n--- CydiaSubstrate/MSHook相关符号 ---")
    for name, val in ms_hooks[:40]:
        print(f"  {val}  {name}")
    
    print(f"\n--- 自定义注入/Logos相关符号 ---")
    for name, val in exports[:40]:
        print(f"  {val}  {name}")
    
    print(f"\n--- Objc Classes (前50个共{len(objc_classes)}个) ---")
    for cls in objc_classes[:50]:
        print(f"  {cls}")
    
    print(f"\n--- 抖音/Aweme相关符号 (前50个) ---")
    for name, val in objc_methods[:50]:
        print(f"  {val}  {name}")

    print(f"\n--- 外部引用符号 (dlsym/MSHookMessageReceiver使用) ---")
    # 找所有 undefined symbols (N_UNDF = 0x0)
    undefineds = []
    for i in range(symtab_nsyms):
        sym_offset = symtab_off + i * 16
        if sym_offset + 16 > len(data):
            break
        n_strx, n_type, n_sect, n_desc, n_value = struct.unpack_from('<IBBHQ', data, sym_offset)
        if (n_type & 0x0E) == 0x0:  # N_UNDF
            if n_strx < strtab_size:
                str_offset = strtab_off + n_strx
                name_bytes = data[str_offset:str_offset + 512]
                if b'\x00' in name_bytes:
                    name = name_bytes.split(b'\x00', 1)[0].decode('utf-8', errors='replace')
                else:
                    name = name_bytes.decode('utf-8', errors='replace')
                if name and not name.startswith('dyld_stub_binder'):
                    undefineds.append(name)
    # 过滤有趣的
    interesting = [s for s in undefineds if any(k in s.lower() for k in 
                   ['ms', 'hook', 'method', 'class', 'msg', 'obhc', 'mshook',
                    'constructor', 'init', 'logos', 'objc_', 'dlsym', 'dlopen'])]
    for s in sorted(set(interesting))[:50]:
        print(f"  {s}")
