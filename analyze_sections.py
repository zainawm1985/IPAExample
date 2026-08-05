import struct

path = r"c:\Users\x\Desktop\插件\抖音助手（xuu）_2.0-5.dylib"
with open(path, 'rb') as f:
    data = f.read()

endian = '<'
LC_SEGMENT_64 = 0x19
LC_DYSYMTAB = 0xB
LC_SYMTAB = 0x2
MH_MAGIC_64 = 0xFEEDFACF

hdr = struct.unpack_from('<IIIIIIII', data, 0)
ncmds = hdr[4]
sizeofcmds = hdr[5]
hdr_size = 32

offset = hdr_size
cmds_end = offset + sizeofcmds

linkedit_vmaddr = None
linkedit_fileoff = None
symtab_off = None
symtab_nsyms = None
strtab_off = None
strtab_size = None
dysymtab_iextdef = None
dysymtab_nextdef = None
dysymtab_iref = None
dysymtab_nref = None

def vm_to_file(vmaddr, linkedit_vmaddr, linkedit_fileoff):
    return linkedit_fileoff + (vmaddr - linkedit_vmaddr)

sections = []  # (seg, sect, addr, size, offset)

while offset < cmds_end:
    cmd_start = offset
    cmd_type, cmd_size = struct.unpack_from('<II', data, offset)
    offset += 8
    
    if cmd_type == LC_SEGMENT_64:
        seg_name_bytes = data[cmd_start + 8:cmd_start + 8 + 16]
        seg_name = seg_name_bytes.split(b'\x00', 1)[0].decode('ascii', errors='replace')
        vmaddr, vmsize, fileoff, filesize, maxprot, initprot, nsects, flags_s = \
            struct.unpack_from('<QQQQIIII', data, cmd_start + 24)
        if seg_name == "__LINKEDIT":
            linkedit_vmaddr = vmaddr
            linkedit_fileoff = fileoff
        
        # section_64: 16+16+QQQQIIIIII (80 bytes each)
        sec_offset = cmd_start + 24 + 8 * 8  # right after the segment_64 command fields
        for s in range(nsects):
            sectname_bytes = data[sec_offset:sec_offset + 16]
            segname_bytes = data[sec_offset + 16:sec_offset + 32]
            sectname = sectname_bytes.split(b'\x00', 1)[0].decode('ascii', errors='replace')
            segname = segname_bytes.split(b'\x00', 1)[0].decode('ascii', errors='replace')
            addr, sz, off, align, reloff, nreloc, flags_s, r1, r2 = \
                struct.unpack_from('<QQQIIIIII', data, sec_offset + 32)
            sections.append((segname, sectname, addr, sz, off))
            sec_offset += 80
    
    elif cmd_type == LC_SYMTAB:
        symoff, nsyms, stroff, strsize = struct.unpack_from('<IIII', data, cmd_start + 8)
        symtab_off = symoff
        symtab_nsyms = nsyms
        strtab_off = stroff
        strtab_size = strsize
    elif cmd_type == LC_DYSYMTAB:
        # struct dysymtab_command { uint32_t ilocalsym, nlocalsym, iextdefsym, nextdefsym, iundefsym, nundefsym, ... }
        fields = struct.unpack_from('<IIIIIIIIIIIIIII', data, cmd_start + 8)
        dysymtab_iextdef = fields[2]  # iextdefsym
        dysymtab_nextdef = fields[3]  # nextdefsym
        dysymtab_iref = fields[8]     # iundefsym (actually index of undef sym)
        dysymtab_nref = fields[9]     # nundefsym
    
    offset = cmd_start + cmd_size

def read_sym(i):
    sym_offset = symtab_off + i * 16
    n_strx, n_type, n_sect, n_desc, n_value = struct.unpack_from('<IBBHQ', data, sym_offset)
    if n_strx < strtab_size:
        str_offset = strtab_off + n_strx
        name_bytes = data[str_offset:str_offset + 512]
        if b'\x00' in name_bytes:
            name = name_bytes.split(b'\x00', 1)[0].decode('utf-8', errors='replace')
        else:
            name = name_bytes.decode('utf-8', errors='replace')
    else:
        name = f"strx{n_strx}"
    return name, n_type, n_sect, n_desc, n_value

# 1. 查找__DATA,__mod_init_func段（构造函数数组）
print("=" * 60)
print("1. __mod_init_func (dylib constructor入口点)")
print("=" * 60)
for segname, sectname, addr, sz, off in sections:
    if sectname == "__mod_init_func":
        print(f"  找到: {segname},{sectname}  addr=0x{addr:X} size=0x{sz:X} fileoff=0x{off:X}")
        n_funcs = sz // 8  # 每个指针8字节 arm64
        print(f"  构造函数个数: {n_funcs}")
        for i in range(min(n_funcs, 20)):
            func_ptr = struct.unpack_from('<Q', data, off + i * 8)[0]
            print(f"    [{i}] 入口地址: 0x{func_ptr:X}")
        break
else:
    print("  未找到__mod_init_func段")

# 2. __DATA,__objc_nlclslist (non-lazy class list - +load classes)
print("\n" + "=" * 60)
print("2. __objc_nlclslist (non-lazy classes - 有+load方法)")
print("=" * 60)
for segname, sectname, addr, sz, off in sections:
    if sectname == "__objc_nlclslist":
        print(f"  找到: {segname},{sectname}  addr=0x{addr:X} size=0x{sz:X} fileoff=0x{off:X}")
        n_cls = sz // 8
        print(f"  +load类个数: {n_cls}")
        # 这里存的是class_t的VM地址相对偏移，先打印原始值
        for i in range(min(n_cls, 30)):
            rel_off = struct.unpack_from('<i', data, off + i * 4)[0]  # could be 32-bit rel?
        # 实际上Mach-O是指针列表，可能是绝对地址
        for i in range(min(n_cls, 30)):
            cls_ptr = struct.unpack_from('<Q', data, off + i * 8)[0]
            print(f"    [{i}] class指针: 0x{cls_ptr:X}")
        break
else:
    print("  未找到__objc_nlclslist段 (可能所有类都在普通类列表)")

# 3. 导出符号表
print("\n" + "=" * 60)
print("3. 导出符号 (extdefsym - 外部可见符号)")
print("=" * 60)
if dysymtab_iextdef is not None:
    print(f"  导出符号数: {dysymtab_nextdef}")
    count = 0
    for i in range(dysymtab_iextdef, dysymtab_iextdef + dysymtab_nextdef):
        name, n_type, n_sect, n_desc, n_value = read_sym(i)
        if name and not name.startswith('_OBJC_') and not name.startswith('.objc_class_name'):
            print(f"    0x{n_value:016X}  {name}")
            count += 1
            if count >= 60:
                print(f"    ... (共{dysymtab_nextdef}个导出，只展示前{count}个非Objc符号)")
                break

# 4. 找关键section
print("\n" + "=" * 60)
print("4. 所有Section列表 (部分关键)")
print("=" * 60)
key_sections = ["__mod_init_func", "__objc_const", "__objc_selrefs", "__objc_msgrefs",
                "__objc_classlist", "__objc_nlclslist", "__objc_catlist", "__objc_nlcatlist",
                "__objc_protolist", "__TEXT,__text", "__DATA,__data", "__bss", "__common",
                "__la_symbol_ptr", "__nl_symbol_ptr", "__got", "__auth_got",
                "__objc_stubs", "__objc_stub_holds"]
for segname, sectname, addr, sz, off in sections:
    is_key = sectname in key_sections or (segname + "," + sectname) in key_sections
    marker = " ★" if is_key else ""
    if sz > 0:
        print(f"  {segname:12s} {sectname:24s} addr=0x{addr:09X} size=0x{sz:07X} ({sz:8d}) fileoff=0x{off:X}{marker}")
