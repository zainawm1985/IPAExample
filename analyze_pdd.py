import zipfile, struct, os, tempfile, shutil, re

ipa_path = r"c:\Users\x\Desktop\插件\拼多多-8.4.0.ipa"
tmp = tempfile.mkdtemp()
try:
    print("正在解压IPA...")
    with zipfile.ZipFile(ipa_path, 'r') as zf:
        exe_zip_path = "Payload/pinduoduo.app/pinduoduo"
        zf.extract(exe_zip_path, tmp)
    exe_local = os.path.join(tmp, exe_zip_path)
    print(f"可执行文件已提取: {exe_local}")

    # 也尝试提取Info.plist
    print("\n📱 App信息:")
    with zipfile.ZipFile(ipa_path, 'r') as zf:
        try:
            zf.extract("Payload/pinduoduo.app/Info.plist", tmp)
            import plistlib
            with open(os.path.join(tmp, "Payload/pinduoduo.app/Info.plist"), 'rb') as pf:
                pl = plistlib.load(pf)
            print(f"   BundleID: {pl.get('CFBundleIdentifier', '?')}")
            print(f"   版本号: {pl.get('CFBundleShortVersionString', '?')}")
            print(f"   最低iOS: {pl.get('MinimumOSVersion', '?')}")
        except:
            pass

    with open(exe_local, 'rb') as f:
        data = f.read()

    print(f"\n文件大小: {len(data)/1024/1024:.1f} MB")

    # 提取所有可读字符串（双线程扫描：ASCII + 可能的UTF-8中文）
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

    # 分类
    urls = [s for s in strings if s.startswith('http') or s.startswith('https://')]
    classes = [s for s in strings if re.match(r'^[A-Z][a-zA-Z0-9_]{2,50}$', s) and not s.startswith(('Http','URL','JSON','XML','NS','CG','UI')) and not '/' in s]
    
    # 找与商品/图片/详情页相关的
    goods_keywords = ['Goods', 'goods', 'Product', 'product', 'Image', 'image', 'Picture', 'picture',
                      'Photo', 'photo', 'Gallery', 'gallery', 'Banner', 'banner', 'Sku', 'sku',
                      'Detail', 'detail', 'LunBo', 'Lunbo', 'Pic', 'pic', 'Thumb', 'thumb',
                      'Album', 'album', 'Media', 'media', 'Preview', 'preview', 'carousel',
                      'Slide', 'slide', 'Round', 'round']
    
    goods_classes = []
    goods_strings = []
    goods_urls = []
    goods_methods = []
    
    for s in strings:
        sl = s
        if any(k.lower() in sl.lower() for k in goods_keywords):
            if re.match(r'^[A-Z][a-zA-Z0-9_]{3,60}$', s):
                goods_classes.append(s)
            elif s.startswith('http'):
                goods_urls.append(s)
            elif re.match(r'^[a-z_][a-zA-Z0-9_:]+$', s) and '_' in s:
                goods_methods.append(s)
            elif len(s) < 150:
                goods_strings.append(s)

    # 找所有https URL的域名
    domains = set()
    for u in urls:
        m = re.search(r'https?://([^/]+)', u.lower())
        if m:
            domains.add(m.group(1))

    print("\n" + "=" * 60)
    print("🌐 PDD使用的域名")
    print("=" * 60)
    for d in sorted(domains):
        print(f"  {d}")

    print(f"\n{'='*60}")
    print(f"📷 商品/图片/详情页 相关类名 (前200个，共{len(set(goods_classes))}个)")
    print("=" * 60)
    for c in sorted(set(goods_classes))[:200]:
        print(f"  {c}")

    print(f"\n{'='*60}")
    print(f"🔗 商品/图片相关URL (前100个)")
    print("=" * 60)
    for u in sorted(set(goods_urls))[:100]:
        print(f"  {u}")

    print(f"\n{'='*60}")
    print(f"📝 商品/图片相关字符串 (前100个)")
    print("=" * 60)
    for s in sorted(set(goods_strings))[:100]:
        print(f"  {s}")

    print(f"\n{'='*60}")
    print(f"🛠️ 商品/图片相关方法/属性名 (前100个)")
    print("=" * 60)
    for m in sorted(set(goods_methods))[:100]:
        print(f"  {m}")

    # 重点搜索: SDWebImage / Kingfisher / 网络图片加载库
    print(f"\n{'='*60}")
    print(f"🖼️ 图片加载库检测")
    print("=" * 60)
    img_lib_keywords = ['SDWeb', 'sd_', 'sdweb', 'SDImage', 'Kingfisher', 'YYWebImage',
                        'AFNetwork', 'Alamo', 'Swifty', 'Moya', 'Nuke/', 'PINCache']
    for kw in img_lib_keywords:
        found = [s for s in strings if kw.lower() in s.lower()]
        if found:
            print(f"  ✅ 检测到 {kw}: {len(found)}个引用")
            for f in found[:5]:
                print(f"     {f}")
        else:
            print(f"  ❌ 未检测到 {kw}")

    # 搜ViewController
    print(f"\n{'='*60}")
    print(f"📱 可能的关键ViewController (含Product/Detail/Image/Gallery等)")
    print("=" * 60)
    vc_patterns = [s for s in set(classes) if 'ViewController' in s or 'Controller' in s]
    target_vc = [v for v in vc_patterns if any(k.lower() in v.lower() for k in ['goods','product','detail','image','photo','gallery','publish'])]
    for v in sorted(target_vc)[:50]:
        print(f"  {v}")

    # 搜Model
    print(f"\n{'='*60}")
    print(f"📦 可能的关键Model (含Product/Goods/Image/Pic等)")
    print("=" * 60)
    model_patterns = [s for s in set(classes) if 'Model' in s or 'Info' in s or 'Entity' in s or 'Item' in s]
    target_model = [m for m in model_patterns if any(k.lower() in m.lower() for k in ['goods','product','image','photo','pic','sku','detail','banner'])]
    for m in sorted(target_model)[:50]:
        print(f"  {m}")

finally:
    shutil.rmtree(tmp, ignore_errors=True)
