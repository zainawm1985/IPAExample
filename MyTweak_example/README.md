## MyTweak - 可注入iOS App的Tweak Dylib 示例工程

### 🎯 这个工程是做什么的？
演示如何写一个类似"抖音助手"那样**可被TrollStore / Sideloadly注入到任意App**的dylib插件。

注入成功后会有以下效果：
1. ✅ App启动后任意VC第一次展示时，弹出激活Toast
2. ✅ **双击屏幕** 任意位置弹出Tweak菜单（粘贴板/当前VC/App信息）
3. ✅ 预留了 **按类名精确Hook私有方法** 的模板（如HomeViewController.onBtnClick:）

---

### ⚙️ 为什么"抖音助手"这种dylib可以被直接注入？

| 特性 | 说明 |
|------|------|
| 文件类型 | `MH_DYLIB` (Mach-O动态库)，不是MH_EXECUTE可执行 |
| 架构 | 纯 arm64 切片（现代iOS设备） |
| 安装名 | `@rpath/DouyinHelper.dylib` → 放在App的 Frameworks/ 目录就能被找到 |
| 加密 | `cryptid=0` 完全未加密 (App Store下载的才会被FairPlay加密) |
| 代码签名 | 假的AdHoc签名 (`-s -`)，TrollStore/Sideloadly接受这种签名 |
| 注入入口 | `__attribute__((constructor))` 构造函数 → 由dyld在dylib被load时自动执行 |
| 依赖方式 | 可选链接 `CydiaSubstrate.framework` (做Method Swizzle的老牌库)，也可以直接用runtime API |
| 入口触发方式 | `constructor` → 主队列async → Hook各种类的方法 → 业务逻辑 |

---

### 🧱 注入原理总图

```
┌──────────────────────────────────────────────────────┐
│ 你做的事情 (macOS上执行)                              │
│                                                      │
│  ① clang 编译 MyTweak.m  ──►  MyTweak.dylib          │
│     (MH_DYLIB, arm64, install_name=@rpath/...)       │
│                                                      │
│  ② (可选) codesign -f -s -  MyTweak.dylib            │
│         (AdHoc假签名，不校验有效性)                    │
│                                                      │
│  ③ 把dylib塞进目标IPA里:                              │
│     Payload/Target.app/                              │
│       ├─ Target              (主可执行文件)           │
│       └─ Frameworks/                                │
│          ├─ MyTweak.dylib  ← 你写的dylib             │
│          └─ CydiaSubstrate.framework (可选依赖)      │
│                                                      │
│  ④ optool / insert_dylib 给主可执行文件插入：         │
│     • LC_LOAD_DYLIB(@rpath/MyTweak.dylib)            │
│     • LC_RPATH(@executable_path/Frameworks)          │
│                                                      │
│  ⑤ codesign --deep 重签整个.app + 打回IPA             │
│                                                      │
│  ⑥ Sideloadly / TrollStore 安装这个修改后的IPA        │
└─────────────────────┬────────────────────────────────┘
                      │
                      ▼  安装后首次启动
┌──────────────────────────────────────────────────────┐
│ iOS 运行时发生的事                                    │
│                                                      │
│  dyld 加载主可执行 → 解析 LC_LOAD_DYLIB              │
│        │                                             │
│        ▼                                             │
│  dlopen("Frameworks/MyTweak.dylib")                  │
│        │                                             │
│        ▼                                             │
│  MyTweak.m 的 __attribute__((constructor)) 被调用    │
│  (等价C++全局对象构造，dyld自动触发)                   │
│        │                                             │
│        ▼                                             │
│  dispatch_async(main_queue) 里执行：                  │
│   ↳ class_getInstanceMethod + method_exchangeImplementations
│   ↳ 或 MSHookMessageEx(cls, @selector(xxx), newImp, &oldImp)
│   ↳ 把你要修改的 UIViewController / 私有类的方法      │
│     指向你的新IMP                                     │
│                                                      │
│  用户操作App时 → 你的新IMP被调用 → 插入逻辑 +         │
│                    通过保存的oldImp回调原实现          │
└──────────────────────────────────────────────────────┘
```

---

### 🛠️ 编译方法

#### 方式A: macOS + Xcode CLT（最简单，本Makefile方式）
```bash
cd MyTweak_example

# 1. 编译
make all
# 产物: build/MyTweak.dylib

# 2. AdHoc签名 (Sideloadly要求)
make sign

# 3. 查看生成的Mach-O信息
make check
```

#### 方式B: 无Mac？用GitHub Actions云编译
把项目推到GitHub，创建 `.github/workflows/build.yml`：
```yaml
name: Build Tweak Dylib
on: workflow_dispatch
jobs:
  build:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - run: make all sign package
      - uses: actions/upload-artifact@v4
        with:
          name: MyTweak-dylib
          path: MyTweak_for_injection.zip
```
几分钟后下载artifact即可。

#### 方式C: Theos/Logos语法 (越狱社区标准写法，也可Sideloadly用)
安装Theos后，写 Tweak.xm 文件：
```logos
%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"MyTweak OK" message:nil preferredStyle:1];
      [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:0 handler:nil]];
      [self presentViewController:ac animated:YES completion:nil];
    });
}
%end

%ctor {
  NSLog(@"[MyTweak logos] constructor");
}
```
然后 `make package FINALPACKAGE=1` 得到的 .deb 解压后里面的/Library/MobileSubstrate/DynamicLibraries/*.dylib就是同样的东西，可以直接用Sideloadly/TrollStore注入。

---

### 🚀 注入到IPA（3种方式任选）

#### 方式1: Sideloadly图形界面（新手推荐）
1. 打开Sideloadly
2. 把目标.ipa拖进去
3. 点 **`Advanced options` → `Inject dylib/frameworks/deb`**
4. 把 `build/MyTweak.dylib` 和（如果用到了）`CydiaSubstrate.framework` 拖进去
5. Start → 安装到TrollStore设备即可

Sideloadly会自动做：插入LC_LOAD_DYLIB、补CydiaSubstrate、重签。

#### 方式2: 命令行手动注入 (脚本，适合CI批量)
```bash
# 需要: brew install alexey-sun/tmp/optool  （或自己编译optool）
make manual-inject IPA=/Users/you/Downloads/TargetApp.ipa
# 产物: tmp_out/TargetApp_tweaked.ipa
# 然后用 TrollStore 安装这个tweaked ipa
```

#### 方式3: TrollStore 1.x + TCI (TrollStore Custom Injection)
仅限支持TCI的TrollStore版本，把 `MyTweak.dylib` 放到设备的
`/var/mobile/TrollStoreInjections/` 目录，安装/重装任意IPA时会自动注入所有该目录下的dylib。

---

### 🧩 进阶：针对具体App做精准Hook

要Hook抖音/微信等特定App的私有方法，先做逆向拿到类名和方法名（用class-dump、Hopper、FLEX）。

举个例子（假设抖音有个类 `AWEUserFeedViewController` 有方法 `- (void)onLikeBtnClick:(id)sender`），在MyTweak.m里加：

```objc
// MyTweakEntry constructor里追加:
Class cls = objc_getClass("AWEUserFeedViewController");
if (cls) {
    SEL sel = @selector(onLikeBtnClick:);
    IMP newImp = imp_implementationWithBlock(^(id _self, id sdr){
        NSLog(@"[MyTweak] 点赞！sender=%@", sdr);
        // 这里做自动点赞、点赞计数等任意逻辑
        typedef void (*LikeFunc)(id, SEL, id);
        static LikeFunc orig = NULL;
        if (!orig) {
            Method m = class_getInstanceMethod(cls, sel);
            orig = (LikeFunc)method_getImplementation(m);
        }
        orig(_self, sel, sdr);  // 调用原实现(取消注释=正常点赞)
    });
    hh_hookWithCydiaSubstrate(cls, sel, newImp, NULL);
}
```

### ⚠️ 常见坑
| 坑 | 解决 |
|----|------|
| dylib install_name和实际放的路径对不上 | otool -D 确认，要和 optool insert 的路径完全一致 |
| 找不到CydiaSubstrate | 要么打包CydiaSubstrate.framework进Frameworks，要么纯runtime swizzle（示例默认这种，不依赖） |
| 崩溃在constructor（EXC_BAD_ACCESS / dyld 启动即崩） | constructor里不要碰UIKit，把所有操作都放到dispatch_async(main)里 |
| codesign失败 | 确保用 `-s -`  (adhoc，无证书) |
| 某个类Hook没生效 | 先用 `NSClassFromString()` 打印类是否真的存在；注意swift类的mangled name |
| 注入后App闪退 | 用Console.app看设备日志，通常是Hook方法的参数/返回值类型不对 (IMP签名必须和原方法匹配) |
| armv7 / arm64e 切片 | 老设备加 `-arch armv7`，arm64e pac指针签名可能影响MSHookMessageEx，先去掉arm64e只留arm64 |

---

### 📁 目录结构
```
MyTweak_example/
├── MyTweak.m          ← 核心源码，你主要修改这个文件
├── Makefile           ← 一键编译/签名/注入
├── README.md          ← 本说明
└── vendor/ (可选)
    └── CydiaSubstrate.framework
```

祝注入顺利！遇到崩溃查崩溃日志 + 看dyld/dylb路径报错，90%都是路径或签名问题～
