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

@end

@implementation HlsPlayerViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor blackColor];
    
    if (!self.currentCamera) self.currentCamera = @"front";
    if (!self.apiBaseUrl) self.apiBaseUrl = @"http://192.168.0.1";
    
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
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAllButUpsideDown; }

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
    
    self.backButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.backButton.frame = CGRectMake(16, 0, 44, 44);
    [self.backButton setTitle:@"✕" forState:UIControlStateNormal];
    self.backButton.titleLabel.font = [UIFont systemFontOfSize:24 weight:UIFontWeightBold];
    self.backButton.tintColor = [UIColor whiteColor];
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
        self.cameraSwitchButton = [UIButton buttonWithType:UIButtonTypeCustom];
        self.cameraSwitchButton.frame = CGRectMake(self.view.bounds.size.width - 100, 50, 90, 36);
        self.cameraSwitchButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        self.cameraSwitchButton.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
        self.cameraSwitchButton.layer.cornerRadius = 18;
        [self.cameraSwitchButton setTitle:@"⟳ Front" forState:UIControlStateNormal];
        [self.cameraSwitchButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.cameraSwitchButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        [self.cameraSwitchButton addTarget:self action:@selector(switchCamera) forControlEvents:UIControlEventTouchUpInside];
        [self.topBar addSubview:self.cameraSwitchButton];
    }
}

- (void)setupBottomControls {
    self.bottomControls = [[UIView alloc] initWithFrame:CGRectMake(0, self.view.bounds.size.height - 160,
                                                                   self.view.bounds.size.width, 160)];
    self.bottomControls.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    [self.view addSubview:self.bottomControls];
    
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.frame = CGRectMake(0, 0, self.view.bounds.size.width * 2, 160);
    gradient.colors = @[(id)[UIColor clearColor].CGColor, (id)[UIColor colorWithWhite:0 alpha:0.8].CGColor];
    [self.bottomControls.layer insertSublayer:gradient atIndex:0];
    
    CGFloat centerY = 60, centerX = self.view.bounds.size.width / 2, spacing = 100;
    
    self.photoButton = [self createCircleButton:60];
    self.photoButton.center = CGPointMake(centerX - spacing, centerY);
    [self.photoButton setTitle:@"📷" forState:UIControlStateNormal];
    [self.photoButton addTarget:self action:@selector(takePhoto) forControlEvents:UIControlEventTouchUpInside];
    [self.bottomControls addSubview:self.photoButton];
    
    self.recordButton = [self createCircleButton:72];
    self.recordButton.center = CGPointMake(centerX, centerY);
    [self.recordButton setTitle:@"⏺" forState:UIControlStateNormal];
    [self.recordButton addTarget:self action:@selector(toggleRecording) forControlEvents:UIControlEventTouchUpInside];
    [self.bottomControls addSubview:self.recordButton];
    
    self.fullscreenButton = [self createCircleButton:60];
    self.fullscreenButton.center = CGPointMake(centerX + spacing, centerY);
    [self.fullscreenButton setTitle:@"⤢" forState:UIControlStateNormal];
    [self.fullscreenButton addTarget:self action:@selector(toggleFullscreen) forControlEvents:UIControlEventTouchUpInside];
    [self.bottomControls addSubview:self.fullscreenButton];
}

- (UIButton *)createCircleButton:(CGFloat)size {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = CGRectMake(0, 0, size, size);
    button.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.9];
    button.layer.cornerRadius = size / 2;
    button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    button.titleLabel.font = [UIFont systemFontOfSize:size * 0.4];
    [button setTitleColor:[UIColor darkGrayColor] forState:UIControlStateNormal];
    return button;
}

#pragma mark - AVPlayer

- (void)startPlayback {
    if (!self.hlsUrl || self.hlsUrl.length == 0) {
        [self showError:@"No HLS URL provided"];
        return;
    }
    
    NSLog(@"[HLSPlayer] Starting: %@", self.hlsUrl);
    
    NSURL *url = [NSURL URLWithString:self.hlsUrl];
    AVPlayerItem *playerItem = [AVPlayerItem playerItemWithURL:url];
    
    self.player = [AVPlayer playerWithPlayerItem:playerItem];
    
    self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
    self.playerLayer.frame = self.videoContainer.bounds;
    self.playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    [self.videoContainer.layer addSublayer:self.playerLayer];
    
    [playerItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];
    [playerItem addObserver:self forKeyPath:@"playbackBufferEmpty" options:NSKeyValueObservingOptionNew context:nil];
    [playerItem addObserver:self forKeyPath:@"playbackLikelyToKeepUp" options:NSKeyValueObservingOptionNew context:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(playerItemDidReachEnd:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:playerItem];
    
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

- (void)toggleFullscreen {
    if ([self.playerLayer.videoGravity isEqualToString:AVLayerVideoGravityResizeAspect]) {
        self.playerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    } else {
        self.playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    }
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
