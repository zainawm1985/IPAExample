# 🚀 GitHub 云编译 + 自动注入 使用指南（零Mac、全网页操作）

> 你只有 Windows + iOS 15.4.1 + TrollStore？完全没问题！
> 这套方案把 `编译dylib → 签名 → 打包 → (可选)自动注入IPA` 全部放到 GitHub Actions 云端免费跑。
> 你只需要推代码 + 点按钮，2~3分钟后下载成品即可。

---

## 📋 你需要先准备好

| 项目 | 怎么获取 |
|---|---|
| GitHub 账号 | https://github.com 免费注册一个 |
| 目标 App 的 IPA | 去各大越狱源/IPA站下砸壳版，或自己从越狱设备提取，**必须是未加密（cryptid=0）的砸壳IPA** |
| Windows 版 Sideloadly | https://sideloadly.io/ 下载安装（TrollStore辅助用，注入dylib功能非常好用） |

---

## 📁 当前目录结构（直接用就行）

```
c:\Users\x\Desktop\插件\            ← 把整个目录推到 GitHub
├── 抖音助手（xuu）_2.0-5.dylib     ← 原始参考dylib
├── MyTweak_example/
│   ├── MyTweak.m                   ← ✅ 你的Tweak源码 (修改这个来加功能)
│   ├── Makefile                    ← 本地macOS编译用(可选)
│   └── README.md                   ← Tweak原理说明
├── analyze_dylib.py                ← 分析dylib用的脚本（可忽略）
├── analyze_symbols.py              ← （可忽略）
├── analyze_sections.py             ← （可忽略）
├── analyze_objc.py                 ← （可忽略）
└── .github/workflows/
    └── build.yml                   ← ✅ GitHub Actions 云编译配置
```

---

## 🛠️ 第一步：把代码推到 GitHub

### 方式1：网页直接上传（超简单，不用装Git）

1. 打开 GitHub → 点右上角 **+** → **New repository**
   - Repository name: `MyTweak` （随你起）
   - ✅ Private（建议私有，公开也可以）
   - 点 **Create repository**

2. 进仓库后页面中间会有个 `uploading an existing file` 的链接，点它

3. 把 `c:\Users\x\Desktop\插件\` 这个目录里**所有文件和文件夹**（包括隐藏的 .github 文件夹）
   都拖进网页上传框里 → 底部点 **Commit changes**

> 💡 拖的时候要把 `.github` 文件夹也拖进去！它默认是隐藏的，Windows资源管理器里
> 打开"查看 → 显示 → 隐藏的项目"就能看到了。

### 方式2：命令行Git（懂Git的话）

```powershell
cd "c:\Users\x\Desktop\插件"
git init
git add .
git commit -m "init: MyTweak with GitHub Actions"
git branch -M main
git remote add origin https://github.com/你的用户名/MyTweak.git
git push -u origin main
```

---

## ▶️ 第二步：触发编译（点按钮就行）

1. 进仓库 → 点顶部 **Actions** 标签
2. 左侧列表点 **🔨 编译 Tweak Dylib + 自动注入 IPA**
3. 右边有个 **Run workflow ▼** 按钮，点它展开菜单：

| 选项 | 建议值 | 说明 |
|---|---|---|
| `upload_ipa` | ❌ 不勾选（推荐） | 直接让你拿到dylib，然后Windows上用Sideloadly注入，最简单最稳 |
| `upload_ipa` | ✅ 勾选（实验性） | 如果你把IPA改名为`target.ipa`一起push到仓库，或在Secrets里填了`IPA_URL`，Action会自动下载IPA → 注入 → 产出成品IPA |
| `sign_with_certs` | ❌ 不勾选 | 用AdHoc假签，TrollStore/Sideloadly完美兼容 |
| `min_ios` | 14.0 | 适配iOS 14+，和你的15.4.1兼容 |
| `arch` | arm64 | 你的iOS 15.4.1设备是arm64（iPhone X及以上都是arm64） |

4. 点绿色 **Run workflow** 按钮 → 页面会出现一条黄色的工作流在跑

5. 等 **2~3分钟** → 变成绿色 ✓ 就成功了！

---

## 📦 第三步：下载编译好的文件

1. 点那个绿色 ✓ 的工作流标题（比如 "🔨 编译 Tweak Dylib + ... 2 minutes ago"）
2. 滚到页面最底部 → **Artifacts** 区域有两个文件：

| Artifact 名 | 内容 |
|---|---|
| `MyTweak_dylib_packages` | ✅ 包含两个东西：<br>① `MyTweak.dylib` —— 编译好的可注入dylib<br>② `MyTweak_dylib_注入包.zip` —— 含使用说明的打包好的zip |
| `MyTweak_injected_IPA` | （只有勾选upload_ipa且提供了IPA才有）<br>已注入好的IPA，下载后直接TrollStore安装即可 |

3. 点 `MyTweak_dylib_packages` 下载 → 解压得到 `MyTweak.dylib`

---

## 🚀 第四步：注入到你的目标 IPA（推荐方式：Sideloadly）

> 这一步在你自己的 Windows 电脑上操作，最稳最简单！

1. 打开 **Sideloadly**（没装就去 sideloadly.io 下 Windows 版）
2. **iDevice** 那里选好你的 TrollStore 设备
3. 把目标 IPA 拖到 Sideloadly 中间的 **ipa 文件** 框
4. 点最下面的 **▸ Advanced options** 展开高级选项
5. 找到 **Inject dylib/frameworks/deb** 这一行 → 点右边的 **+** 号 →
   选择刚才下载解压出来的 `MyTweak.dylib`
   > ✅ 不需要再加 CydiaSubstrate.framework！因为示例代码里的 swizzle 用的是纯 ObjC runtime API，动态找不到CydiaSubstrate会自动降级
6. 确认无误后点 **Start** 按钮 → 等它跑完
7. Sideloadly 会自动把注入后的 IPA 安装到你 TrollStore 设备里
8. 设备上打开目标 App → 稍等几秒 → 弹出 **🎉 MyTweak 已成功注入** 的 Toast → **双击屏幕** 弹出Tweak菜单 → 大功告成！

---

## 🧪 进阶：让 GitHub 自动帮你注入 IPA（实验性功能）

如果你不想在 Windows 上用 Sideloadly，也可以让 GitHub Actions 直接产出注入好的 IPA：

### 方案A：把 IPA 文件放进仓库（IPA小于100M推荐）

1. 把你的目标 IPA 文件重命名为 **`target.ipa`**，放在仓库根目录（和 MyTweak_example 同级）
2. `git add target.ipa && git push` （或网页上传）
3. Actions → Run workflow 时 **✅ 勾选 upload_ipa**
4. 跑完后 Artifacts 里的 `MyTweak_injected_IPA` 就是 **已注入好的IPA**，下载后直接 TrollStore 安装即可

### 方案B：IPA放云盘用直链（IPA很大推荐）

1. 把 IPA 上传到能公网直链下载的地方（阿里云OSS、七牛、GitHub Release附件、OneDrive直链...）
   注意：要的是**点一下直接开始下载**的直链，不是分享页
2. 进仓库 → **Settings** → 左侧 **Secrets and variables** → **Actions**
3. 点 **New repository secret**
   - Name: `IPA_URL`
   - Secret: 你的直链URL
4. Run workflow 时 ✅ 勾选 upload_ipa，Action 会自动用 curl 下载 IPA → 注入 → 打包

---

## ✏️ 怎么修改 Tweak 功能？

打开 `MyTweak_example/MyTweak.m`，里面有非常详细的中文注释，所有模板都写好了：

### 💡 场景1：加一个"双击弹出的菜单里加新功能"

找到 `handleDoubleTap` 函数里的 `UIAlertController *ac = ...` 那一段，
照着现有的3个菜单项复制粘贴一个：

```objc
[ac addAction:[UIAlertAction actionWithTitle:@"🎵 我的新功能"
    style:UIAlertActionStyleDefault
    handler:^(UIAlertAction * _Nonnull a) {
        // 在这里写你的代码
        UIAlertController *show = [UIAlertController alertControllerWithTitle:@"标题"
            message:@"点击成功！" preferredStyle:UIAlertControllerStyleAlert];
        [show addAction:[UIAlertAction actionWithTitle:@"OK" style:0 handler:nil]];
        [vc presentViewController:show animated:YES completion:nil];
    }]];
```

改完 → 推代码 → 再跑一次Actions → 下载新dylib → Sideloadly重新注入。

### 💡 场景2：Hook目标App的某个具体类/方法

比如你逆向出来，目标App有个叫 `MusicPlayerVC` 的类，有个 `- (void)nextSong` 方法，
你想让它"下一首"时弹个提示：

在 `MyTweakEntry` 的 `dispatch_async` 代码块最后面加：

```objc
Class myCls = objc_getClass("MusicPlayerVC");
if (myCls) {
    SEL origSel = @selector(nextSong);
    IMP newImp = imp_implementationWithBlock(^(id _self){
        // 先调原方法（不想让它切歌就注释掉下一行）
        ((void(*)(id,SEL))objc_msgSend)(_self, origSel);
        // 你的代码
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"🎵 已切歌"
            message:nil preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:0 handler:nil]];
        // 找当前最顶层VC弹
        UIViewController *top = (UIViewController *)[UIApplication sharedApplication].keyWindow.rootViewController;
        while (top.presentedViewController) top = top.presentedViewController;
        [top presentViewController:ac animated:YES completion:nil];
    });
    hh_hookWithCydiaSubstrate(myCls, origSel, newImp, NULL);
} else {
    HHLog(@"⚠️ MusicPlayerVC这个类不存在");
}
```

### 💡 场景3：判断BundleID只在特定App激活

不想这个Tweak注入所有App？在MyTweakEntry函数开头加：

```objc
NSString *bid = [NSBundle mainBundle].bundleIdentifier;
NSSet *allowed = [NSSet setWithArray:@[
    @"com.netease.cloudmusic",      // 网易云
    @"com.tencent.qqmusic",         // QQ音乐
    @"com.ss.iphone.ugc.Aweme",     // 抖音
]];
if (![allowed containsObject:bid]) {
    HHLog(@"BundleID %@ 不在白名单，Tweak不激活", bid);
    return;
}
```

---

## 🧐 常见问题排查

### ❓ Actions 跑失败了怎么办？
1. 点进红色 ✗ 的那一次工作流
2. 点 `build` job → 展开每一步看红色报错的具体日志
3. 99% 是代码语法错误，根据报错修 MyTweak.m 重新push即可

### ❓ 注入后App打开闪退？
1. 设备上保持App闪退那一刻，电脑开iMazing/3uTools看设备日志
2. 常见原因：
   - **找不到MyTweak.dylib** → Sideloadly没注入成功，重新来一遍
   - **找不到CydiaSubstrate** → 勾选Sideloadly注入时不要自己加CydiaSubstrate
   - **Hook了不存在的方法 → crash** → 看崩溃栈定位是哪个swizzle崩了

### ❓ 双击屏幕没反应？
1. 先看有没有弹启动Toast（任意VC第一次appear时弹）
2. 没弹Toast = Tweak根本没加载成功 → 重新Sideloadly注入
3. 弹了Toast但双击没菜单 → 可能是这个App自己有双击手势被拦截了，
   可以把 `MyTweak.m` 里的 `gDoubleTap.numberOfTapsRequired = 2;` 改成 3（三击）试试

### ❓ 我想加更多第三方库（FMDB、AFNetworking等）怎么办？
1. 把源码 .m 文件一起放 MyTweak_example 目录
2. 改 `.github/workflows/build.yml` 里的 `SRC_FILE` 变量，改成多个源文件：
   比如 `SRC_FILE: "MyTweak_example/MyTweak.m MyTweak_example/FMDatabase.m"`
   或者更简单，把SRC_FILE改成*.m通配
3. `FRAMEWORKS` 变量里追加需要的framework，比如 `-framework CFNetwork -framework MobileCoreServices`

---

## 🎉 总结一下完整流程

```
改 MyTweak.m → push到GitHub → Actions点Run workflow → 等2分钟
    ↓
下载 Artifact → 得到 MyTweak.dylib
    ↓
Windows开Sideloadly → 拖目标IPA → Advanced+Inject dylib选MyTweak.dylib → Start
    ↓
设备上打开App → 看到Toast + 双击出菜单 = 成功！
```

写Tweak的过程就是 **逆向找类名和方法名 → 在MyTweak.m里加hook代码 → push → 编译 → 注入 → 测试** 的循环。
祝玩的开心！🎊
