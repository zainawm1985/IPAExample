//
//  PDDSaver.m  v5 - 完整网络抓包 (请求体 + 响应体全量显示)
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#define HHLog(fmt, ...) NSLog(@"[PDDNet] " fmt, ##__VA_ARGS__)

// ==================== 请求记录(完整存储) ====================
@interface NetEntry : NSObject
@property (nonatomic, copy) NSString *url;
@property (nonatomic, copy) NSString *method;
@property (nonatomic, assign) NSInteger statusCode;
@property (nonatomic, assign) NSInteger bodySize;
@property (nonatomic, copy) NSString *reqBody;    // POST载荷
@property (nonatomic, copy) NSString *respBody;   // 响应体全文
@property (nonatomic, copy) NSString *time;
@end
@implementation NetEntry
@end

// ==================== 详情弹窗 ====================
@interface DetailView : UIView <UITextViewDelegate>
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UISegmentedControl *seg;
@property (nonatomic, strong) NetEntry *entry;
@property (nonatomic, copy) void(^onClose)(void);

+ (void)showWithEntry:(NetEntry *)entry;
@end

@implementation DetailView

+ (void)showWithEntry:(NetEntry *)entry {
    DetailView *dv = [[DetailView alloc] initWithFrame:UIScreen.mainScreen.bounds entry:entry];
    UIWindow *kw = [UIApplication sharedApplication].keyWindow;
    if (!kw) kw = [UIApplication sharedApplication].windows.firstObject;
    [kw addSubview:dv];
}

- (instancetype)initWithFrame:(CGRect)f entry:(NetEntry *)entry {
    if (self = [super initWithFrame:f]) {
        self.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.97];
        self.entry = entry;
        
        // 避让刘海/状态栏
        CGFloat safeTop = 44;
        if (@available(iOS 11.0, *)) {
            UIWindow *kw = [UIApplication sharedApplication].keyWindow;
            if (!kw) kw = [UIApplication sharedApplication].windows.firstObject;
            safeTop = kw.safeAreaInsets.top > 0 ? kw.safeAreaInsets.top : 44;
        }
        
        _seg = [[UISegmentedControl alloc] initWithItems:@[@"响应", @"请求体", @"URL"]];
        _seg.selectedSegmentIndex = 0;
        _seg.frame = CGRectMake(12, safeTop + 50, f.size.width-24, 32);
        _seg.tintColor = [UIColor colorWithRed:0.3 green:0.7 blue:1 alpha:1];
        [_seg addTarget:self action:@selector(switchTab) forControlEvents:UIControlEventValueChanged];
        [self addSubview:_seg];
        
        CGFloat textTop = safeTop + 90;
        _textView = [[UITextView alloc] initWithFrame:CGRectMake(8, textTop, f.size.width-16, f.size.height - textTop - 60)];
        _textView.backgroundColor = [UIColor colorWithWhite:0.06 alpha:1];
        _textView.textColor = [UIColor colorWithWhite:0.9 alpha:1];
        _textView.font = [UIFont fontWithName:@"Menlo" size:11] ?: [UIFont systemFontOfSize:11];
        _textView.editable = NO;
        _textView.layer.cornerRadius = 6;
        _textView.layer.borderColor = [UIColor colorWithWhite:0.3 alpha:1].CGColor;
        _textView.layer.borderWidth = 0.5;
        [self addSubview:_textView];
        
        // 关闭按钮
        UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
        close.frame = CGRectMake(f.size.width - 60, safeTop + 5, 50, 40);
        [close setTitle:@"✕ 关闭" forState:UIControlStateNormal];
        [close setTitleColor:[UIColor colorWithRed:1 green:0.4 blue:0.4 alpha:1] forState:UIControlStateNormal];
        close.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        [close addTarget:self action:@selector(closeTap) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:close];
        
        // 复制按钮
        UIButton *copy = [UIButton buttonWithType:UIButtonTypeSystem];
        copy.frame = CGRectMake(12, safeTop + 5, 80, 40);
        [copy setTitle:@"📋复制" forState:UIControlStateNormal];
        [copy setTitleColor:[UIColor colorWithRed:0.3 green:0.7 blue:1 alpha:1] forState:UIControlStateNormal];
        copy.titleLabel.font = [UIFont boldSystemFontOfSize:13];
        [copy addTarget:self action:@selector(copyTap) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:copy];
        
        // 请求摘要
        UILabel *summary = [[UILabel alloc] initWithFrame:CGRectMake(90, safeTop + 6, f.size.width-160, 38)];
        summary.text = [NSString stringWithFormat:@"%@@%ld  %ldB", entry.method, (long)entry.statusCode, (long)entry.bodySize];
        summary.textColor = [UIColor colorWithWhite:0.6 alpha:1];
        summary.font = [UIFont systemFontOfSize:11];
        summary.numberOfLines = 2;
        [self addSubview:summary];
        
        [self switchTab]; // 初始显示响应
    }
    return self;
}

- (void)switchTab {
    switch (_seg.selectedSegmentIndex) {
        case 0: _textView.text = self.entry.respBody ?: @"(无响应体)"; break;
        case 1: _textView.text = self.entry.reqBody ?: @"(无请求体/GDET请求)"; break;
        case 2: {
            NSMutableString *s = [NSMutableString string];
            [s appendFormat:@"Method: %@\n", self.entry.method];
            [s appendFormat:@"Status: %ld\n", (long)self.entry.statusCode];
            [s appendFormat:@"Size: %ld bytes\n", (long)self.entry.bodySize];
            [s appendFormat:@"Time: %@\n\n", self.entry.time ?: @"?"];
            [s appendString:self.entry.url];
            _textView.text = s;
            break;
        }
    }
}

- (void)closeTap { [self removeFromSuperview]; }
- (void)copyTap { [UIPasteboard generalPasteboard].string = _textView.text;
    // 简单确认
    UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(0,0,10,10)];
    dot.backgroundColor = UIColor.greenColor; dot.layer.cornerRadius = 5; dot.center = CGPointMake(40,30);
    dot.alpha = 1; [self addSubview:dot];
    [UIView animateWithDuration:0.8 animations:^{ dot.alpha=0; } completion:^(BOOL f){ [dot removeFromSuperview]; }];
}

@end

// ==================== 网络面板 ====================
@interface NetPanel : UIView <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray<NetEntry *> *entries;
@property (nonatomic, strong) UILabel *countLabel;
+ (instancetype)shared;
- (void)show;
- (void)hide;
- (void)toggle;
- (void)addEntry:(NetEntry *)entry;
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
    if (self = [super initWithFrame:CGRectMake(0, h - 320, w, 320)]) {
        self.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.95];
        self.layer.cornerRadius = 12;
        self.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
        self.entries = [NSMutableArray array];
        
        UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0,0,w,40)];
        header.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1];
        UIButton *fold = [UIButton buttonWithType:UIButtonTypeSystem];
        fold.frame = CGRectMake(8,4,36,32); [fold setTitle:@"❮" forState:UIControlStateNormal];
        fold.titleLabel.font = [UIFont boldSystemFontOfSize:12];
        fold.tintColor = [UIColor colorWithRed:0.3 green:0.7 blue:1 alpha:1];
        [fold addTarget:self action:@selector(foldTap) forControlEvents:UIControlEventTouchUpInside];
        [header addSubview:fold];
        
        UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(50,0,60,40)];
        t.text=@"📡 网络"; t.textColor=UIColor.whiteColor; t.font=[UIFont boldSystemFontOfSize:13];
        [header addSubview:t];
        
        _countLabel = [[UILabel alloc] initWithFrame:CGRectMake(105,0,80,40)];
        _countLabel.text=@"0条"; _countLabel.textColor=[UIColor colorWithRed:0.3 green:0.7 blue:1 alpha:1];
        _countLabel.font=[UIFont systemFontOfSize:12]; [header addSubview:_countLabel];
        
        UIButton *clr = [UIButton buttonWithType:UIButtonTypeSystem];
        clr.frame=CGRectMake(w-80,4,36,32); [clr setTitle:@"🗑" forState:UIControlStateNormal];
        [clr addTarget:self action:@selector(clearTap) forControlEvents:UIControlEventTouchUpInside];
        [header addSubview:clr];
        
        UIButton *cpy = [UIButton buttonWithType:UIButtonTypeSystem];
        cpy.frame=CGRectMake(w-45,4,36,32); [cpy setTitle:@"📋" forState:UIControlStateNormal];
        [cpy addTarget:self action:@selector(copyTap) forControlEvents:UIControlEventTouchUpInside];
        [header addSubview:cpy];
        [self addSubview:header];
        
        _tableView = [[UITableView alloc] initWithFrame:CGRectMake(0,44,w,276) style:UITableViewStylePlain];
        _tableView.backgroundColor=UIColor.clearColor;
        _tableView.separatorColor=[UIColor colorWithWhite:0.25 alpha:1];
        _tableView.dataSource=self; _tableView.delegate=self;
        _tableView.rowHeight=36;
        [_tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"c"];
        [self addSubview:_tableView];
        
        UIView *handle=[[UIView alloc]initWithFrame:CGRectMake(w/2-18,6,36,4)];
        handle.backgroundColor=[UIColor colorWithWhite:0.4 alpha:1]; handle.layer.cornerRadius=2;
        [self addSubview:handle];
        UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(pan:)];
        [header addGestureRecognizer:pan];
        
        self.hidden=YES;
    }
    return self;
}

- (void)show {
    if(!self.superview){UIWindow*kw=[UIApplication sharedApplication].keyWindow;if(!kw)kw=[UIApplication sharedApplication].windows.firstObject;[kw addSubview:self];}
    self.hidden=NO;[self.superview bringSubviewToFront:self];
}
- (void)hide{self.hidden=YES;}
- (void)toggle{if(self.hidden)[self show];else[self hide];}
- (void)foldTap{CGRect f=self.frame;f.origin.y=self.superview.bounds.size.height-40;[UIView animateWithDuration:0.25 animations:^{self.frame=f;}];}

- (void)pan:(UIPanGestureRecognizer*)g{
    CGPoint t=[g translationInView:self.superview];
    self.frame=CGRectMake(0,MAX(60,self.frame.origin.y+t.y),self.superview.bounds.size.width,320);
    [g setTranslation:CGPointZero inView:self.superview];
    if(g.state==UIGestureRecognizerStateEnded){
        CGFloat sh=self.superview.bounds.size.height;
        CGFloat tg=self.frame.origin.y<sh-180?60:sh-320;
        [UIView animateWithDuration:0.2 animations:^{self.frame=CGRectMake(0,tg,self.superview.bounds.size.width,320);}];
    }
}

- (void)addEntry:(NetEntry*)e{
    dispatch_async(dispatch_get_main_queue(),^{
        [self.entries insertObject:e atIndex:0];
        if(self.entries.count>200)[self.entries removeLastObject];
        self.countLabel.text=[NSString stringWithFormat:@"%lu条",(unsigned long)self.entries.count];
        HHLog(@"[%@@%ld %ldB] %@",e.method,(long)e.statusCode,(long)e.bodySize,e.url);
        if(e.reqBody.length)HHLog(@"  ↳ 请求体: %@",[e.reqBody substringToIndex:MIN(e.reqBody.length,200)]);
        if(e.respBody.length)HHLog(@"  ↳ 响应体: %@",[e.respBody substringToIndex:MIN(e.respBody.length,200)]);
        [self.tableView reloadData];
    });
}

- (void)clearTap{[self.entries removeAllObjects];self.countLabel.text=@"0条";[self.tableView reloadData];}
- (void)copyTap{
    NSMutableString*s=[NSMutableString string];
    for(NetEntry*e in self.entries)[s appendFormat:@"[%@@%ld %ldB] %@\n",e.method,(long)e.statusCode,(long)e.bodySize,e.url];
    [UIPasteboard generalPasteboard].string=s;
}

- (NSInteger)tableView:(UITableView*)tv numberOfRowsInSection:(NSInteger)s{return self.entries.count;}

- (UITableViewCell*)tableView:(UITableView*)tv cellForRowAtIndexPath:(NSIndexPath*)ip{
    UITableViewCell*c=[tv dequeueReusableCellWithIdentifier:@"c"];
    NetEntry*e=self.entries[ip.row];
    UIColor *sc;NSString*st;
    if(e.statusCode==0){sc=UIColor.grayColor;st=@"···";}
    else if(e.statusCode<300){sc=UIColor.greenColor;st=[NSString stringWithFormat:@"%ld",(long)e.statusCode];}
    else if(e.statusCode<400){sc=UIColor.yellowColor;st=[NSString stringWithFormat:@"%ld",(long)e.statusCode];}
    else{sc=UIColor.redColor;st=[NSString stringWithFormat:@"%ld",(long)e.statusCode];}
    UIColor *mc;if([e.method isEqualToString:@"GET"])mc=[UIColor colorWithRed:0.2 green:0.7 blue:0.3 alpha:1];
    else if([e.method isEqualToString:@"POST"])mc=[UIColor colorWithRed:0.9 green:0.6 blue:0.1 alpha:1];
    else if([e.method isEqualToString:@"PUT"])mc=[UIColor colorWithRed:0.3 green:0.5 blue:0.9 alpha:1];
    else mc=UIColor.grayColor;
    
    // 有载荷/响应体的请求加星标
    NSString*star=e.reqBody.length>10||e.respBody.length>100?@"★ ":@"";
    
    NSString*su=e.url;if(su.length>50)su=[[su substringToIndex:47]stringByAppendingString:@"..."];
    NSString*sz=e.bodySize>1024?[NSString stringWithFormat:@"%.1fK",e.bodySize/1024.0]:[NSString stringWithFormat:@"%ldB",(long)e.bodySize];
    
    NSMutableAttributedString*as=[[NSMutableAttributedString alloc]init];
    [as appendAttributedString:[[NSAttributedString alloc]initWithString:star attributes:@{NSForegroundColorAttributeName:[UIColor colorWithRed:1 green:0.8 blue:0.2 alpha:1],NSFontAttributeName:[UIFont boldSystemFontOfSize:10]}]];
    [as appendAttributedString:[[NSAttributedString alloc]initWithString:e.method attributes:@{NSForegroundColorAttributeName:mc,NSFontAttributeName:[UIFont boldSystemFontOfSize:11]}]];
    [as appendAttributedString:[[NSAttributedString alloc]initWithString:@"  " attributes:nil]];
    [as appendAttributedString:[[NSAttributedString alloc]initWithString:st attributes:@{NSForegroundColorAttributeName:sc,NSFontAttributeName:[UIFont boldSystemFontOfSize:11]}]];
    [as appendAttributedString:[[NSAttributedString alloc]initWithString:@"  " attributes:nil]];
    [as appendAttributedString:[[NSAttributedString alloc]initWithString:su attributes:@{NSForegroundColorAttributeName:[UIColor colorWithWhite:0.85 alpha:1],NSFontAttributeName:[UIFont systemFontOfSize:11]}]];
    [as appendAttributedString:[[NSAttributedString alloc]initWithString:[NSString stringWithFormat:@"  %@",sz] attributes:@{NSForegroundColorAttributeName:[UIColor colorWithWhite:0.5 alpha:1],NSFontAttributeName:[UIFont systemFontOfSize:10]}]];
    c.textLabel.attributedText=as;c.textLabel.numberOfLines=1;
    c.backgroundColor=ip.row%2==0?[UIColor colorWithWhite:0.14 alpha:1]:[UIColor colorWithWhite:0.1 alpha:1];
    return c;
}

- (void)tableView:(UITableView*)tv didSelectRowAtIndexPath:(NSIndexPath*)ip{
    [tv deselectRowAtIndexPath:ip animated:YES];
    [DetailView showWithEntry:self.entries[ip.row]];
}

@end

// ==================== 浮球 ====================
@interface FloatBall : UIButton @end
@implementation FloatBall { CGPoint _s; }
+ (void)show {
    dispatch_async(dispatch_get_main_queue(),^{
        FloatBall*b=[[FloatBall alloc] initWithFrame:CGRectMake(UIScreen.mainScreen.bounds.size.width-56,200,48,48)];
        b.backgroundColor=[[UIColor colorWithRed:0.2 green:0.5 blue:0.9 alpha:1] colorWithAlphaComponent:0.85];
        b.layer.cornerRadius=24;b.layer.borderColor=UIColor.whiteColor.CGColor;b.layer.borderWidth=1.5;
        UILabel*icon=[[UILabel alloc]initWithFrame:CGRectMake(0,2,48,44)];
        icon.text=@"📡";icon.font=[UIFont systemFontOfSize:18];icon.textAlignment=NSTextAlignmentCenter;
        [b addSubview:icon];
        [b addTarget:b action:@selector(tap) forControlEvents:UIControlEventTouchUpInside];
        UIPanGestureRecognizer*pan=[[UIPanGestureRecognizer alloc]initWithTarget:b action:@selector(drag:)];
        [b addGestureRecognizer:pan];
        UIWindow*kw=[UIApplication sharedApplication].keyWindow;
        if(!kw)kw=[UIApplication sharedApplication].windows.firstObject;[kw addSubview:b];
    });
}
- (void)tap{[[NetPanel shared] toggle];}
- (void)drag:(UIPanGestureRecognizer*)g{
    if(g.state==UIGestureRecognizerStateBegan)_s=g.view.center;
    CGPoint t=[g translationInView:g.view.superview];
    g.view.center=CGPointMake(_s.x+t.x,_s.y+t.y);
    if(g.state==UIGestureRecognizerStateEnded){CGFloat x=g.view.center.x,w=g.view.superview.bounds.size.width;
        [UIView animateWithDuration:0.2 animations:^{g.view.center=CGPointMake(x<w/2?34:w-34,g.view.center.y);}];}
}
@end

// ==================== NSURLSession Hook ====================

static NSString *fmtBody(NSData *d) {
    if(!d||d.length==0)return nil;
    NSString *s=[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    if(!s)s=[[NSString alloc] initWithData:d encoding:NSASCIIStringEncoding];
    if(!s){
        // 尝试pretty-print非文本
        if(d.length>4096)return [NSString stringWithFormat:@"(binary %luB)",(unsigned long)d.length];
        NSMutableString*hex=[NSMutableString string];
        for(NSUInteger i=0;i<MIN(d.length,256);i+=16){
            for(NSUInteger j=i;j<MIN(i+16,d.length);j++)
                [hex appendFormat:@"%02x ",((uint8_t*)d.bytes)[j]];
            [hex appendString:@"\n"];
        }
        return hex;
    }
    return s;
}

typedef NSURLSessionDataTask *(*DataTaskWithReqFn)(id,SEL,NSURLRequest*,void(^)(NSData*,NSURLResponse*,NSError*));
static DataTaskWithReqFn _origDTWR = NULL;

static NSURLSessionDataTask *_hookDTWR(id self,SEL _cmd,NSURLRequest *req,void(^h)(NSData*,NSURLResponse*,NSError*)) {
    NSURL *url=req.URL;
    NSString *method=req.HTTPMethod?:@"GET";
    NSString *reqBody=fmtBody(req.HTTPBody);
    id hc=[h copy];
    void(^w)(NSData*,NSURLResponse*,NSError*)=^(NSData*d,NSURLResponse*r,NSError*e){
        NSInteger st=0;if([r isKindOfClass:[NSHTTPURLResponse class]])st=((NSHTTPURLResponse*)r).statusCode;
        NetEntry*en=[NetEntry new];
        en.url=url.absoluteString; en.method=method; en.statusCode=st; en.bodySize=d.length;
        en.reqBody=reqBody; en.respBody=fmtBody(d);
        [[NetPanel shared] addEntry:en];
        if(hc)((void(^)(NSData*,NSURLResponse*,NSError*))hc)(d,r,e);
    };
    return _origDTWR(self,_cmd,req,w);
}

typedef NSURLSessionDataTask *(*DataTaskWithURLFn)(id,SEL,NSURL*,void(^)(NSData*,NSURLResponse*,NSError*));
static DataTaskWithURLFn _origDTWU = NULL;

static NSURLSessionDataTask *_hookDTWU(id self,SEL _cmd,NSURL *url,void(^h)(NSData*,NSURLResponse*,NSError*)) {
    id hc=[h copy];
    void(^w)(NSData*,NSURLResponse*,NSError*)=^(NSData*d,NSURLResponse*r,NSError*e){
        NSInteger st=0;if([r isKindOfClass:[NSHTTPURLResponse class]])st=((NSHTTPURLResponse*)r).statusCode;
        NetEntry*en=[NetEntry new];
        en.url=url.absoluteString; en.method=@"GET"; en.statusCode=st; en.bodySize=d.length;
        en.respBody=fmtBody(d);
        [[NetPanel shared] addEntry:en];
        if(hc)((void(^)(NSData*,NSURLResponse*,NSError*))hc)(d,r,e);
    };
    return _origDTWU(self,_cmd,url,w);
}

// ==================== 入口 ====================
__attribute__((constructor))
static void PDDSaverEntry(void) {
    @autoreleasepool {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.3*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
            SEL s1=@selector(dataTaskWithRequest:completionHandler:);
            Method m1=class_getInstanceMethod([NSURLSession class],s1);
            if(m1){_origDTWR=(DataTaskWithReqFn)method_getImplementation(m1);method_setImplementation(m1,(IMP)_hookDTWR);}
            SEL s2=@selector(dataTaskWithURL:completionHandler:);
            Method m2=class_getInstanceMethod([NSURLSession class],s2);
            if(m2){_origDTWU=(DataTaskWithURLFn)method_getImplementation(m2);method_setImplementation(m2,(IMP)_hookDTWU);}
            [[NetPanel shared] show];
            [FloatBall show];
            HHLog(@"📡 v5 完整抓包已启动 - 可查看请求体+响应体");
        });
    }
}
