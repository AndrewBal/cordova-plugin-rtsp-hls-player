//
//  HlsPlayerViewController.m
//  Native AVPlayer-based HLS player
//

#import "HlsPlayerViewController.h"

@interface HlsPlayerViewController ()

@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerLayer *playerLayer;

@property (nonatomic, strong) UIView *videoContainer;
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *errorLabel;

@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UIButton *backButton;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIView *recordingIndicator;
@property (nonatomic, strong) UIView *recordingDot;
@property (nonatomic, strong) UIButton *cameraSwitchButton;

@property (nonatomic, strong) UIView *bottomControls;
@property (nonatomic, strong) UIButton *photoButton;
@property (nonatomic, strong) UIButton *recordButton;
@property (nonatomic, strong) UIButton *fullscreenButton;

@property (nonatomic, assign) BOOL isRecording;
@property (nonatomic, assign) BOOL isRecordingInProgress;
@property (nonatomic, assign) BOOL isPlaying;
@property (nonatomic, strong) NSTimer *blinkTimer;

// Orientation state
@property (nonatomic, assign) BOOL isLandscape;
@property (nonatomic, assign) UIInterfaceOrientation currentOrientation;

@end

@implementation HlsPlayerViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor blackColor];
    
    if (!self.currentCamera) self.currentCamera = @"front";
    if (!self.apiBaseUrl) self.apiBaseUrl = @"http://192.168.0.1";
    
    self.isLandscape = NO;
    self.currentOrientation = UIInterfaceOrientationPortrait;
    
    NSLog(@"[HLSPlayer] viewDidLoad - hlsUrl: %@", self.hlsUrl);
    
    [self setupUI];
    [self setupAudioSession];
    [self startPlayback];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.playerLayer.frame = self.videoContainer.bounds;
    
    CGFloat topInset = 0, bottomInset = 0;
    if (@available(iOS 11.0, *)) {
        topInset = self.view.safeAreaInsets.top;
        bottomInset = self.view.safeAreaInsets.bottom;
    }
    
    self.topBar.frame = CGRectMake(0, topInset, self.view.bounds.size.width, 100);
    self.bottomControls.frame = CGRectMake(0, self.view.bounds.size.height - 160 - bottomInset,
                                           self.view.bounds.size.width, 160);
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self cleanup];
}

- (void)dealloc {
    [self cleanup];
}

- (void)cleanup {
    [self.blinkTimer invalidate];
    self.blinkTimer = nil;
    
    @try {
        [self.player.currentItem removeObserver:self forKeyPath:@"status"];
        [self.player.currentItem removeObserver:self forKeyPath:@"playbackBufferEmpty"];
        [self.player.currentItem removeObserver:self forKeyPath:@"playbackLikelyToKeepUp"];
    } @catch (NSException *e) {}
    
    [self.player pause];
    self.player = nil;
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)prefersStatusBarHidden { return YES; }

- (UIInterfaceOrientationMask)supportedInterfaceOrientations { 
    // Return current orientation mask based on state
    if (self.isLandscape) {
        return UIInterfaceOrientationMaskLandscape;
    } else {
        return UIInterfaceOrientationMaskPortrait;
    }
}

- (BOOL)shouldAutorotate {
    return YES; // Allow rotation when orientation mask changes
}

#pragma mark - Audio

- (void)setupAudioSession {
    NSError *error = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeMoviePlayback options:0 error:&error];
    [session setActive:YES error:&error];
}

#pragma mark - UI

- (void)setupUI {
    self.videoContainer = [[UIView alloc] initWithFrame:self.view.bounds];
    self.videoContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.videoContainer.backgroundColor = [UIColor blackColor];
    [self.view addSubview:self.videoContainer];
    
    if (@available(iOS 13.0, *)) {
        self.loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
        self.loadingIndicator.color = [UIColor whiteColor];
    } else {
        self.loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    }
    self.loadingIndicator.center = self.view.center;
    self.loadingIndicator.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin |
                                             UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [self.view addSubview:self.loadingIndicator];
    [self.loadingIndicator startAnimating];
    
    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 280, 60)];
    self.statusLabel.center = CGPointMake(self.view.center.x, self.view.center.y + 50);
    self.statusLabel.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin |
                                        UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    self.statusLabel.textColor = [UIColor lightGrayColor];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.font = [UIFont systemFontOfSize:14];
    self.statusLabel.numberOfLines = 2;
    self.statusLabel.text = @"Loading stream...";
    [self.view addSubview:self.statusLabel];
    
    self.errorLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 0, self.view.bounds.size.width - 40, 180)];
    self.errorLabel.center = self.view.center;
    self.errorLabel.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleWidth;
    self.errorLabel.textColor = [UIColor whiteColor];
    self.errorLabel.textAlignment = NSTextAlignmentCenter;
    self.errorLabel.numberOfLines = 0;
    self.errorLabel.font = [UIFont systemFontOfSize:16];
    self.errorLabel.hidden = YES;
    [self.view addSubview:self.errorLabel];
    
    [self setupTopBar];
    [self setupBottomControls];
}

- (void)setupTopBar {
    self.topBar = [[UIView alloc] initWithFrame:CGRectMake(0, 50, self.view.bounds.size.width, 100)];
    self.topBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:self.topBar];
    
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.frame = CGRectMake(0, -50, self.view.bounds.size.width * 2, 150);
    gradient.colors = @[(id)[UIColor colorWithWhite:0 alpha:0.8].CGColor, (id)[UIColor clearColor].CGColor];
    [self.topBar.layer insertSublayer:gradient atIndex:0];
    
    // Close button with SVG icon
    self.backButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.backButton.frame = CGRectMake(16, 0, 44, 44);
    [self setCloseIconForButton:self.backButton];
    [self.backButton addTarget:self action:@selector(backTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.backButton];
    
    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(60, 0, self.view.bounds.size.width - 120, 44)];
    self.titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.titleLabel.text = self.titleText ?: @"Live Stream";
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.topBar addSubview:self.titleLabel];
    
    self.recordingIndicator = [[UIView alloc] initWithFrame:CGRectMake(self.view.bounds.size.width - 80, 10, 70, 24)];
    self.recordingIndicator.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    self.recordingIndicator.hidden = YES;
    [self.topBar addSubview:self.recordingIndicator];
    
    self.recordingDot = [[UIView alloc] initWithFrame:CGRectMake(0, 6, 12, 12)];
    self.recordingDot.backgroundColor = [UIColor redColor];
    self.recordingDot.layer.cornerRadius = 6;
    [self.recordingIndicator addSubview:self.recordingDot];
    
    UILabel *recLabel = [[UILabel alloc] initWithFrame:CGRectMake(18, 0, 50, 24)];
    recLabel.text = @"REC";
    recLabel.textColor = [UIColor redColor];
    recLabel.font = [UIFont boldSystemFontOfSize:14];
    [self.recordingIndicator addSubview:recLabel];
    
    if (self.rearRtspUrl && self.rearRtspUrl.length > 0) {
        self.cameraSwitchButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.cameraSwitchButton.frame = CGRectMake(16, 50, 100, 36);
        [self.cameraSwitchButton setTitle:@"⟳ Front" forState:UIControlStateNormal];
        self.cameraSwitchButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        self.cameraSwitchButton.tintColor = [UIColor whiteColor];
        self.cameraSwitchButton.backgroundColor = [UIColor colorWithWhite:1 alpha:0.2];
        self.cameraSwitchButton.layer.cornerRadius = 18;
        [self.cameraSwitchButton addTarget:self action:@selector(switchCamera) forControlEvents:UIControlEventTouchUpInside];
        [self.topBar addSubview:self.cameraSwitchButton];
    }
}

- (void)setupBottomControls {
    self.bottomControls = [[UIView alloc] initWithFrame:CGRectMake(0, self.view.bounds.size.height - 160,
                                                                    self.view.bounds.size.width, 160)];
    self.bottomControls.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:self.bottomControls];
    
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.frame = CGRectMake(0, 0, self.view.bounds.size.width * 2, 160);
    gradient.colors = @[(id)[UIColor clearColor].CGColor, (id)[UIColor colorWithWhite:0 alpha:0.8].CGColor];
    [self.bottomControls.layer insertSublayer:gradient atIndex:0];
    
    CGFloat centerX = self.view.bounds.size.width / 2;
    CGFloat buttonSize = 60;
    CGFloat spacing = 90;
    
    // Photo button with SVG icon
    self.photoButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.photoButton.frame = CGRectMake(centerX - spacing - buttonSize/2, 40, buttonSize, buttonSize);
    self.photoButton.backgroundColor = [UIColor whiteColor];
    self.photoButton.layer.cornerRadius = buttonSize / 2;
    [self setPhotoIconForButton:self.photoButton];
    [self.photoButton addTarget:self action:@selector(takePhoto) forControlEvents:UIControlEventTouchUpInside];
    [self.bottomControls addSubview:self.photoButton];
    
    // Record button with SVG icon
    self.recordButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.recordButton.frame = CGRectMake(centerX - buttonSize/2, 40, buttonSize, buttonSize);
    self.recordButton.backgroundColor = [UIColor whiteColor];
    self.recordButton.layer.cornerRadius = buttonSize / 2;
    [self setRecordIconForButton:self.recordButton];
    [self.recordButton addTarget:self action:@selector(toggleRecording) forControlEvents:UIControlEventTouchUpInside];
    [self.bottomControls addSubview:self.recordButton];
    
    // Fullscreen/Rotation button with SVG icon
    self.fullscreenButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.fullscreenButton.frame = CGRectMake(centerX + spacing - buttonSize/2, 40, buttonSize, buttonSize);
    self.fullscreenButton.backgroundColor = [UIColor whiteColor];
    self.fullscreenButton.layer.cornerRadius = buttonSize / 2;
    [self setRotationIconForButton:self.fullscreenButton];
    [self.fullscreenButton addTarget:self action:@selector(toggleOrientation) forControlEvents:UIControlEventTouchUpInside];
    [self.bottomControls addSubview:self.fullscreenButton];
}

#pragma mark - SVG Icons

- (void)setCloseIconForButton:(UIButton *)button {
    // Close icon from ic_close.xml
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(34.9, 27)];
    [path addLineToPoint:CGPointMake(52.4, 9.5)];
    [path addCurveToPoint:CGPointMake(52.4, 1.7) controlPoint1:CGPointMake(54.6, 7.3) controlPoint2:CGPointMake(54.6, 3.9)];
    [path addCurveToPoint:CGPointMake(44.6, 1.7) controlPoint1:CGPointMake(50.2, -0.5) controlPoint2:CGPointMake(46.8, -0.5)];
    [path addLineToPoint:CGPointMake(27.1, 19.2)];
    [path addLineToPoint:CGPointMake(9.4, 1.6)];
    [path addCurveToPoint:CGPointMake(1.6, 1.6) controlPoint1:CGPointMake(7.2, -0.6) controlPoint2:CGPointMake(3.8, -0.6)];
    [path addCurveToPoint:CGPointMake(1.6, 9.4) controlPoint1:CGPointMake(-0.6, 3.8) controlPoint2:CGPointMake(-0.5, 7.1)];
    [path addLineToPoint:CGPointMake(19.3, 27)];
    [path addLineToPoint:CGPointMake(1.8, 44.5)];
    [path addCurveToPoint:CGPointMake(1.8, 52.3) controlPoint1:CGPointMake(-0.4, 46.7) controlPoint2:CGPointMake(-0.4, 50.1)];
    [path addCurveToPoint:CGPointMake(5.7, 54) controlPoint1:CGPointMake(2.8, 53.5) controlPoint2:CGPointMake(4.3, 54)];
    [path addCurveToPoint:CGPointMake(9.6, 52.4) controlPoint1:CGPointMake(7.1, 54) controlPoint2:CGPointMake(8.5, 53.5)];
    [path addLineToPoint:CGPointMake(27.1, 34.9)];
    [path addLineToPoint:CGPointMake(44.6, 52.4)];
    [path addCurveToPoint:CGPointMake(48.5, 54) controlPoint1:CGPointMake(45.7, 53.5) controlPoint2:CGPointMake(47, 54)];
    [path addCurveToPoint:CGPointMake(52.4, 52.4) controlPoint1:CGPointMake(49.9, 54) controlPoint2:CGPointMake(51.3, 53.5)];
    [path addCurveToPoint:CGPointMake(52.4, 44.6) controlPoint1:CGPointMake(54.6, 50.2) controlPoint2:CGPointMake(54.6, 46.8)];
    [path addLineToPoint:CGPointMake(34.9, 27)];
    [path closePath];
    
    CAShapeLayer *shapeLayer = [CAShapeLayer layer];
    shapeLayer.path = path.CGPath;
    shapeLayer.fillColor = [UIColor whiteColor].CGColor;
    
    CGFloat scale = 24.0 / 64.0;
    CGAffineTransform transform = CGAffineTransformMakeScale(scale, scale);
    shapeLayer.path = CGPathCreateCopyByTransformingPath(path.CGPath, &transform);
    shapeLayer.frame = CGRectMake(10, 10, 24, 24);
    
    [button.layer addSublayer:shapeLayer];
}

- (void)setPhotoIconForButton:(UIButton *)button {
    // Photo icon from ic_photo.xml
    UIBezierPath *path = [UIBezierPath bezierPath];
    
    // Main camera body
    [path moveToPoint:CGPointMake(26.9, 48.6)];
    [path addLineToPoint:CGPointMake(5.5, 48.6)];
    [path addCurveToPoint:CGPointMake(0.7, 45.9) controlPoint1:CGPointMake(3.4, 48.6) controlPoint2:CGPointMake(1.6, 47.7)];
    [path addCurveToPoint:CGPointMake(0, 43.2) controlPoint1:CGPointMake(0.3, 45.1) controlPoint2:CGPointMake(0, 44.2)];
    [path addCurveToPoint:CGPointMake(0, 18.9) controlPoint1:CGPointMake(0, 35.1) controlPoint2:CGPointMake(0, 27)];
    [path addCurveToPoint:CGPointMake(5.3, 13.5) controlPoint1:CGPointMake(0, 15.8) controlPoint2:CGPointMake(2.2, 13.5)];
    [path addLineToPoint:CGPointMake(10.9, 13.5)];
    [path addCurveToPoint:CGPointMake(14.2, 11.1) controlPoint1:CGPointMake(12.8, 13.5) controlPoint2:CGPointMake(13.4, 13.1)];
    [path addLineToPoint:CGPointMake(15.5, 7.1)];
    [path addCurveToPoint:CGPointMake(18, 5.4) controlPoint1:CGPointMake(16, 5.9) controlPoint2:CGPointMake(16.8, 5.4)];
    [path addLineToPoint:CGPointMake(35.9, 5.4)];
    [path addCurveToPoint:CGPointMake(38.4, 7.2) controlPoint1:CGPointMake(37.2, 5.4) controlPoint2:CGPointMake(38, 6)];
    [path addLineToPoint:CGPointMake(39.8, 11.5)];
    [path addCurveToPoint:CGPointMake(42.6, 13.5) controlPoint1:CGPointMake(40.3, 13) controlPoint2:CGPointMake(41.4, 13.5)];
    [path addLineToPoint:CGPointMake(48.2, 13.5)];
    [path addCurveToPoint:CGPointMake(54, 19.2) controlPoint1:CGPointMake(51.6, 13.4) controlPoint2:CGPointMake(53.8, 16.5)];
    [path addCurveToPoint:CGPointMake(54, 43.2) controlPoint1:CGPointMake(53.9, 27.2) controlPoint2:CGPointMake(53.9, 35.2)];
    [path addCurveToPoint:CGPointMake(48.5, 48.7) controlPoint1:CGPointMake(54, 45.9) controlPoint2:CGPointMake(51.2, 48.7)];
    [path addLineToPoint:CGPointMake(26.9, 48.6)];
    [path closePath];
    
    // Lens circle
    [path moveToPoint:CGPointMake(27, 16.2)];
    [path addCurveToPoint:CGPointMake(13.4, 29.7) controlPoint1:CGPointMake(19.5, 16.2) controlPoint2:CGPointMake(13.4, 22.2)];
    [path addCurveToPoint:CGPointMake(26.9, 43.3) controlPoint1:CGPointMake(13.4, 37.2) controlPoint2:CGPointMake(19.4, 43.3)];
    [path addCurveToPoint:CGPointMake(40.5, 29.8) controlPoint1:CGPointMake(34.4, 43.3) controlPoint2:CGPointMake(40.5, 37.3)];
    [path addCurveToPoint:CGPointMake(27, 16.2) controlPoint1:CGPointMake(40.5, 22.3) controlPoint2:CGPointMake(34.5, 16.2)];
    [path closePath];
    
    // Inner lens
    [path moveToPoint:CGPointMake(27, 37.8)];
    [path addCurveToPoint:CGPointMake(18.9, 29.7) controlPoint1:CGPointMake(22.5, 37.8) controlPoint2:CGPointMake(18.9, 34.2)];
    [path addCurveToPoint:CGPointMake(27, 21.6) controlPoint1:CGPointMake(18.9, 25.2) controlPoint2:CGPointMake(22.5, 21.6)];
    [path addCurveToPoint:CGPointMake(35.1, 29.7) controlPoint1:CGPointMake(31.5, 21.6) controlPoint2:CGPointMake(35.1, 25.2)];
    [path addCurveToPoint:CGPointMake(27, 37.8) controlPoint1:CGPointMake(35.1, 34.2) controlPoint2:CGPointMake(31.5, 37.8)];
    [path closePath];
    
    CAShapeLayer *shapeLayer = [CAShapeLayer layer];
    shapeLayer.path = path.CGPath;
    shapeLayer.fillColor = [UIColor blackColor].CGColor;
    
    CGFloat scale = 30.0 / 54.0;
    CGAffineTransform transform = CGAffineTransformMakeScale(scale, scale);
    shapeLayer.path = CGPathCreateCopyByTransformingPath(path.CGPath, &transform);
    shapeLayer.frame = CGRectMake(15, 15, 30, 30);
    
    [button.layer addSublayer:shapeLayer];
}

- (void)setRecordIconForButton:(UIButton *)button {
    // Record icon from ic_record.xml
    UIBezierPath *path = [UIBezierPath bezierPath];
    
    // Video camera body
    [path moveToPoint:CGPointMake(42.7, 31.2)];
    [path addCurveToPoint:CGPointMake(49.5, 25.3) controlPoint1:CGPointMake(45.3, 28.8) controlPoint2:CGPointMake(47.2, 26.9)];
    [path addCurveToPoint:CGPointMake(52.9, 24.5) controlPoint1:CGPointMake(50.4, 24.7) controlPoint2:CGPointMake(51.9, 24.4)];
    [path addCurveToPoint:CGPointMake(53.9, 27.2) controlPoint1:CGPointMake(53.4, 24.6) controlPoint2:CGPointMake(53.9, 25.9)];
    [path addCurveToPoint:CGPointMake(53.9, 46.5) controlPoint1:CGPointMake(54, 33.6) controlPoint2:CGPointMake(54, 40.1)];
    [path addCurveToPoint:CGPointMake(52.4, 49.6) controlPoint1:CGPointMake(53.9, 47.6) controlPoint2:CGPointMake(53.1, 49.4)];
    [path addCurveToPoint:CGPointMake(48.8, 48.7) controlPoint1:CGPointMake(51.4, 49.9) controlPoint2:CGPointMake(50.4, 49.5)];
    [path addLineToPoint:CGPointMake(42.7, 42.6)];
    [path addLineToPoint:CGPointMake(42.7, 46.6)];
    [path addCurveToPoint:CGPointMake(37.3, 52) controlPoint1:CGPointMake(42.6, 50.6) controlPoint2:CGPointMake(40.0, 52)];
    [path addLineToPoint:CGPointMake(10.6, 52)];
    [path addLineToPoint:CGPointMake(4.7, 52)];
    [path addCurveToPoint:CGPointMake(0.1, 47.2) controlPoint1:CGPointMake(1.4, 51.9) controlPoint2:CGPointMake(0.0, 50.3)];
    [path addCurveToPoint:CGPointMake(0.1, 27) controlPoint1:CGPointMake(0, 40.4) controlPoint2:CGPointMake(0.1, 33.8)];
    [path addCurveToPoint:CGPointMake(4.4, 22.1) controlPoint1:CGPointMake(0.1, 23.9) controlPoint2:CGPointMake(1.3, 22.1)];
    [path addLineToPoint:CGPointMake(38.6, 22.1)];
    [path addCurveToPoint:CGPointMake(42.8, 26.5) controlPoint1:CGPointMake(41.3, 22.1) controlPoint2:CGPointMake(42.7, 23.8)];
    [path addLineToPoint:CGPointMake(42.7, 31.2)];
    [path closePath];
    
    // Top left circle
    [path moveToPoint:CGPointMake(9.7, 20.1)];
    [path addCurveToPoint:CGPointMake(0, 11.1) controlPoint1:CGPointMake(4.3, 20.1) controlPoint2:CGPointMake(0, 16.3)];
    [path addCurveToPoint:CGPointMake(9.9, 2) controlPoint1:CGPointMake(0, 5.9) controlPoint2:CGPointMake(4.7, 1.9)];
    [path addCurveToPoint:CGPointMake(19.4, 11) controlPoint1:CGPointMake(15.1, 2.1) controlPoint2:CGPointMake(19.4, 6.2)];
    [path addCurveToPoint:CGPointMake(9.7, 20.1) controlPoint1:CGPointMake(19.5, 16.1) controlPoint2:CGPointMake(15.1, 20.2)];
    [path closePath];
    
    // Top right circle
    [path moveToPoint:CGPointMake(40.4, 11.2)];
    [path addCurveToPoint:CGPointMake(30.7, 20.2) controlPoint1:CGPointMake(40.4, 16.2) controlPoint2:CGPointMake(36.0, 20.2)];
    [path addCurveToPoint:CGPointMake(20.9, 11.2) controlPoint1:CGPointMake(25.4, 20.2) controlPoint2:CGPointMake(20.9, 16.2)];
    [path addCurveToPoint:CGPointMake(30.6, 2.1) controlPoint1:CGPointMake(20.9, 6.3) controlPoint2:CGPointMake(25.3, 2.1)];
    [path addCurveToPoint:CGPointMake(40.4, 11.2) controlPoint1:CGPointMake(36.0, 2.1) controlPoint2:CGPointMake(40.4, 6.2)];
    [path closePath];
    
    CAShapeLayer *shapeLayer = [CAShapeLayer layer];
    shapeLayer.path = path.CGPath;
    shapeLayer.fillColor = [UIColor blackColor].CGColor;
    
    CGFloat scale = 30.0 / 54.0;
    CGAffineTransform transform = CGAffineTransformMakeScale(scale, scale);
    shapeLayer.path = CGPathCreateCopyByTransformingPath(path.CGPath, &transform);
    shapeLayer.frame = CGRectMake(15, 15, 30, 30);
    
    [button.layer addSublayer:shapeLayer];
}

- (void)setRotationIconForButton:(UIButton *)button {
    // Rotation/Fullscreen icon - simplified version
    UIBezierPath *path = [UIBezierPath bezierPath];
    
    [path moveToPoint:CGPointMake(46.4, 5.5)];
    [path addLineToPoint:CGPointMake(7.6, 5.5)];
    [path addCurveToPoint:CGPointMake(0, 13.2) controlPoint1:CGPointMake(3.4, 5.5) controlPoint2:CGPointMake(0, 9)];
    [path addLineToPoint:CGPointMake(0, 40.9)];
    [path addCurveToPoint:CGPointMake(7.6, 48.5) controlPoint1:CGPointMake(0, 45.1) controlPoint2:CGPointMake(3.4, 48.5)];
    [path addLineToPoint:CGPointMake(46.4, 48.5)];
    [path addCurveToPoint:CGPointMake(54, 40.9) controlPoint1:CGPointMake(50.6, 48.5) controlPoint2:CGPointMake(54, 45.1)];
    [path addLineToPoint:CGPointMake(54, 13.2)];
    [path addCurveToPoint:CGPointMake(46.4, 5.5) controlPoint1:CGPointMake(54, 9) controlPoint2:CGPointMake(50.6, 5.5)];
    [path closePath];
    
    // Bottom left corner
    [path moveToPoint:CGPointMake(18.7, 40.2)];
    [path addLineToPoint:CGPointMake(13.2, 40.2)];
    [path addCurveToPoint:CGPointMake(8.4, 35.4) controlPoint1:CGPointMake(10.5, 40.2) controlPoint2:CGPointMake(8.4, 38.1)];
    [path addLineToPoint:CGPointMake(8.4, 29.9)];
    [path addCurveToPoint:CGPointMake(10.5, 27.8) controlPoint1:CGPointMake(8.4, 28.8) controlPoint2:CGPointMake(9.4, 27.8)];
    [path addCurveToPoint:CGPointMake(12.6, 29.9) controlPoint1:CGPointMake(11.6, 27.8) controlPoint2:CGPointMake(12.6, 28.8)];
    [path addLineToPoint:CGPointMake(12.6, 35.4)];
    [path addCurveToPoint:CGPointMake(13.3, 36.1) controlPoint1:CGPointMake(12.6, 35.8) controlPoint2:CGPointMake(12.9, 36.1)];
    [path addLineToPoint:CGPointMake(18.7, 36.1)];
    [path addCurveToPoint:CGPointMake(20.8, 38.1) controlPoint1:CGPointMake(19.8, 36.1) controlPoint2:CGPointMake(20.8, 37.0)];
    [path addCurveToPoint:CGPointMake(18.7, 40.2) controlPoint1:CGPointMake(20.8, 39.2) controlPoint2:CGPointMake(19.8, 40.2)];
    [path closePath];
    
    // Top right corner
    [path moveToPoint:CGPointMake(45.7, 24.2)];
    [path addCurveToPoint:CGPointMake(43.6, 26.3) controlPoint1:CGPointMake(45.7, 25.3) controlPoint2:CGPointMake(44.7, 26.3)];
    [path addCurveToPoint:CGPointMake(41.5, 24.2) controlPoint1:CGPointMake(42.5, 26.3) controlPoint2:CGPointMake(41.5, 25.3)];
    [path addLineToPoint:CGPointMake(41.5, 18.7)];
    [path addCurveToPoint:CGPointMake(40.8, 18) controlPoint1:CGPointMake(41.5, 18.3) controlPoint2:CGPointMake(41.2, 18)];
    [path addLineToPoint:CGPointMake(35.3, 18)];
    [path addCurveToPoint:CGPointMake(33.2, 15.9) controlPoint1:CGPointMake(34.2, 18) controlPoint2:CGPointMake(33.2, 17.0)];
    [path addCurveToPoint:CGPointMake(35.3, 13.8) controlPoint1:CGPointMake(33.2, 14.8) controlPoint2:CGPointMake(34.2, 13.8)];
    [path addLineToPoint:CGPointMake(40.8, 13.8)];
    [path addCurveToPoint:CGPointMake(45.6, 18.6) controlPoint1:CGPointMake(43.5, 13.8) controlPoint2:CGPointMake(45.6, 15.9)];
    [path addLineToPoint:CGPointMake(45.7, 24.2)];
    [path closePath];
    
    CAShapeLayer *shapeLayer = [CAShapeLayer layer];
    shapeLayer.path = path.CGPath;
    shapeLayer.fillColor = [UIColor blackColor].CGColor;
    
    CGFloat scale = 30.0 / 54.0;
    CGAffineTransform transform = CGAffineTransformMakeScale(scale, scale);
    shapeLayer.path = CGPathCreateCopyByTransformingPath(path.CGPath, &transform);
    shapeLayer.frame = CGRectMake(15, 15, 30, 30);
    
    [button.layer addSublayer:shapeLayer];
}

#pragma mark - Playback

- (void)startPlayback {
    if (!self.hlsUrl || self.hlsUrl.length == 0) {
        [self showError:@"No stream URL provided"];
        return;
    }
    
    NSURL *url = [NSURL URLWithString:self.hlsUrl];
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:url];
    
    [item addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];
    [item addObserver:self forKeyPath:@"playbackBufferEmpty" options:NSKeyValueObservingOptionNew context:nil];
    [item addObserver:self forKeyPath:@"playbackLikelyToKeepUp" options:NSKeyValueObservingOptionNew context:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(playerItemDidReachEnd:) 
                                                 name:AVPlayerItemDidPlayToEndTimeNotification 
                                               object:item];
    
    self.player = [AVPlayer playerWithPlayerItem:item];
    self.player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
    
    self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
    self.playerLayer.frame = self.videoContainer.bounds;
    self.playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    [self.videoContainer.layer addSublayer:self.playerLayer];
    
    [self.player play];
}

- (void)updateHlsUrl:(NSString *)newUrl {
    NSLog(@"[HLSPlayer] Updating URL: %@", newUrl);
    
    self.hlsUrl = newUrl;
    
    @try {
        [self.player.currentItem removeObserver:self forKeyPath:@"status"];
        [self.player.currentItem removeObserver:self forKeyPath:@"playbackBufferEmpty"];
        [self.player.currentItem removeObserver:self forKeyPath:@"playbackLikelyToKeepUp"];
    } @catch (NSException *e) {}
    
    [self.loadingIndicator startAnimating];
    self.statusLabel.text = @"Switching camera...";
    self.statusLabel.hidden = NO;
    
    NSURL *url = [NSURL URLWithString:newUrl];
    AVPlayerItem *newItem = [AVPlayerItem playerItemWithURL:url];
    
    [newItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];
    [newItem addObserver:self forKeyPath:@"playbackBufferEmpty" options:NSKeyValueObservingOptionNew context:nil];
    [newItem addObserver:self forKeyPath:@"playbackLikelyToKeepUp" options:NSKeyValueObservingOptionNew context:nil];
    
    [self.player replaceCurrentItemWithPlayerItem:newItem];
    [self.player play];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    
    if ([keyPath isEqualToString:@"status"]) {
        AVPlayerItem *item = (AVPlayerItem *)object;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (item.status == AVPlayerItemStatusReadyToPlay) {
                self.isPlaying = YES;
                [self.loadingIndicator stopAnimating];
                self.statusLabel.hidden = YES;
                self.errorLabel.hidden = YES;
                [self.delegate hlsPlayerDidChangeStatus:@"PLAYING"];
            } else if (item.status == AVPlayerItemStatusFailed) {
                [self showError:item.error.localizedDescription ?: @"Playback failed"];
            }
        });
    } else if ([keyPath isEqualToString:@"playbackBufferEmpty"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.statusLabel.text = @"Buffering...";
            self.statusLabel.hidden = NO;
            [self.delegate hlsPlayerDidChangeStatus:@"BUFFERING"];
        });
    } else if ([keyPath isEqualToString:@"playbackLikelyToKeepUp"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.statusLabel.hidden = YES;
            [self.delegate hlsPlayerDidChangeStatus:@"PLAYING"];
        });
    }
}

- (void)playerItemDidReachEnd:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusLabel.text = @"Stream ended";
        self.statusLabel.hidden = NO;
        [self.delegate hlsPlayerDidChangeStatus:@"ENDED"];
    });
}

#pragma mark - Actions

- (void)backTapped {
    [self cleanup];
    [self.delegate hlsPlayerDidClose];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)switchCamera {
    self.currentCamera = [self.currentCamera isEqualToString:@"front"] ? @"rear" : @"front";
    [self.cameraSwitchButton setTitle:[self.currentCamera isEqualToString:@"front"] ? @"⟳ Front" : @"⟳ Rear" 
                             forState:UIControlStateNormal];
    [self showToast:@"Switching camera..."];
    [self.delegate hlsPlayerNeedsSwitchCamera:self.currentCamera];
    [self.delegate hlsPlayerDidTriggerAction:@"CAMERA_SWITCHED" camera:self.currentCamera data:nil];
}

- (void)takePhoto {
    [self showToast:@"Taking photo..."];
    [self.delegate hlsPlayerDidTriggerAction:@"PHOTO" camera:self.currentCamera data:nil];
    
    [self sendCameraCommand:@"trigger" success:^{
        [self showToast:@"Photo saved!"];
        [self.delegate hlsPlayerDidTriggerAction:@"PHOTO_SUCCESS" camera:self.currentCamera data:nil];
    } failure:^{
        [self showToast:@"Photo failed"];
        [self.delegate hlsPlayerDidTriggerAction:@"PHOTO_FAILED" camera:self.currentCamera data:nil];
    }];
}

- (void)toggleRecording {
    if (self.isRecordingInProgress) return;
    self.isRecordingInProgress = YES;
    BOOL start = !self.isRecording;
    
    [self showToast:start ? @"Starting..." : @"Stopping..."];
    
    [self sendCameraCommand:start ? @"start" : @"stop" success:^{
        self.isRecording = start;
        [self updateRecordingUI];
        [self showToast:start ? @"Recording" : @"Stopped"];
        [self.delegate hlsPlayerDidTriggerAction:start ? @"RECORD_START" : @"RECORD_STOP" camera:self.currentCamera data:nil];
        self.isRecordingInProgress = NO;
    } failure:^{
        [self showToast:@"Failed"];
        self.isRecordingInProgress = NO;
    }];
}

- (void)toggleOrientation {
    self.isLandscape = !self.isLandscape;
    
    NSLog(@"[HLSPlayer] Toggling orientation to: %@", self.isLandscape ? @"Landscape" : @"Portrait");
    
    // First, update the supported orientations
    [self setNeedsUpdateOfSupportedInterfaceOrientations];
    
    if (@available(iOS 16.0, *)) {
        // iOS 16+ - use new geometry preferences API
        NSArray *scenes = [UIApplication sharedApplication].connectedScenes.allObjects;
        for (UIScene *scene in scenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                UIWindowSceneGeometryPreferencesIOS *preferences = 
                    [[UIWindowSceneGeometryPreferencesIOS alloc] init];
                
                // Set the interface orientations that are now "supported"
                if (self.isLandscape) {
                    preferences.interfaceOrientations = UIInterfaceOrientationMaskLandscape;
                } else {
                    preferences.interfaceOrientations = UIInterfaceOrientationMaskPortrait;
                }
                
                [windowScene requestGeometryUpdateWithPreferences:preferences 
                                                      errorHandler:^(NSError *error) {
                    if (error) {
                        NSLog(@"[HLSPlayer] Orientation change error: %@", error);
                    }
                }];
            }
        }
        
        // Force the view controller to re-evaluate its orientation support
        dispatch_async(dispatch_get_main_queue(), ^{
            [UIViewController attemptRotationToDeviceOrientation];
        });
        
    } else {
        // iOS 15 and below - use setValue trick
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        
        UIInterfaceOrientation targetOrientation = self.isLandscape ? 
            UIInterfaceOrientationLandscapeRight : UIInterfaceOrientationPortrait;
        
        [[UIDevice currentDevice] setValue:@(targetOrientation) forKey:@"orientation"];
        [UIViewController attemptRotationToDeviceOrientation];
        
        #pragma clang diagnostic pop
    }
    
    [self showToast:self.isLandscape ? @"Landscape" : @"Portrait"];
    
    [self.delegate hlsPlayerDidTriggerAction:@"ORIENTATION_CHANGED" 
                                      camera:self.currentCamera 
                                        data:@{@"isLandscape": @(self.isLandscape)}];
}

- (void)updateRecordingUI {
    self.recordingIndicator.hidden = !self.isRecording;
    self.recordButton.backgroundColor = self.isRecording ? [UIColor redColor] : [UIColor whiteColor];
    
    if (self.isRecording) {
        [self.blinkTimer invalidate];
        self.blinkTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) {
            self.recordingDot.alpha = self.recordingDot.alpha > 0.5 ? 0.3 : 1.0;
        }];
    } else {
        [self.blinkTimer invalidate];
        self.recordingDot.alpha = 1.0;
    }
}

#pragma mark - API

- (void)sendCameraCommand:(NSString *)cmd success:(void(^)(void))success failure:(void(^)(void))failure {
    NSString *urlStr = [NSString stringWithFormat:@"%@/cgi-bin/hisnet/workmodecmd.cgi?-cmd=%@", self.apiBaseUrl, cmd];
    NSURL *url = [NSURL URLWithString:urlStr];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url
                                                             completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)r;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (http.statusCode >= 200 && http.statusCode < 300 && !e) {
                if (success) success();
            } else {
                if (failure) failure();
            }
        });
    }];
    [task resume];
}

#pragma mark - Helpers

- (void)showError:(NSString *)msg {
    [self.loadingIndicator stopAnimating];
    self.statusLabel.hidden = YES;
    self.errorLabel.text = msg;
    self.errorLabel.hidden = NO;
    [self.delegate hlsPlayerDidReceiveError:msg];
}

- (void)showToast:(NSString *)msg {
    UILabel *toast = [[UILabel alloc] init];
    toast.text = [NSString stringWithFormat:@"  %@  ", msg];
    toast.backgroundColor = [UIColor colorWithWhite:0 alpha:0.75];
    toast.textColor = [UIColor whiteColor];
    toast.textAlignment = NSTextAlignmentCenter;
    toast.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    toast.layer.cornerRadius = 8;
    toast.clipsToBounds = YES;
    toast.alpha = 0;
    [toast sizeToFit];
    toast.frame = CGRectMake((self.view.bounds.size.width - toast.bounds.size.width - 32) / 2,
                             self.view.bounds.size.height - 220,
                             toast.bounds.size.width + 32, 40);
    [self.view addSubview:toast];
    
    [UIView animateWithDuration:0.2 animations:^{ toast.alpha = 1; } completion:^(BOOL f) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.2 animations:^{ toast.alpha = 0; } completion:^(BOOL f) {
                [toast removeFromSuperview];
            }];
        });
    }];
}

@end
