//
//  MyTweak.m
//  可注入到任意App的Tweak dylib 示例
//
//  功能：
//  1. App启动时弹欢迎Toast
//  2. 替换 ViewController 的 viewDidAppear: 弹框
//  3. 用手势双击屏幕弹调试菜单
//
//  编译方式见 Makefile
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// ==================== CydiaSubstrate 兼容声明 ====================
// 如果你用Theos Logos语法编译 (logos %hook)，不需要写这些
// 这里直接用runtime等价实现，也可以用MSHookMessageEx宏
#import <objc/runtime.h>
#import <objc/message.h>
#include <dlfcn.h>

// 声明MSHookMessageEx，链接时会从CydiaSubstrate.framework找
// 不依赖CydiaSubstrate也可以直接用method_setImplementation替换
void MSHookMessageEx(Class class, SEL selector, IMP replacement, IMP *result);

#define HHLog(fmt, ...) NSLog(@"[MyTweak] " fmt, ##__VA_ARGS__)

// ==================== 通用工具：Method Swizzle 封装 ====================
// 方案A: 纯runtime swizzle（不依赖CydiaSubstrate.framework，最便携）
static void hh_swizzleMethod(Class cls, SEL originalSel, IMP newImp, IMP *oldImpStore) {
    Method origMethod = class_getInstanceMethod(cls, originalSel);
    if (!origMethod) {
        HHLog(@"⚠️ swizzle失败，方法不存在: %@ on %@", NSStringFromSelector(originalSel), cls);
        return;
    }
    const char *typeEncoding = method_getTypeEncoding(origMethod);
    IMP oldImp = method_getImplementation(origMethod);
    
    // 动态添加一个带前缀的新方法，保存old实现
    SEL backupSel = sel_registerName([[@"__hh_orig_" stringByAppendingString:NSStringFromSelector(originalSel)] UTF8String]);
    if (!class_addMethod(cls, backupSel, oldImp, typeEncoding)) {
        // 已添加过，直接取
        oldImp = method_getImplementation(class_getInstanceMethod(cls, backupSel));
    }
    
    // 替换原方法为新实现
    class_replaceMethod(cls, originalSel, newImp, typeEncoding);
    
    if (oldImpStore) *oldImpStore = oldImp;
    HHLog(@"✅ swizzle成功: %@ %@", cls, NSStringFromSelector(originalSel));
}

// 方案B: 用CydiaSubstrate MSHookMessageEx（传统Tweak方式）
// 原理完全一样，封装得更好用；在CydiaSubstrate环境下优先用它
static void hh_hookWithCydiaSubstrate(Class cls, SEL sel, IMP newImp, IMP *orig) {
    static void *handle = NULL;
    static void (*_MSHookMessageEx)(Class, SEL, IMP, IMP*) = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // 动态找CydiaSubstrate，找不到就降级为runtime swizzle
        handle = dlopen("/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate", RTLD_LAZY);
        if (!handle) {
            // Sideloadly注入时打包在App内的Framework路径
            handle = dlopen("@rpath/CydiaSubstrate.framework/CydiaSubstrate", RTLD_LAZY);
        }
        if (handle) {
            _MSHookMessageEx = (typeof(_MSHookMessageEx))dlsym(handle, "MSHookMessageEx");
        }
    });
    if (_MSHookMessageEx) {
        _MSHookMessageEx(cls, sel, newImp, orig);
        HHLog(@"🎣 MSHookMessageEx: %@ %@", cls, NSStringFromSelector(sel));
    } else {
        HHLog(@"⚠️ CydiaSubstrate不可用，降级为runtime swizzle");
        hh_swizzleMethod(cls, sel, newImp, orig);
    }
}

// ==================== 保存原方法的函数指针 ====================
static IMP Orig_UIApplicationDelegate_didFinishLaunching = NULL;
static IMP Orig_UIViewController_viewDidAppear = NULL;

// ==================== 自己实现的Toast（无需第三方库） ====================
@interface HHToast : UIView
+ (void)showInView:(UIView *)view text:(NSString *)text duration:(NSTimeInterval)duration;
@end
@implementation HHToast
+ (void)showInView:(UIView *)view text:(NSString *)text duration:(NSTimeInterval)duration {
    if (!view || !text.length) return;
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.textColor = [UIColor whiteColor];
    label.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.75];
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    label.layer.cornerRadius = 10;
    label.layer.masksToBounds = YES;
    
    CGSize size = [text boundingRectWithSize:CGSizeMake(view.bounds.size.width - 80, 200)
                                     options:NSStringDrawingUsesLineFragmentOrigin
                                  attributes:@{NSFontAttributeName: label.font}
                                     context:nil].size;
    label.frame = CGRectMake(0, 0, size.width + 32, size.height + 20);
    label.center = CGPointMake(view.bounds.size.width / 2, view.bounds.size.height - 120);
    label.alpha = 0;
    [view addSubview:label];
    
    [UIView animateWithDuration:0.25 animations:^{ label.alpha = 1; }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.25 animations:^{ label.alpha = 0; } completion:^(BOOL f) {
            [label removeFromSuperview];
        }];
    });
}
@end

// ==================== Hook 1: AppDelegate 启动 ================
// 目标：勾住最前面几个UIApplicationDelegate的didFinishLaunching，弹欢迎Toast
// 这里我们直接勾UIApplication本身的sendEvent:做一个兜底，
// 并勾任意UIViewController.viewDidAppear作为首次展示时机。

// 保存原实现：UIViewController -viewDidAppear:
typedef void (*VCViewDidAppearFunc)(id, SEL, BOOL);
static VCViewDidAppearFunc Orig_VC_viewDidAppear = NULL;

static void New_VC_viewDidAppear(id self, SEL _cmd, BOOL animated) {
    if (Orig_VC_viewDidAppear) Orig_VC_viewDidAppear(self, _cmd, animated);
    
    // 只在最顶层VC第一次出现时弹一次
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *msg = [NSString stringWithFormat:@"🎉 MyTweak已激活\n已加载类: %@",
                             NSStringFromClass([self class])];
            UIViewController *topVC = self;
            while (topVC.presentedViewController) topVC = topVC.presentedViewController;
            [HHToast showInView:topVC.view text:msg duration:3.0];
            HHLog(@"🎯 MyTweak 激活，当前VC: %@", NSStringFromClass([self class]));
        });
    });
}

// ==================== Hook 2: 监控 特定App 的类 ================
// 比如注入到微信、抖音等App时，你可以针对其私有类做精准Hook
// 这里用一个"如果存在就Hook"的通用辅助函数

static void hookIfClassExists(const char *className, SEL sel, IMP newImp, IMP *origStore) {
    Class cls = objc_getClass(className);
    if (cls) {
        hh_hookWithCydiaSubstrate(cls, sel, newImp, origStore);
    } else {
        HHLog(@"ℹ️ 类 %s 不存在，跳过hook", className);
    }
}

// 示例：假设App里有个叫"HomeViewController"的类，勾它的按钮点击
typedef void (*AnyVoidFunc)(id, SEL, ...);
static AnyVoidFunc Orig_HomeBtnClick = NULL;
static void New_HomeBtnClick(id self, SEL _cmd, id sender) {
    HHLog(@"👉 捕获到HomeViewController按钮点击: %@", sender);
    if (Orig_HomeBtnClick) Orig_HomeBtnClick(self, _cmd, sender);
    // 插入我们的逻辑：弹额外提示
    UIViewController *vc = (UIViewController *)self;
    if ([vc isKindOfClass:[UIViewController class]]) {
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"MyTweak提示"
                                                                    message:@"按钮点击已被我拦截😎"
                                                             preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [vc presentViewController:ac animated:YES completion:nil];
    }
}

// ==================== 双击手势 ================
static UITapGestureRecognizer *gDoubleTap = nil;

static void handleDoubleTap(UITapGestureRecognizer *gr) {
    if (gr.state != UIGestureRecognizerStateRecognized) return;
    HHLog(@"👆 双击手势触发");
    UIView *target = gr.view;
    if (!target) return;
    UIResponder *resp = target;
    while (resp && ![resp isKindOfClass:[UIViewController class]]) resp = [resp nextResponder];
    UIViewController *vc = (UIViewController *)resp;
    
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"MyTweak菜单"
                                                                message:nil
                                                         preferredStyle:UIAlertControllerStyleActionSheet];
    [ac addAction:[UIAlertAction actionWithTitle:@"📋 粘贴板内容" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull a) {
        UIPasteboard *pb = [UIPasteboard generalPasteboard];
        NSString *content = pb.string ?: @"(空)";
        UIAlertController *show = [UIAlertController alertControllerWithTitle:@"粘贴板"
                                                                      message:content
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [show addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [vc presentViewController:show animated:YES completion:nil];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"ℹ️ 当前VC信息" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull a) {
        NSString *info = [NSString stringWithFormat:@"当前VC: %@\nView: %@",
                          NSStringFromClass([vc class]), NSStringFromClass([vc.view class])];
        UIAlertController *show = [UIAlertController alertControllerWithTitle:@"控制器信息"
                                                                      message:info
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [show addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [vc presentViewController:show animated:YES completion:nil];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"🏠 Bundle信息" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull a) {
        NSBundle *b = [NSBundle mainBundle];
        NSString *info = [NSString stringWithFormat:@"BundleID: %@\nApp名: %@\n版本: %@\n可执行: %@",
                          b.bundleIdentifier,
                          [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: b.infoDictionary[@"CFBundleName"],
                          b.infoDictionary[@"CFBundleShortVersionString"],
                          b.executablePath.lastPathComponent];
        UIAlertController *show = [UIAlertController alertControllerWithTitle:@"App信息"
                                                                      message:info
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [show addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [vc presentViewController:show animated:YES completion:nil];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    // iPad适配
    if ([ac respondsToSelector:@selector(popoverPresentationController)]) {
        ac.popoverPresentationController.sourceView = target;
        ac.popoverPresentationController.sourceRect = CGRectMake(target.bounds.size.width/2, target.bounds.size.height/2, 0, 0);
        ac.popoverPresentationController.permittedArrowDirections = 0;
    }
    [vc presentViewController:ac animated:YES completion:nil];
}

// ==================== UIApplication sendEvent: ================
// 这是最稳定的全局入口，用它给所有新出现的Window附加双击手势
typedef void (*SendEventFunc)(id, SEL, UIEvent*);
static SendEventFunc Orig_SendEvent = NULL;

static void New_SendEvent(UIApplication *self, SEL _cmd, UIEvent *event) {
    if (Orig_SendEvent) Orig_SendEvent(self, _cmd, event);
    
    // 懒加载，附加手势到keyWindow
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            UIWindow *w = [UIApplication sharedApplication].keyWindow;
            if (!w) {
                for (UIWindow *ww in [UIApplication sharedApplication].windows) {
                    if (!ww.hidden) { w = ww; break; }
                }
            }
            if (w && !gDoubleTap) {
                gDoubleTap = [[UITapGestureRecognizer alloc] initWithTarget:[HHToast class] action:@selector(hh_doubleTapWrapper:)];
                gDoubleTap.numberOfTapsRequired = 2;
                gDoubleTap.numberOfTouchesRequired = 1;
                gDoubleTap.cancelsTouchesInView = NO;
                // 因target需要handleDoubleTap，我们用objc关联block方式
                // 简化方案：直接add到NSObject+category
                // 这里更简单：动态加方法
                Method m = class_getInstanceMethod([HHToast class], @selector(showInView:text:duration:));
                const char *types = method_getTypeEncoding(m);
                class_addMethod([UIWindow class], @selector(hh_myTap:), (IMP)handleDoubleTap, "v@:@");
                gDoubleTap = [[UITapGestureRecognizer alloc] initWithTarget:w action:@selector(hh_myTap:)];
                gDoubleTap.numberOfTapsRequired = 2;
                gDoubleTap.cancelsTouchesInView = NO;
                [w addGestureRecognizer:gDoubleTap];
                HHLog(@"✅ 已在KeyWindow上附加双击手势: %@", w);
            }
        });
    });
}

// ==================== dylib constructor ================
// 这是dylib被加载时 dyld 自动调用的入口 (等价于 Theos 的 %ctor)
// 注意：不要在这里做太耗时的事，会卡住App启动
__attribute__((constructor))
static void MyTweakEntry(void) {
    @autoreleasepool {
        HHLog(@"========================================");
        HHLog(@"🚀 MyTweak.dylib 已注入！ 进程: %@", NSProcessInfo.processInfo.processName);
        HHLog(@"📦 BundleID: %@", [NSBundle mainBundle].bundleIdentifier);
        HHLog(@"🔧 可执行文件: %@", [NSBundle mainBundle].executablePath.lastPathComponent);
        HHLog(@"========================================");
        
        // 可在这里按BundleID白名单判断要不要激活（可选）
        // NSString *bid = [NSBundle mainBundle].bundleIdentifier;
        // if (![bid hasPrefix:@"com.tencent.xin"] && ![bid hasPrefix:@"com.ss.iphone.ugc.Aweme"]) return;
        
        // ====== 核心Hook操作放在 dispatch_async 或 +load 里更安全 ======
        // 构造函数执行时机极早，部分framework可能尚未初始化
        // 稳妥做法：用objc_getClass延迟判断
        dispatch_async(dispatch_get_main_queue(), ^{
            @autoreleasepool {
                HHLog(@"🏗️ 开始执行Hook...");
                
                // Hook 1: 任意UIViewController的viewDidAppear: （首次弹激活提示）
                Class vcCls = [UIViewController class];
                SEL vdaSel = @selector(viewDidAppear:);
                IMP newVDA = imp_implementationWithBlock(^(id _self, BOOL animated){
                    if (Orig_VC_viewDidAppear) {
                        Orig_VC_viewDidAppear(_self, @selector(viewDidAppear:), animated);
                    } else {
                        ((void(*)(id,SEL,BOOL))objc_msgSend)(_self, @selector(viewDidAppear:), animated);
                    }
                    static dispatch_once_t once;
                    dispatch_once(&once, ^{
                        UIViewController *top = _self;
                        while (top.presentedViewController) top = top.presentedViewController;
                        NSString *bid = [NSBundle mainBundle].bundleIdentifier ?: @"";
                        NSString *appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"]
                                            ?: [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"] ?: @"App";
                        NSString *msg = [NSString stringWithFormat:@"🎉 MyTweak 已成功注入\nApp: %@\n%@\n💡 双击屏幕呼出菜单",
                                         appName, bid.length ? [NSString stringWithFormat:@"Bundle: %@", bid] : @""];
                        [HHToast showInView:top.view ?: ((UIViewController*)_self).view text:msg duration:3.5];
                        HHLog(@"🎯 激活提示已展示");
                    });
                });
                hh_hookWithCydiaSubstrate(vcCls, vdaSel, newVDA, (IMP *)&Orig_VC_viewDidAppear);
                
                // Hook 2: UIApplication -sendEvent: 用于附加双击手势
                Class appCls = [UIApplication class];
                SEL seSel = @selector(sendEvent:);
                IMP newSE = imp_implementationWithBlock(^(UIApplication *_self, UIEvent *evt){
                    if (Orig_SendEvent) Orig_SendEvent(_self, seSel, evt);
                    static dispatch_once_t t;
                    dispatch_once(&t, ^{
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                            UIWindow *key = nil;
                            for (UIWindow *w in _self.windows) if (!w.hidden) { key = w; break; }
                            if (!key) key = _self.keyWindow;
                            if (key) {
                                // 动态给UIWindow加一个方法作为手势target
                                if (!class_getInstanceMethod([key class], @selector(hh_rootTweakDoubleTap:))) {
                                    class_addMethod([key class], @selector(hh_rootTweakDoubleTap:),
                                                    (IMP)handleDoubleTap, "v@:@");
                                }
                                UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
                                    initWithTarget:key action:@selector(hh_rootTweakDoubleTap:)];
                                tap.numberOfTapsRequired = 2;
                                tap.cancelsTouchesInView = NO;
                                tap.delaysTouchesEnded = NO;
                                [key addGestureRecognizer:tap];
                                HHLog(@"✅ 双击手势已安装到 %@", key);
                            }
                        });
                    });
                });
                hh_hookWithCydiaSubstrate(appCls, seSel, newSE, (IMP *)&Orig_SendEvent);
                
                // Hook 3: 示例 - 如果有HomeViewController就Hook它
                hookIfClassExists("HomeViewController", @selector(onBtnClick:),
                                  imp_implementationWithBlock(^(id _self, id sdr){
                    HHLog(@"拦截HomeViewController.onBtnClick: %@", sdr);
                    if (Orig_HomeBtnClick) Orig_HomeBtnClick(_self, @selector(onBtnClick:), sdr);
                }), (IMP *)&Orig_HomeBtnClick);
                
                HHLog(@"🏁 所有Hook安装完成 ✓");
            }
        });
    }
}
