//
//  PDDSaver.m  v4 - 实时网络面板 (类似浏览器开发者工具)
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#define HHLog(fmt, ...) NSLog(@"[PDDNet] " fmt, ##__VA_ARGS__)

// ==================== 单条请求记录 ====================
@interface NetEntry : NSObject
@property (nonatomic, copy) NSString *url;
@property (nonatomic, copy) NSString *method;
@property (nonatomic, assign) NSInteger statusCode;
@property (nonatomic, assign) NSInteger bodySize;
@property (nonatomic, copy) NSString *preview;
@property (nonatomic, copy) NSString *time;
@end
@implementation NetEntry
@end

// ==================== 网络面板 (底部抽屉) ====================
@interface NetPanel : UIView <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray<NetEntry *> *entries;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) UILabel *urlLabel;
@property (nonatomic, assign) BOOL expanded;
+ (instancetype)shared;
- (void)show;
- (void)hide;
- (void)toggle;
- (void)addEntry:(NetEntry *)entry;
- (void)clear;
@end

@implementation NetPanel

+ (instancetype)shared {
    static NetPanel *inst;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ inst = [[NetPanel alloc] init]; });
    return inst;
}

- (instancetype)init {
    CGFloat h = UIScreen.mainScreen.bounds.size.height;
    CGFloat w = UIScreen.mainScreen.bounds.size.width;
    CGRect frame = CGRectMake(0, h - 320, w, 320);
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.95];
        self.layer.cornerRadius = 12;
        self.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
        self.layer.shadowColor = UIColor.blackColor.CGColor;
        self.layer.shadowOffset = CGSizeMake(0, -2);
        self.layer.shadowRadius = 8;
        self.layer.shadowOpacity = 0.5;
        self.entries = [NSMutableArray array];
        
        // 顶部栏
        UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 40)];
        header.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1];
        
        // 折叠按钮
        UIButton *foldBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        foldBtn.frame = CGRectMake(8, 4, 36, 32);
        [foldBtn setTitle:@"❮" forState:UIControlStateNormal];
        foldBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
        foldBtn.tintColor = [UIColor colorWithRed:0.3 green:0.7 blue:1 alpha:1];
        [foldBtn addTarget:self action:@selector(toggleFold) forControlEvents:UIControlEventTouchUpInside];
        [header addSubview:foldBtn];
        
        // 标题
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(50, 0, 60, 40)];
        title.text = @"📡 网络";
        title.textColor = UIColor.whiteColor;
        title.font = [UIFont boldSystemFontOfSize:13];
        [header addSubview:title];
        
        // 计数
        _countLabel = [[UILabel alloc] initWithFrame:CGRectMake(105, 0, 80, 40)];
        _countLabel.text = @"0条";
        _countLabel.textColor = [UIColor colorWithRed:0.3 green:0.7 blue:1 alpha:1];
        _countLabel.font = [UIFont systemFontOfSize:12];
        [header addSubview:_countLabel];
        
        // 清空按钮
        UIButton *clearBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        clearBtn.frame = CGRectMake(w - 80, 4, 36, 32);
        [clearBtn setTitle:@"🗑" forState:UIControlStateNormal];
        [clearBtn addTarget:self action:@selector(clearTap) forControlEvents:UIControlEventTouchUpInside];
        [header addSubview:clearBtn];
        
        // 复制按钮
        UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        copyBtn.frame = CGRectMake(w - 45, 4, 36, 32);
        [copyBtn setTitle:@"📋" forState:UIControlStateNormal];
        [copyBtn addTarget:self action:@selector(copyTap) forControlEvents:UIControlEventTouchUpInside];
        [header addSubview:copyBtn];
        
        [self addSubview:header];
        
        // URL 预览标签
        _urlLabel = [[UILabel alloc] initWithFrame:CGRectMake(8, 44, w-16, 28)];
        _urlLabel.text = @"点击请求行查看详情";
        _urlLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1];
        _urlLabel.font = [UIFont systemFontOfSize:10];
        _urlLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [self addSubview:_urlLabel];
        
        // 表格
        _tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 72, w, 248) style:UITableViewStylePlain];
        _tableView.backgroundColor = UIColor.clearColor;
        _tableView.separatorColor = [UIColor colorWithWhite:0.25 alpha:1];
        _tableView.dataSource = self;
        _tableView.delegate = self;
        _tableView.rowHeight = 36;
        [_tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"c"];
        [self addSubview:_tableView];
        
        // 拖动手柄
        UIView *handle = [[UIView alloc] initWithFrame:CGRectMake(w/2-18, 6, 36, 4)];
        handle.backgroundColor = [UIColor colorWithWhite:0.4 alpha:1];
        handle.layer.cornerRadius = 2;
        [self addSubview:handle];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panHeader:)];
        [header addGestureRecognizer:pan];
        
        self.hidden = YES;
    }
    return self;
}

- (void)show {
    if (!self.superview) {
        UIWindow *kw = [UIApplication sharedApplication].keyWindow;
        if (!kw) kw = [UIApplication sharedApplication].windows.firstObject;
        [kw addSubview:self];
    }
    self.hidden = NO;
    [self.superview bringSubviewToFront:self];
}

- (void)hide { self.hidden = YES; }

- (void)toggle {
    if (self.hidden) [self show]; else [self hide];
}

- (void)toggleFold {
    _expanded = !_expanded;
    CGFloat h = _expanded ? 44 : 320;
    CGFloat sh = UIScreen.mainScreen.bounds.size.height;
    CGFloat w = UIScreen.mainScreen.bounds.size.width;
    [UIView animateWithDuration:0.25 animations:^{
        self.frame = CGRectMake(0, sh - h, w, 320);
    }];
}

- (void)panHeader:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.superview];
    CGFloat sh = UIScreen.mainScreen.bounds.size.height;
    CGFloat w = UIScreen.mainScreen.bounds.size.width;
    self.frame = CGRectMake(0, MAX(60, self.frame.origin.y + t.y), w, 320);
    [g setTranslation:CGPointZero inView:self.superview];
    if (g.state == UIGestureRecognizerStateEnded) {
        CGFloat mid = sh - 180;
        CGFloat target = self.frame.origin.y < mid ? 60 : sh - 320;
        [UIView animateWithDuration:0.2 animations:^{
            self.frame = CGRectMake(0, target, w, 320);
        }];
    }
}

- (void)addEntry:(NetEntry *)entry {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.entries insertObject:entry atIndex:0];
        if (self.entries.count > 200) [self.entries removeLastObject];
        self.countLabel.text = [NSString stringWithFormat:@"%lu条", (unsigned long)self.entries.count];
        HHLog(@"[%@@%ld %ldB] %@", entry.method, (long)entry.statusCode, (long)entry.bodySize, entry.url);
        [self.tableView reloadData];
    });
}

- (void)clearTap {
    [self.entries removeAllObjects];
    self.countLabel.text = @"0条";
    self.urlLabel.text = @"点击请求行查看详情";
    [self.tableView reloadData];
}

- (void)clear { [self clearTap]; }

- (void)copyTap {
    NSMutableString *s = [NSMutableString string];
    for (NetEntry *e in self.entries) {
        [s appendFormat:@"[%@@%ld %ldB] %@\n", e.method, (long)e.statusCode, (long)e.bodySize, e.url];
    }
    [UIPasteboard generalPasteboard].string = s;
    [self flashToast:[NSString stringWithFormat:@"已复制%lu条", (unsigned long)self.entries.count]];
}

- (void)flashToast:(NSString *)txt {
    UILabel *l = [[UILabel alloc] init];
    l.text = txt;
    l.textColor = UIColor.whiteColor;
    l.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.8];
    l.textAlignment = NSTextAlignmentCenter;
    l.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    l.layer.cornerRadius = 6; l.clipsToBounds = YES;
    [l sizeToFit];
    l.frame = CGRectMake(0, 0, l.frame.size.width+16, 30);
    l.center = CGPointMake(self.bounds.size.width/2, self.bounds.size.height/2);
    l.alpha = 0;
    [self addSubview:l];
    [UIView animateWithDuration:0.2 animations:^{ l.alpha = 1; }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.5*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.2 animations:^{ l.alpha = 0; } completion:^(BOOL f){ [l removeFromSuperview]; }];
    });
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return self.entries.count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"c"];
    NetEntry *e = self.entries[ip.row];
    
    UIColor *sc; NSString *scTxt;
    if (e.statusCode == 0) { sc = UIColor.grayColor; scTxt = @"···"; }
    else if (e.statusCode < 300) { sc = UIColor.greenColor; scTxt = [NSString stringWithFormat:@"%ld",(long)e.statusCode]; }
    else if (e.statusCode < 400) { sc = UIColor.yellowColor; scTxt = [NSString stringWithFormat:@"%ld",(long)e.statusCode]; }
    else { sc = UIColor.redColor; scTxt = [NSString stringWithFormat:@"%ld",(long)e.statusCode]; }
    
    UIColor *mc;
    if ([e.method isEqualToString:@"GET"])     mc = [UIColor colorWithRed:0.2 green:0.7 blue:0.3 alpha:1];
    else if ([e.method isEqualToString:@"POST"])    mc = [UIColor colorWithRed:0.9 green:0.6 blue:0.1 alpha:1];
    else if ([e.method isEqualToString:@"PUT"])     mc = [UIColor colorWithRed:0.3 green:0.5 blue:0.9 alpha:1];
    else if ([e.method isEqualToString:@"DELETE"])  mc = UIColor.redColor;
    else mc = UIColor.grayColor;
    
    NSString *shortURL = e.url;
    if (shortURL.length > 55) shortURL = [[shortURL substringToIndex:52] stringByAppendingString:@"..."];
    
    NSString *sz = e.bodySize > 1024 ? [NSString stringWithFormat:@"%.1fK", e.bodySize/1024.0]
                 : [NSString stringWithFormat:@"%ldB", (long)e.bodySize];
    
    NSMutableAttributedString *as = [[NSMutableAttributedString alloc] init];
    [as appendAttributedString:[[NSAttributedString alloc] initWithString:e.method attributes:@{NSForegroundColorAttributeName:mc, NSFontAttributeName:[UIFont boldSystemFontOfSize:11]}]];
    [as appendAttributedString:[[NSAttributedString alloc] initWithString:@"  " attributes:nil]];
    [as appendAttributedString:[[NSAttributedString alloc] initWithString:scTxt attributes:@{NSForegroundColorAttributeName:sc, NSFontAttributeName:[UIFont boldSystemFontOfSize:11]}]];
    [as appendAttributedString:[[NSAttributedString alloc] initWithString:@"  " attributes:nil]];
    [as appendAttributedString:[[NSAttributedString alloc] initWithString:shortURL attributes:@{NSForegroundColorAttributeName:[UIColor colorWithWhite:0.85 alpha:1], NSFontAttributeName:[UIFont systemFontOfSize:11]}]];
    [as appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"  %@", sz] attributes:@{NSForegroundColorAttributeName:[UIColor colorWithWhite:0.5 alpha:1], NSFontAttributeName:[UIFont systemFontOfSize:10]}]];
    
    c.textLabel.attributedText = as;
    c.textLabel.numberOfLines = 1;
    c.textLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    c.backgroundColor = ip.row % 2 == 0 ? [UIColor colorWithWhite:0.14 alpha:1] : [UIColor colorWithWhite:0.1 alpha:1];
    c.selectionStyle = UITableViewCellSelectionStyleGray;
    
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    NetEntry *e = self.entries[ip.row];
    self.urlLabel.text = e.url;
    self.urlLabel.textColor = [UIColor colorWithRed:0.4 green:0.7 blue:1 alpha:1];
    [UIPasteboard generalPasteboard].string = e.url;
    [self flashToast:@"URL已复制"];
}

@end

// ==================== 浮球 ====================
@interface FloatBall : UIButton @end

@implementation FloatBall { CGPoint _start; }

+ (void)show {
    dispatch_async(dispatch_get_main_queue(), ^{
        FloatBall *b = [[FloatBall alloc] initWithFrame:CGRectMake(UIScreen.mainScreen.bounds.size.width - 56, 200, 48, 48)];
        b.backgroundColor = [[UIColor colorWithRed:0.2 green:0.5 blue:0.9 alpha:1] colorWithAlphaComponent:0.85];
        b.layer.cornerRadius = 24;
        b.layer.borderColor = UIColor.whiteColor.CGColor;
        b.layer.borderWidth = 1.5;
        b.layer.shadowColor = UIColor.blackColor.CGColor;
        b.layer.shadowOffset = CGSizeMake(0,2);
        b.layer.shadowRadius = 4;
        b.layer.shadowOpacity = 0.4;
        b.clipsToBounds = NO;
        
        UILabel *icon = [[UILabel alloc] initWithFrame:CGRectMake(0, 2, 48, 44)];
        icon.text = @"📡"; icon.font = [UIFont systemFontOfSize:18]; icon.textAlignment = NSTextAlignmentCenter;
        [b addSubview:icon];
        
        [b addTarget:b action:@selector(tap) forControlEvents:UIControlEventTouchUpInside];
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:b action:@selector(drag:)];
        [b addGestureRecognizer:pan];
        
        UIWindow *kw = [UIApplication sharedApplication].keyWindow;
        if (!kw) kw = [UIApplication sharedApplication].windows.firstObject;
        [kw addSubview:b];
    });
}

- (void)tap { [[NetPanel shared] toggle]; }

- (void)drag:(UIPanGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) _start = g.view.center;
    CGPoint t = [g translationInView:g.view.superview];
    g.view.center = CGPointMake(_start.x+t.x, _start.y+t.y);
    if (g.state == UIGestureRecognizerStateEnded) {
        CGFloat x = g.view.center.x, w = g.view.superview.bounds.size.width;
        [UIView animateWithDuration:0.2 animations:^{ g.view.center = CGPointMake(x<w/2?34:w-34, g.view.center.y); }];
    }
}

@end

// ==================== NSURLSession Hook ====================

static NSString *safePreview(NSData *data, NSUInteger maxLen) {
    if (!data || data.length == 0) return @"";
    NSUInteger len = MIN(data.length, maxLen);
    NSString *s = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, len)] encoding:NSUTF8StringEncoding];
    if (!s) s = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, len)] encoding:NSASCIIStringEncoding];
    if (!s) s = [NSString stringWithFormat:@"(binary %luB)", (unsigned long)data.length];
    s = [s stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    s = [s stringByReplacingOccurrencesOfString:@"\r" withString:@""];
    if (data.length > maxLen) s = [s stringByAppendingString:@"..."];
    return s;
}

typedef NSURLSessionDataTask *(*DataTaskWithReqFn)(id, SEL, NSURLRequest *, void(^)(NSData *, NSURLResponse *, NSError *));
static DataTaskWithReqFn _origDataTaskWithReq = NULL;

static NSURLSessionDataTask *_hookDataTaskWithReq(id self, SEL _cmd, NSURLRequest *req, void(^handler)(NSData *, NSURLResponse *, NSError *)) {
    NSURL *url = req.URL;
    NSString *method = req.HTTPMethod ?: @"GET";
    id handlerCopy = [handler copy];
    void(^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSInteger status = 0;
        if ([resp isKindOfClass:[NSHTTPURLResponse class]]) status = ((NSHTTPURLResponse *)resp).statusCode;
        NetEntry *e = [NetEntry new];
        e.url = url.absoluteString; e.method = method; e.statusCode = status; e.bodySize = data.length;
        e.preview = safePreview(data, 150);
        [[NetPanel shared] addEntry:e];
        if (handlerCopy) ((void(^)(NSData *, NSURLResponse *, NSError *))handlerCopy)(data, resp, err);
    };
    return _origDataTaskWithReq(self, _cmd, req, wrapped);
}

typedef NSURLSessionDataTask *(*DataTaskWithURLFn)(id, SEL, NSURL *, void(^)(NSData *, NSURLResponse *, NSError *));
static DataTaskWithURLFn _origDataTaskWithURL = NULL;

static NSURLSessionDataTask *_hookDataTaskWithURL(id self, SEL _cmd, NSURL *url, void(^handler)(NSData *, NSURLResponse *, NSError *)) {
    id handlerCopy = [handler copy];
    void(^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSInteger status = 0;
        if ([resp isKindOfClass:[NSHTTPURLResponse class]]) status = ((NSHTTPURLResponse *)resp).statusCode;
        NetEntry *e = [NetEntry new];
        e.url = url.absoluteString; e.method = @"GET"; e.statusCode = status; e.bodySize = data.length;
        e.preview = safePreview(data, 150);
        [[NetPanel shared] addEntry:e];
        if (handlerCopy) ((void(^)(NSData *, NSURLResponse *, NSError *))handlerCopy)(data, resp, err);
    };
    return _origDataTaskWithURL(self, _cmd, url, wrapped);
}

// ==================== 入口 ====================
__attribute__((constructor))
static void PDDSaverEntry(void) {
    @autoreleasepool {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SEL s1 = @selector(dataTaskWithRequest:completionHandler:);
            Method m1 = class_getInstanceMethod([NSURLSession class], s1);
            if (m1) { _origDataTaskWithReq = (DataTaskWithReqFn)method_getImplementation(m1); method_setImplementation(m1, (IMP)_hookDataTaskWithReq); }

            SEL s2 = @selector(dataTaskWithURL:completionHandler:);
            Method m2 = class_getInstanceMethod([NSURLSession class], s2);
            if (m2) { _origDataTaskWithURL = (DataTaskWithURLFn)method_getImplementation(m2); method_setImplementation(m2, (IMP)_hookDataTaskWithURL); }

            [[NetPanel shared] show];
            [FloatBall show];
            HHLog(@"📡 v4网络面板已启动 - 点右下浮球开关面板");
        });
    }
}
