//
//  PDDSaver.m
//  PDD 商品图片一键提取 Tweak
//
//  策略1: Hook SDWebImage → 拦截所有加载的图片URL → 按域名过滤保留商品图
//  策略2: Hook AMImageURLInfo → 直接读取商品Model里的图片URL
//  策略3: Hook PDDGoodsDetailPhotoController → 拿到当前详情页所有图片
//
//  注入到PDD后：浏览商品 → 双击屏幕 → 自动复制所有图片URL到粘贴板
//                              → 弹出菜单选择"保存全部图片"
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <dlfcn.h>

#define HHLog(fmt, ...) NSLog(@"[PDDSaver] " fmt, ##__VA_ARGS__)

// ================ 图片URL收集器 ================
@interface PDDSaverImageCollector : NSObject
+ (instancetype)shared;
- (void)addImageURL:(NSString *)url title:(NSString *)title;
- (NSArray<NSDictionary *> *)allImages;
- (void)clear;
- (void)saveAllToAlbum;
@end

@implementation PDDSaverImageCollector {
    NSMutableArray<NSDictionary *> *_images;
    NSMutableSet<NSString *> *_urlSet;  // 去重
    dispatch_queue_t _queue;
}

+ (instancetype)shared {
    static PDDSaverImageCollector *inst;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ inst = [[PDDSaverImageCollector alloc] init]; });
    return inst;
}

- (instancetype)init {
    if (self = [super init]) {
        _images = [NSMutableArray array];
        _urlSet = [NSMutableSet set];
        _queue = dispatch_queue_create("com.pddsaver.collect", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)addImageURL:(NSString *)url title:(NSString *)title {
    if (!url.length) return;
    dispatch_async(_queue, ^{
        @synchronized (_urlSet) {
            if ([_urlSet containsObject:url]) return;
            [_urlSet addObject:url];
        }
        @synchronized (_images) {
            [_images addObject:@{@"url": url, @"title": title ?: @""}];
        }
        HHLog(@"📷 捕获图片 [%@]: %@", title, url);
    });
}

- (NSArray<NSDictionary *> *)allImages {
    @synchronized (_images) {
        return [_images copy];
    }
}

- (void)clear {
    @synchronized (_images) { [_images removeAllObjects]; }
    @synchronized (_urlSet) { [_urlSet removeAllObjects]; }
}

- (void)saveAllToAlbum {
    NSArray *imgs = [self allImages];
    NSString *text = [NSString stringWithFormat:@"📦 PDD商品图片 (%lu张)\n\n", (unsigned long)imgs.count];
    for (NSDictionary *d in imgs) {
        text = [text stringByAppendingFormat:@"%@\n", d[@"url"]];
    }
    [[UIPasteboard generalPasteboard] setString:text];
    HHLog(@"✅ 已复制 %lu 张图片URL到粘贴板", (unsigned long)imgs.count);
}
@end

// ================ 策略1: Hook SDWebImage ================
// SDWebImageDownloader 负责下载图片, SDWebImageManager 负责调度

static void (*orig_SDWebImageDownloader_download_)(id, SEL, id, id, id);
static void hook_SDWebImageDownloader_download(id self, SEL _cmd, id url, id options, id context) {
    // url可能是NSURL或NSString
    NSString *urlStr = nil;
    if ([url isKindOfClass:[NSURL class]]) {
        urlStr = [((NSURL *)url) absoluteString];
    } else if ([url isKindOfClass:[NSString class]]) {
        urlStr = (NSString *)url;
    }
    
    if (urlStr) {
        // 只过滤PDD图片域名
        if ([urlStr containsString:@"pddpic.com"] ||
            [urlStr containsString:@"yangkeduo.com"] ||
            [urlStr containsString:@"pddcdn.com"]) {
            // 过滤掉明显的UI icon (太小的图)
            if ([urlStr rangeOfString:@"icon" options:NSCaseInsensitiveSearch].location == NSNotFound &&
                [urlStr rangeOfString:@"avatar" options:NSCaseInsensitiveSearch].location == NSNotFound &&
                [urlStr rangeOfString:@"arrow" options:NSCaseInsensitiveSearch].location == NSNotFound) {
                [[PDDSaverImageCollector shared] addImageURL:urlStr title:@"SDWebImage拦截"];
            }
        }
    }
    if (orig_SDWebImageDownloader_download_) {
        orig_SDWebImageDownloader_download_(self, _cmd, url, options, context);
    }
}

// ================ 策略2: Hook GoodsImageModel ================

static void (*orig_GoodsImageModel_setUrl_)(id, SEL, id);
static void hook_GoodsImageModel_setUrl(id self, SEL _cmd, id url) {
    if (orig_GoodsImageModel_setUrl_) orig_GoodsImageModel_setUrl_(self, _cmd, url);
    NSString *urlStr = nil;
    if ([url isKindOfClass:[NSString class]]) urlStr = url;
    else if ([url isKindOfClass:[NSURL class]]) urlStr = [url absoluteString];
    if (urlStr && [urlStr containsString:@"pddpic.com"]) {
        // 尝试取goodsName或title
        NSString *title = @"商品图";
        if ([self respondsToSelector:@selector(title)]) {
            id t = [self performSelector:@selector(title)];
            if ([t isKindOfClass:[NSString class]]) title = t;
        } else if ([self respondsToSelector:@selector(goods_name)]) {
            id t = [self performSelector:@selector(goods_name)];
            if ([t isKindOfClass:[NSString class]]) title = t;
        }
        [[PDDSaverImageCollector shared] addImageURL:urlStr title:title];
    }
}

// ================ 策略3: Hook AMImageURLInfo ================

static void (*orig_AMImageURLInfo_setUrl_)(id, SEL, id);
static void hook_AMImageURLInfo_setUrl(id self, SEL _cmd, id url) {
    if (orig_AMImageURLInfo_setUrl_) orig_AMImageURLInfo_setUrl_(self, _cmd, url);
    NSString *urlStr = nil;
    if ([url isKindOfClass:[NSString class]]) urlStr = url;
    else if ([url isKindOfClass:[NSURL class]]) urlStr = [url absoluteString];
    if (urlStr && ([urlStr containsString:@"pddpic.com"] || [urlStr containsString:@"yangkeduo.com"])) {
        [[PDDSaverImageCollector shared] addImageURL:urlStr title:@"AMImageURLInfo"];
    }
}

// ================ UI工具方法 ================

static void showToast(NSString *text, UIView *view) {
    UILabel *l = [[UILabel alloc] init];
    l.text = text;
    l.textColor = [UIColor whiteColor];
    l.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.8];
    l.textAlignment = NSTextAlignmentCenter;
    l.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    l.layer.cornerRadius = 8;
    l.layer.masksToBounds = YES;
    l.frame = CGRectMake(0, 0, 200, 40);
    l.center = CGPointMake(view.bounds.size.width/2, view.bounds.size.height - 150);
    l.alpha = 0;
    [view addSubview:l];
    [UIView animateWithDuration:0.3 animations:^{ l.alpha = 1; }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.3 animations:^{ l.alpha = 0; } completion:^(BOOL f){ [l removeFromSuperview]; }];
    });
}

static void tryScanGoodsModel(void) {
    Class goodsModelCls = objc_getClass("GoodsModel");
    Class goodsImgModelCls = objc_getClass("GoodsImageModel");
    HHLog(@"GoodsModel: %@, GoodsImageModel: %@", goodsModelCls, goodsImgModelCls);
    if (goodsImgModelCls) {
        unsigned int pCount = 0;
        objc_property_t *props = class_copyPropertyList(goodsImgModelCls, &pCount);
        HHLog(@"GoodsImageModel 属性列表:");
        for (unsigned int i = 0; i < pCount && i < 20; i++) {
            HHLog(@"  - %s", property_getName(props[i]));
        }
        free(props);
    }
}

// ================ 双击手势菜单 ================

static void showMenu(UIView *view) {
    UIViewController *vc = nil;
    UIResponder *resp = view;
    while (resp && ![resp isKindOfClass:[UIViewController class]]) resp = [resp nextResponder];
    vc = (UIViewController *)resp;
    if (!vc) {
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (!w.hidden && w.rootViewController) {
                vc = w.rootViewController;
                while (vc.presentedViewController) vc = vc.presentedViewController;
                break;
            }
        }
    }
    if (!vc) return;
    
    NSArray *images = [[PDDSaverImageCollector shared] allImages];
    NSInteger count = images.count;
    
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"📷 PDD图片提取"
                                                                message:[NSString stringWithFormat:@"已捕获 %ld 张商品图片", (long)count]
                                                         preferredStyle:UIAlertControllerStyleActionSheet];
    
    if (count > 0) {
        [ac addAction:[UIAlertAction actionWithTitle:@"📋 复制全部URL到粘贴板" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [[PDDSaverImageCollector shared] saveAllToAlbum];
            showToast(@"✅ URL已复制！", vc.view);
        }]];
        [ac addAction:[UIAlertAction actionWithTitle:@"🗑️ 清空已收集" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
            [[PDDSaverImageCollector shared] clear];
            showToast(@"已清空", vc.view);
        }]];
    }
    [ac addAction:[UIAlertAction actionWithTitle:@"🔄 扫描GoodsImageModel" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        tryScanGoodsModel();
        showToast(@"已扫描，看日志", vc.view);
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    if ([ac respondsToSelector:@selector(popoverPresentationController)]) {
        ac.popoverPresentationController.sourceView = view;
        ac.popoverPresentationController.sourceRect = CGRectMake(view.bounds.size.width/2, view.bounds.size.height/2, 0, 0);
    }
    [vc presentViewController:ac animated:YES completion:nil];
}

// ================ swizzle 工具 ================
static void swizzleClassMethod(Class cls, SEL sel, IMP newImp, IMP *origStore) {
    Method m = class_getClassMethod(cls, sel);
    if (!m) {
        // 尝试实例方法
        m = class_getInstanceMethod(cls, sel);
        if (!m) { HHLog(@"⚠️ 方法不存在 %@ %@", cls, NSStringFromSelector(sel)); return; }
    }
    if (origStore) *origStore = method_getImplementation(m);
    method_setImplementation(m, newImp);
    HHLog(@"✅ Hook: %@ %@", cls, NSStringFromSelector(sel));
}

// ================ dylib 入口 ================
__attribute__((constructor))
static void PDDEntry(void) {
    @autoreleasepool {
        HHLog(@"🚀 PDDSaver.dylib 已注入PDD");
        HHLog(@"📱 BundleID: %@", [NSBundle mainBundle].bundleIdentifier);
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @autoreleasepool {
                HHLog(@"🏗️ 开始安装Hooks...");
                
                // === 策略1: Hook SDWebImage ===
                Class downloaderCls = objc_getClass("SDWebImageDownloader");
                if (downloaderCls) {
                    HHLog(@"✅ 检测到 SDWebImageDownloader");
                    // downloadImageWithURL:options:context:
                    // 实际方法可能是 downloadImageWithURL:options:progress:completed: 或 downloadImageWithURL:
                    SEL sel1 = @selector(downloadImageWithURL:options:context:);
                    SEL sel2 = @selector(downloadImageWithURL:options:progress:completed:);
                    SEL sel3 = @selector(downloadImageWithURL:);
                    
                    for (SEL s in @[sel1, sel2, sel3]) {
                        if ([downloaderCls instancesRespondToSelector:s]) {
                            HHLog(@"  Hook方法: %@", NSStringFromSelector(s));
                            // 不太好直接hook多参数block方法，换一个思路Hook NSURLConnection/NSURLSession
                            break;
                        }
                    }
                }
                
                // === 策略1b: Hook SDWebImageManager（更上层，更容易） ===
                // loadImageWithURL:options:progress:completed:
                Class managerCls = objc_getClass("SDWebImageManager");
                SEL loadSel = @selector(loadImageWithURL:options:progress:completed:);
                if (managerCls && [managerCls instancesRespondToSelector:loadSel]) {
                    HHLog(@"  Hook SDWebImageManager.loadImageWithURL:");
                    Method loadM = class_getInstanceMethod(managerCls, loadSel);
                    IMP loadOrig = method_getImplementation(loadM);
                    
                    IMP loadNew = imp_implementationWithBlock(^(id _self, NSURL *url, NSInteger options, id progress, id completed) {
                        if (url.absoluteString.length > 0) {
                            NSString *s = url.absoluteString;
                            if (([s containsString:@"pddpic.com"] || [s containsString:@"yangkeduo.com"]) &&
                                [s rangeOfString:@"icon" options:NSCaseInsensitiveSearch].location == NSNotFound &&
                                [s rangeOfString:@"avatar" options:NSCaseInsensitiveSearch].location == NSNotFound) {
                                [[PDDSaverImageCollector shared] addImageURL:s title:@"SDWebImage"];
                            }
                        }
                        ((void(*)(id,SEL,NSURL*,NSInteger,id,id))loadOrig)(_self, loadSel, url, options, progress, completed);
                    });
                    method_setImplementation(loadM, loadNew);
                    HHLog(@"✅ SDWebImageManager Hook 安装成功");
                } else {
                    HHLog(@"⚠️ SDWebImageManager hook失败，类=%@" , managerCls);
                }
                
                // === 策略2: Hook GoodsImageModel ===
                Class gimCls = objc_getClass("GoodsImageModel");
                if (gimCls) {
                    // 找setUrl: 或 setImage_url: 或 setThumb_url:
                    SEL urlSel = nil;
                    for (NSString *selName in @[@"setUrl:", @"setImage_url:", @"setImageUrl:", @"setThumb_url:", @"setImgUrl:", @"setThumbUrl:"]) {
                        SEL s = NSSelectorFromString(selName);
                        if ([gimCls instancesRespondToSelector:s]) {
                            urlSel = s;
                            break;
                        }
                    }
                    if (urlSel) {
                        Method m = class_getInstanceMethod(gimCls, urlSel);
                        IMP orig = method_getImplementation(m);
                        IMP new = imp_implementationWithBlock(^(id _self, NSString *_url){
                            ((void(*)(id,SEL,NSString*))orig)(_self, urlSel, _url);
                            if (_url && [_url containsString:@"pddpic"]) {
                                [[PDDSaverImageCollector shared] addImageURL:_url title:@"GoodsImageModel"];
                            }
                        });
                        method_setImplementation(m, new);
                        HHLog(@"✅ GoodsImageModel.%@ Hook 安装成功", NSStringFromSelector(urlSel));
                    } else {
                        HHLog(@"⚠️ GoodsImageModel 存在但没有找到setUrl方法，打印属性:");
                        [PDDSaverImageCollector tryScanGoodsModel];
                    }
                } else {
                    HHLog(@"⚠️ GoodsImageModel 类不存在");
                }
                
                // === 策略3: Hook PDDGoodsDetailPhotoController ===
                Class photoCls = objc_getClass("PDDGoodsDetailPhotoController");
                if (photoCls) {
                    HHLog(@"✅ 检测到 PDDGoodsDetailPhotoController");
                    // 找viewDidLoad或者展示图片的方法
                    if ([photoCls instancesRespondToSelector:@selector(viewDidLoad)]) {
                        SEL vdlSel = @selector(viewDidLoad);
                        Method vdlM = class_getInstanceMethod(photoCls, vdlSel);
                        IMP vdlOrig = method_getImplementation(vdlM);
                        IMP vdlNew = imp_implementationWithBlock(^(id _self){
                            ((void(*)(id,SEL))vdlOrig)(_self, vdlSel);
                            HHLog(@"📷 商品详情图片页已加载");
                        });
                        method_setImplementation(vdlM, vdlNew);
                        HHLog(@"✅ PDDGoodsDetailPhotoController.viewDidLoad Hook 安装成功");
                    }
                }
                
                // === 安装双击手势 ===
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    UIWindow *key = nil;
                    for (UIWindow *w in [UIApplication sharedApplication].windows) {
                        if (!w.hidden && w.isKeyWindow) { key = w; break; }
                    }
                    if (!key) key = [UIApplication sharedApplication].keyWindow;
                    if (key) {
                        if (!class_getInstanceMethod([key class], @selector(pddsaver_doubleTap:))) {
                            class_addMethod([key class], @selector(pddsaver_doubleTap:), (IMP)showMenu, "v@:@");
                        }
                        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:key action:@selector(pddsaver_doubleTap:)];
                        tap.numberOfTapsRequired = 2;
                        tap.cancelsTouchesInView = NO;
                        [key addGestureRecognizer:tap];
                        HHLog(@"✅ 双击手势已安装到 %@", key);
                    }
                });
                
                HHLog(@"🏁 所有Hook安装完成");
            }
        });
    }
}
