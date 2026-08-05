import struct

path = r"c:\Users\x\Desktop\插件\抖音助手（xuu）_2.0-5.dylib"
with open(path, 'rb') as f:
    data = f.read()

endian = '<'
LC_SEGMENT_64 = 0x19
hdr_size = 32

hdr = struct.unpack_from('<IIIIIIII', data, 0)
ncmds = hdr[4]
sizeofcmds = hdr[5]

offset = hdr_size
cmds_end = offset + sizeofcmds
sections = []

symtab_off = None
symtab_nsyms = None
strtab_off = None
strtab_size = None
LC_SYMTAB = 0x2

linkedit_vmaddr = None
linkedit_fileoff = None

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
        
        sec_offset = cmd_start + 24 + 64  # 8 fields * 8 bytes = 64 bytes after segment name
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
    
    offset = cmd_start + cmd_size

# 打印所有关键的section
print("=== 关键 Sections ===")
interesting = ["__mod_init_func", "__objc_nlclslist", "__objc_classlist", 
               "__objc_catlist", "__objc_nlcatlist", "__objc_selrefs", 
               "__objc_protolist", "__objc_const", "__objc_data",
               "__la_symbol_ptr", "__nl_symbol_ptr", "__stubs", "__stub_helper",
               "__auth_got", "__got", "__text", "__cstring", "__DATA_CONST"]
for segname, sectname, addr, sz, off in sections:
    if sz > 0 and (sectname in interesting or segname in ["__DATA_CONST", "__AUTH_CONST"] or "objc" in sectname):
        print(f"  {segname:12s} {sectname:22s} vm=0x{addr:09X} size=0x{sz:07X} ({sz:8d})  fileoff=0x{off:X}")

def read_sym(i):
    sym_offset = symtab_off + i * 16
    if sym_offset + 16 > len(data):
        return None, 0, 0, 0, 0
    n_strx, n_type, n_sect, n_desc, n_value = struct.unpack_from('<IBBHQ', data, sym_offset)
    if n_strx < strtab_size:
        str_offset = strtab_off + n_strx
        name_bytes = data[str_offset:str_offset + 512]
        if b'\x00' in name_bytes:
            name = name_bytes.split(b'\x00', 1)[0].decode('utf-8', errors='replace')
        else:
            name = name_bytes.decode('utf-8', errors='replace')
    else:
        name = f"badstrx{n_strx}"
    return name, n_type, n_sect, n_desc, n_value

# 搜索所有符号中的 +load 方法和关键入口
print("\n=== +load / constructor / DYZS* 类方法(前100) ===")
found_load = []
found_init = []
found_dyzs = []
for i in range(symtab_nsyms):
    name, n_type, n_sect, n_desc, n_value = read_sym(i)
    if not name:
        continue
    if "+load" in name or "] +load" in name or " load" in name[-6:]:
        found_load.append((name, n_value))
    if "constructor" in name.lower() and n_value != 0:
        found_init.append((name, n_value))
    if any(p in name for p in ["DYZSManager", "DouyinHelper", "DYZS", "_logos_%ctor", 
                               "logos_init$", "logos_ctor_", "forcedLoadCategories"]):
        found_dyzs.append((name, n_value))

for name, val in found_load[:50]:
    print(f"  +LOAD  0x{val:09X}  {name}")
if len(found_load) > 50:
    print(f"  ... +load总数: {len(found_load)}")

for name, val in found_init[:20]:
    print(f"  INIT   0x{val:09X}  {name}")

for name, val in found_dyzs[:100]:
    print(f"  TWEAK  0x{val:09X}  {name}")

# 查找__objc_classlist，解析所有objc类的名字
print("\n=== Objc 类列表 (前60个) ===")
for segname, sectname, addr, sz, off in sections:
    if sectname == "__objc_classlist":
        n_classes = sz // 8
        print(f"  共有{n_classes}个类 (__TEXT/__DATA指针相对基址=0x{addr:X})")
        # 这些是相对指针 (arm64e可能有auth)。在普通arm64中是32-bit relative offset
        for i in range(min(n_classes, 60)):
            # Try as 64-bit absolute first, then 32-bit rel
            # Most ObjC classlist in arm64 use 32-bit relative offsets (from classlist entry addr)
            try:
                rel32 = struct.unpack_from('<i', data, off + i * 4)[0]
                # target = &entry + rel32
                entry_addr = addr + i * 8  # note: may be 8-byte entries even for rel
                # Actually some use 4-byte displacement, others use 8-byte pointer
                # Let's just dump raw bytes as hex
                raw8 = struct.unpack_from('<Q', data, off + i * 8)[0]
                raw4_1 = struct.unpack_from('<i', data, off + i * 8)[0]
                raw4_2 = struct.unpack_from('<i', data, off + i * 8 + 4)[0]
                if raw4_1 == 0 and raw4_2 == 0:
                    cls_ref_addr = None
                elif raw4_1 != 0 and raw4_2 == 0:
                    # Looks like 32-bit displacement
                    base = addr + i * 8
                    cls_ref_addr = base + raw4_1
                    cls_ref_fileoff = linkedit_fileoff + (cls_ref_addr - linkedit_vmaddr) if linkedit_vmaddr and cls_ref_addr >= linkedit_vmaddr else None
                else:
                    cls_ref_addr = raw8
                    cls_ref_fileoff = linkedit_fileoff + (raw8 - linkedit_vmaddr) if linkedit_vmaddr and raw8 >= linkedit_vmaddr else None
                
                # Now find the class name: class_t has ro at offset 32 (class_rw_t -> class_ro_t)
                # name in class_ro_t at different offsets. Let's just search symbol table for matching.
                # Try to find OBJC_CLASS symbol with address near cls_ref_addr
                found = None
                for si in range(symtab_nsyms):
                    sn, st, ssec, sd, sv = read_sym(si)
                    if sn and sn.startswith("_OBJC_CLASS_$") and sv != 0 and abs(sv - (cls_ref_addr or 0)) < 0x10:
                        found = sn[len("_OBJC_CLASS_$_"):]
                        break
                clslabel = f" -> {found}" if found else ""
                print(f"    [{i:3d}] entry=0x{addr+i*8:X} raw=0x{raw8:016X} (ref=0x{(cls_ref_addr or 0):X}){clslabel}")
            except Exception as e:
                print(f"    [{i}] error {e}")
        break
