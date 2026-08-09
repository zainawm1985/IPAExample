//
//  PDDSaver.m  v2
//  浮窗实时显示 + 多层兜底Hook
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <dlfcn.h>

#define HHLog(fmt, ...) NSLog(@"[PDDSaver] " fmt, ##__VA_ARGS__)

// ==================== 图片收集器 ====================
@interface ImgCollector : NSObject
@property (nonatomic, copy) void(^onCountChanged)(NSInteger count);
- (void)addURL:(NSString *)url from:(NSString *)source;
- (NSArray<NSString *> *)allURLs;
- (void)clear;
- (NSInteger)count;
@end

@implementation ImgCollector {
    NSMutableArray<NSString *> *_urls;
    NSMutableSet<NSString *> *_seen;
}
- (instancetype)init { self = [super init]; _urls = [NSMutableArray new]; _seen = [NSMutableSet new]; return self; }
- (void)addURL:(NSString *)url from:(NSString *)source {
    if (!url.length) return;
    @synchronized(_seen) {
        if ([_seen containsObject:url]) return;
        [_seen addObject:url];
    }
    @synchronized(_urls) { [_urls addObject:url]; }
    HHLog(@"📷 +1 [%lu] src=%@ url=%@", (unsigned long)_seen.count, source, url);
    if (self.onCountChanged) dispatch_async(dispatch_get_main_queue(), ^{ self.onCountChanged(self.count); });
}
- (NSArray<NSString *> *)allURLs { @synchronized(_urls) { return _urls.copy; } }
- (void)clear { @synchronized(_urls) { [_urls removeAllObjects]; } @synchronized(_seen) { [_seen removeAllObjects]; } }
- (NSInteger)count { @synchronized(_seen) { return _seen.count; } }
@end

// ==================== 悬浮窗 ====================
@interface FloatBall : UIButton
@property (nonatomic, strong) ImgCollector *collector;
+ (void)showWithCollector:(ImgCollector *)c;
@end

@implementation FloatBall {
    CGPoint _startPoint;
    UILabel *_badge;
}

+ (void)showWithCollector:(ImgCollector *)c {
    dispatch_async(dispatch_get_main_queue(), ^{
        FloatBall *ball = [[FloatBall alloc] initWithFrame:CGRectMake(10, 200, 56, 56)];
        ball.collector = c;
        UIWindow *kw = [UIApplication sharedApplication].keyWindow;
        if (!kw) kw = [UIApplication sharedApplication].windows.lastObject;
        [kw addSubview:ball];
        c.onCountChanged = ^(NSInteger n) { [ball updateBadge:n]; };
        HHLog(@"🟢 悬浮窗已显示");
    });
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.75];
        self.layer.cornerRadius = 28;
        self.layer.borderColor = [UIColor whiteColor].CGColor;
        self.layer.borderWidth = 2;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOffset = CGSizeMake(0, 2);
        self.layer.shadowRadius = 4;
        self.layer.shadowOpacity = 0.4;
        self.clipsToBounds = NO;
        
        _badge = [[UILabel alloc] initWithFrame:CGRectMake(-6, -6, 24, 24)];
        _badge.backgroundColor = [UIColor systemRedColor];
        _badge.textColor = [UIColor whiteColor];
        _badge.font = [UIFont boldSystemFontOfSize:11];
        _badge.textAlignment = NSTextAlignmentCenter;
        _badge.layer.cornerRadius = 12;
        _badge.clipsToBounds = YES;
        _badge.text = @"0";
        [self addSubview:_badge];
        
        UILabel *icon = [[UILabel alloc] initWithFrame:CGRectMake(8, 6, 40, 24)];
        icon.text = @"📷";
        icon.font = [UIFont systemFontOfSize:18];
        icon.textAlignment = NSTextAlignmentCenter;
        [self addSubview:icon];
        
        [self addTarget:self action:@selector(tap) forControlEvents:UIControlEventTouchUpInside];
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}

- (void)updateBadge:(NSInteger)n {
    _badge.text = [NSString stringWithFormat:@"%ld", (long)n];
    if (n > 0) _badge.backgroundColor = [UIColor systemGreenColor];
    else _badge.backgroundColor = [UIColor systemRedColor];
}

- (void)drag:(UIPanGestureRecognizer *)g {
    UIView *v = g.view;
    if (g.state == UIGestureRecognizerStateBegan) _startPoint = v.center;
    CGPoint t = [g translationInView:v.superview];
    v.center = CGPointMake(_startPoint.x + t.x, _startPoint.y + t.y);
    if (g.state == UIGestureRecognizerStateEnded) {
        CGFloat x = v.center.x, w = v.superview.bounds.size.width;
        v.center = CGPointMake(x < w/2 ? 38 : w-38, MAX(100, MIN(v.center.y, v.superview.bounds.size.height-100)));
    }
}

- (void)tap {
    NSArray *urls = [self.collector allURLs];
    NSInteger n = urls.count;
    
    // 找当前VC
    UIResponder *r = self;
    while (r && ![r isKindOfClass:[UIViewController class]]) r = [r nextResponder];
    UIViewController *vc = (UIViewController *)r;
    if (!vc) {
        UIWindow *kw = [UIApplication sharedApplication].keyWindow;
        vc = kw.rootViewController;
        while (vc.presentedViewController) vc = vc.presentedViewController;
    }
    
    NSString *msg = n > 0 ? [NSString stringWithFormat:@"已捕获 %ld 张图片\n点复制后粘贴到电脑即可", (long)n] : @"尚未捕获到商品图片\n请浏览商品页试试";
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"📷 PDD图片提取"
                                                                 message:msg
                                                          preferredStyle:UIAlertControllerStyleActionSheet];
    if (n > 0) {
        [ac addAction:[UIAlertAction actionWithTitle:@"📋 复制全部URL" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
            NSString *txt = @"";
            for (NSString *u in urls) txt = [txt stringByAppendingFormat:@"%@\n", u];
            [UIPasteboard generalPasteboard].string = txt;
            [self toast:[NSString stringWithFormat:@"已复制 %ld 个URL", (long)n] inView:vc.view];
        }]];
        [ac addAction:[UIAlertAction actionWithTitle:@"🗑️ 清空" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a){
            [self.collector clear];
            [self updateBadge:0];
            [self toast:@"已清空" inView:vc.view];
        }]];
    }
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [vc presentViewController:ac animated:YES completion:nil];
}

- (void)toast:(NSString *)t inView:(UIView *)v {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(0,0,220,40)];
    l.text = t; l.textColor = UIColor.whiteColor; l.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.85];
    l.textAlignment = NSTextAlignmentCenter; l.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    l.layer.cornerRadius = 8; l.clipsToBounds = YES;
    l.center = CGPointMake(v.bounds.size.width/2, v.bounds.size.height*0.55);
    l.alpha = 0; [v addSubview:l];
    [UIView animateWithDuration:0.25 animations:^{ l.alpha = 1; }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.25 animations:^{ l.alpha = 0; } completion:^(BOOL f){ [l removeFromSuperview]; }];
    });
}
@end

// ==================== 图片URL过滤 ====================
static BOOL isGoodImageURL(NSString *s) {
    if (!s || s.length < 5) return NO;
    // 只保留PDD图片域名
    if (![s containsString:@"pddpic.com"] &&
        ![s containsString:@"yangkeduo.com"] &&
        ![s containsString:@"pddcdn.com"]) return NO;
    // 排除UI图
    s = [s lowercaseString];
    if ([s containsString:@"icon"] || [s containsString:@"avatar"] || [s containsString:@"arrow"] ||
        [s containsString:@"badge"] || [s containsString:@"button"] || [s containsString:@"navi"] ||
        [s containsString:@"tab"] || [s containsString:@"back"] || [s containsString:@"close"] ||
        [s containsString:@"logo"] || [s containsString:@"loading"] || [s containsString:@"placeholder"] ||
        [s containsString:@"empty"]) return NO;
    return YES;
}

// ==================== Hook逻辑 ====================

static ImgCollector *g_collector = nil;

// ---- Hook 1: SDWebImageManager (新版5.x API) ----
static void hook_SDWebImageManager(void) {
    Class cls = objc_getClass("SDWebImageManager");
    if (!cls) { HHLog(@"⚠️ SDWebImageManager 类不存在"); return; }
    HHLog(@"✅ 找到 SDWebImageManager");

    // 新版SDWebImage API: 
    // loadImageWithURL:options:context:progress:completed:
    // loadImageWithURL:options:progress:completed:
    SEL sels[] = {
        @selector(loadImageWithURL:options:context:progress:completed:),
        @selector(loadImageWithURL:options:progress:completed:),
        @selector(loadImageWithURL:progress:completed:),
    };
    
    for (int i = 0; i < 3; i++) {
        Method m = class_getInstanceMethod(cls, sels[i]);
        if (m) {
            IMP orig = method_getImplementation(m);
            IMP new = imp_implementationWithBlock(^(id self, NSURL *url, ...) {
                // 只拦截url参数来记录，不干扰原始逻辑
                if (url && [url isKindOfClass:[NSURL class]]) {
                    NSString *s = url.absoluteString;
                    if (isGoodImageURL(s)) [g_collector addURL:s from:@"SDWebMgr"];
                }
                
                // 转发到原始实现
                // 用va_list处理可变参数
                va_list args;
                va_start(args, url);
                void *arg2 = va_arg(args, void *);
                void *arg3 = va_arg(args, void *);
                id arg4 = va_arg(args, id);
                id arg5 = va_arg(args, id);
                va_end(args);
                
                // 根据原始方法签名调用
                typedef void (*fn5)(id, SEL, NSURL *, void *, void *, id, id);
                ((fn5)orig)(self, sels[i], url, arg2, arg3, arg4, arg5);
            });
            method_setImplementation(m, new);
            HHLog(@"✅ Hook SDWebImageManager: %@", NSStringFromSelector(sels[i]));
            return;
        }
    }
    HHLog(@"⚠️ SDWebImageManager 未找到匹配方法，打印可用方法:");
    unsigned int mc = 0;
    Method *ms = class_copyMethodList(cls, &mc);
    for (unsigned int i = 0; i < MIN(mc, 30); i++) {
        HHLog(@"  - %@", NSStringFromSelector(method_getName(ms[i])));
    }
    free(ms);
}

// ---- Hook 2: NSURLSession dataTaskWithURL (兜底，拦截网络请求) ----
static void hook_NSURLSession(void) {
    Class cls = objc_getClass("NSURLSession");
    // Hook实例方法 dataTaskWithURL:completionHandler:
    SEL sel = @selector(dataTaskWithURL:completionHandler:);
    Method m = class_getInstanceMethod(cls, sel);
    if (m) {
        IMP orig = method_getImplementation(m);
        IMP new = imp_implementationWithBlock(^(id self, NSURL *url, id handler) {
            if (url && [url isKindOfClass:[NSURL class]]) {
                NSString *s = url.absoluteString;
                if (isGoodImageURL(s)) [g_collector addURL:s from:@"NSURLSession"];
            }
            return ((id(*)(id,SEL,NSURL*,id))orig)(self, sel, url, handler);
        });
        method_setImplementation(m, new);
        HHLog(@"✅ Hook NSURLSession dataTaskWithURL:");
    } else {
        HHLog(@"⚠️ NSURLSession dataTaskWithURL: 不存在");
    }
}

// ---- Hook 3: NSURLRequest (拦截所有创建) ----
static void hook_NSURLRequest(void) {
    Class cls = objc_getClass("NSURLRequest");
    SEL sel = @selector(requestWithURL:);
    Method m = class_getClassMethod(cls, sel);
    if (m) {
        IMP orig = method_getImplementation(m);
        IMP new = imp_implementationWithBlock(^(id self, NSURL *url) {
            if (url && [url isKindOfClass:[NSURL class]]) {
                NSString *s = url.absoluteString;
                if (isGoodImageURL(s)) [g_collector addURL:s from:@"NSURLReq"];
            }
            return ((id(*)(id,SEL,NSURL*))orig)(self, sel, url);
        });
        method_setImplementation(m, new);
        HHLog(@"✅ Hook NSURLRequest requestWithURL:");
    }
}

// ---- Hook 4: SDWebImageDownloader ----
static void hook_SDWebImageDownloader(void) {
    Class cls = objc_getClass("SDWebImageDownloader");
    if (!cls) { HHLog(@"⚠️ SDWebImageDownloader 不存在"); return; }
    
    SEL sels[] = {
        @selector(downloadImageWithURL:options:context:),
        @selector(downloadImageWithURL:options:progress:completed:),
        @selector(downloadImageWithURL:completed:),
    };
    
    for (int i = 0; i < 3; i++) {
        Method m = class_getInstanceMethod(cls, sels[i]);
        if (m) {
            IMP orig = method_getImplementation(m);
            IMP new = imp_implementationWithBlock(^(id self, NSURL *url, ...) {
                if (url && [url isKindOfClass:[NSURL class]]) {
                    NSString *s = url.absoluteString;
                    if (isGoodImageURL(s)) [g_collector addURL:s from:@"SDDownload"];
                }
                va_list args; va_start(args, url);
                void *a2 = va_arg(args, void *); void *a3 = va_arg(args, void *);
                id a4 = va_arg(args, id); id a5 = va_arg(args, id); va_end(args);
                typedef void (*fn)(id, SEL, NSURL *, void *, void *, id, id);
                ((fn)orig)(self, sels[i], url, a2, a3, a4, a5);
            });
            method_setImplementation(m, new);
            HHLog(@"✅ Hook SDWebImageDownloader: %@", NSStringFromSelector(sels[i]));
            return;
        }
    }
    HHLog(@"⚠️ SDWebImageDownloader 无匹配方法");
}

// ---- Hook 5: UIImageView sd_setImageWithURL (最简单直接的) ----
static void hook_UIImageView_sd(void) {
    // 这个hook的是UIImageView分类里的方法，最直观
    // sd_setImageWithURL: 
    SEL sel = @selector(sd_setImageWithURL:);
    Method m = class_getInstanceMethod([UIImageView class], sel);
    if (m) {
        IMP orig = method_getImplementation(m);
        IMP new = imp_implementationWithBlock(^(UIImageView *self, NSURL *url) {
            if (url && [url isKindOfClass:[NSURL class]]) {
                NSString *s = url.absoluteString;
                if (isGoodImageURL(s)) [g_collector addURL:s from:@"UIImageView"];
            }
            ((void(*)(id,SEL,NSURL*))orig)(self, sel, url);
        });
        method_setImplementation(m, new);
        HHLog(@"✅ Hook UIImageView sd_setImageWithURL:");
    } else {
        // 试试旧版带placeholder的方法
        SEL sel2 = @selector(sd_setImageWithURL:placeholderImage:);
        m = class_getInstanceMethod([UIImageView class], sel2);
        if (m) {
            IMP orig = method_getImplementation(m);
            IMP new = imp_implementationWithBlock(^(UIImageView *self, NSURL *url, UIImage *placeholder) {
                if (url && [url isKindOfClass:[NSURL class]]) {
                    NSString *s = url.absoluteString;
                    if (isGoodImageURL(s)) [g_collector addURL:s from:@"UIImageView"];
                }
                ((void(*)(id,SEL,NSURL*,UIImage*))orig)(self, sel2, url, placeholder);
            });
            method_setImplementation(m, new);
            HHLog(@"✅ Hook UIImageView sd_setImageWithURL:placeholderImage:");
        } else {
            HHLog(@"⚠️ UIImageView sd_setImageWithURL: 未找到(可能不用SD加载图片)");
        }
    }
}

// ---- Hook 6: GoodsImageModel (精准hook) ----
static void hook_GoodsImageModel(void) {
    Class cls = objc_getClass("GoodsImageModel");
    if (!cls) { HHLog(@"⚠️ GoodsImageModel 类不存在"); return; }
    HHLog(@"✅ GoodsImageModel 存在，打印属性:");
    unsigned int pc = 0;
    objc_property_t *ps = class_copyPropertyList(cls, &pc);
    for (unsigned int i = 0; i < pc; i++) {
        const char *n = property_getName(ps[i]);
        const char *attrs = property_getAttributes(ps[i]);
        HHLog(@"  属性%d: %s (%s)", i+1, n, attrs ? attrs : "?");
    }
    free(ps);
    
    // 尝试常见属性名: url, imageUrl, thumbUrl, image_url, imgUrl, picUrl
    NSArray *candidates = @[@"url", @"imageUrl", @"thumbUrl", @"image_url", @"imgUrl", @"picUrl", @"pictureUrl", @"src"];
    for (NSString *attr in candidates) {
        NSString *setter = [NSString stringWithFormat:@"set%@%@:", 
                           [[attr substringToIndex:1] uppercaseString],
                           [attr substringFromIndex:1]];
        SEL sel = NSSelectorFromString(setter);
        if ([cls instancesRespondToSelector:sel]) {
            Method m = class_getInstanceMethod(cls, sel);
            IMP orig = method_getImplementation(m);
            IMP new = imp_implementationWithBlock(^(id self, NSString *url){
                ((void(*)(id,SEL,NSString*))orig)(self, sel, url);
                if (isGoodImageURL(url)) [g_collector addURL:url from:@"GoodsImgModel"];
            });
            method_setImplementation(m, new);
            HHLog(@"✅ Hook GoodsImageModel: %@", setter);
            return;
        }
    }
    HHLog(@"⚠️ GoodsImageModel 未找到任何图片URL setter (已打印属性列表，请查看)");
}

// ---- Hook 7: AMImageURLInfo ----
static void hook_AMImageURLInfo(void) {
    Class cls = objc_getClass("AMImageURLInfo");
    if (!cls) { HHLog(@"⚠️ AMImageURLInfo 不存在"); return; }
    HHLog(@"✅ AMImageURLInfo 存在，尝试hook url setter");
    
    for (NSString *a in @[@"url", @"imageUrl", @"thumbUrl", @"rawUrl", @"originUrl"]) {
        NSString *s = [NSString stringWithFormat:@"set%@%@:", 
                       [[a substringToIndex:1] uppercaseString], [a substringFromIndex:1]];
        SEL sel = NSSelectorFromString(s);
        if ([cls instancesRespondToSelector:sel]) {
            Method m = class_getInstanceMethod(cls, sel);
            IMP orig = method_getImplementation(m);
            IMP new = imp_implementationWithBlock(^(id self, NSString *url){
                ((void(*)(id,SEL,NSString*))orig)(self, sel, url);
                if (isGoodImageURL(url)) [g_collector addURL:url from:@"AMImgInfo"];
            });
            method_setImplementation(m, new);
            HHLog(@"✅ Hook AMImageURLInfo: %@", s);
            return;
        }
    }
}

// ==================== 入口 ====================
__attribute__((constructor))
static void PDDSaverEntry(void) {
    @autoreleasepool {
        HHLog(@"========================================");
        HHLog(@"🚀 PDDSaver v2 已注入");
        HHLog(@"   BundleID: %@", [NSBundle mainBundle].bundleIdentifier);
        HHLog(@"   架构: %@", @(sizeof(void*))); // 8==arm64
        HHLog(@"========================================");
        
        g_collector = [[ImgCollector alloc] init];
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @autoreleasepool {
                HHLog(@"");
                HHLog(@"🏗️ [诊断] 安装所有Hooks...");
                
                // 策略1: UIImageView sd_setImageWithURL (最简单直接)
                HHLog(@"");
                HHLog(@"--- 策略1: UIImageView.sd_setImageWithURL ---");
                hook_UIImageView_sd();
                
                // 策略2: NSURLRequest (拦截所有网络请求图片)
                HHLog(@"");
                HHLog(@"--- 策略2: NSURLRequest ---");
                hook_NSURLRequest();
                
                // 策略3: NSURLSession (兜底)
                HHLog(@"");
                HHLog(@"--- 策略3: NSURLSession ---");
                hook_NSURLSession();
                
                // 策略4: SDWebImageDownloader
                HHLog(@"");
                HHLog(@"--- 策略4: SDWebImageDownloader ---");
                hook_SDWebImageDownloader();
                
                // 策略5: SDWebImageManager
                HHLog(@"");
                HHLog(@"--- 策略5: SDWebImageManager ---");
                hook_SDWebImageManager();
                
                // 策略6: GoodsImageModel (精准)
                HHLog(@"");
                HHLog(@"--- 策略6: GoodsImageModel ---");
                hook_GoodsImageModel();
                
                // 策略7: AMImageURLInfo
                HHLog(@"");
                HHLog(@"--- 策略7: AMImageURLInfo ---");
                hook_AMImageURLInfo();
                
                HHLog(@"");
                HHLog(@"========================================");
                HHLog(@"🏁 所有Hook安装完成");
                HHLog(@"========================================");
                
                // 显示浮窗
                [FloatBall showWithCollector:g_collector];
            }
        });
    }
}
