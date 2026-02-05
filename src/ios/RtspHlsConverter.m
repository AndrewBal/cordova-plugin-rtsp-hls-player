//
//  RtspHlsConverter.m
//  RTSP to HLS Converter using FFmpegKit
//

#import "RtspHlsConverter.h"
#import <AVFoundation/AVFoundation.h>

// FFmpegKit import
#if __has_include(<ffmpegkit/FFmpegKit.h>)
    #import <ffmpegkit/FFmpegKit.h>
    #import <ffmpegkit/FFmpegKitConfig.h>
    #import <ffmpegkit/FFmpegSession.h>
    #import <ffmpegkit/ReturnCode.h>
    #define HAS_FFMPEG 1
#elif __has_include("FFmpegKit.h")
    #import "FFmpegKit.h"
    #import "FFmpegKitConfig.h"
    #import "FFmpegSession.h"
    #import "ReturnCode.h"
    #define HAS_FFMPEG 1
#else
    #define HAS_FFMPEG 0
    #warning "FFmpegKit not found!"
#endif

// GCDWebServer import
#if __has_include(<GCDWebServer/GCDWebServer.h>)
    #import <GCDWebServer/GCDWebServer.h>
    #define HAS_WEBSERVER 1
#elif __has_include("GCDWebServer.h")
    #import "GCDWebServer.h"
    #define HAS_WEBSERVER 1
#else
    #define HAS_WEBSERVER 0
    #warning "GCDWebServer not found!"
#endif

@interface RtspHlsConverter ()

@property (nonatomic, assign) BOOL isConverting;
@property (nonatomic, copy) NSString *hlsOutputPath;
@property (nonatomic, copy) NSString *hlsUrl;
@property (nonatomic, copy) NSString *currentRtspUrl;

#if HAS_FFMPEG
@property (nonatomic, strong) id ffmpegSession;
#endif

#if HAS_WEBSERVER
@property (nonatomic, strong) GCDWebServer *webServer;
#endif

@property (nonatomic, assign) NSUInteger serverPort;
@property (nonatomic, copy) RtspHlsStatusCallback statusCallback;
@property (nonatomic, copy) RtspHlsErrorCallback errorCallback;
@property (nonatomic, strong) NSTimer *hlsCheckTimer;
@property (nonatomic, assign) NSInteger segmentCount;
@property (nonatomic, strong) NSDate *startTime;

@end

@implementation RtspHlsConverter

- (instancetype)init {
    self = [super init];
    if (self) {
        _isConverting = NO;
        _serverPort = 8765;
        _segmentCount = 0;
        [self setupOutputDirectory];
    }
    return self;
}

- (void)dealloc {
    [self stopConversion];
    [self cleanup];
}

#pragma mark - Setup

- (void)setupOutputDirectory {
    NSString *tmpDir = NSTemporaryDirectory();
    self.hlsOutputPath = [tmpDir stringByAppendingPathComponent:@"hls_stream"];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    
    if ([fm fileExistsAtPath:self.hlsOutputPath]) {
        [fm removeItemAtPath:self.hlsOutputPath error:nil];
    }
    
    [fm createDirectoryAtPath:self.hlsOutputPath 
  withIntermediateDirectories:YES 
                   attributes:nil 
                        error:nil];
    
    NSLog(@"[HLS] Output directory: %@", self.hlsOutputPath);
}

#pragma mark - Public Methods

+ (BOOL)isFFmpegAvailable {
#if HAS_FFMPEG
    return YES;
#else
    return NO;
#endif
}

- (void)startConversion:(NSString *)rtspUrl
         statusCallback:(RtspHlsStatusCallback)statusCallback
          errorCallback:(RtspHlsErrorCallback)errorCallback {
    
    self.statusCallback = statusCallback;
    self.errorCallback = errorCallback;
    self.currentRtspUrl = rtspUrl;
    
#if HAS_FFMPEG && HAS_WEBSERVER
    NSLog(@"[HLS] Starting conversion: %@", rtspUrl);
    
    [self setupOutputDirectory];
    [self startWebServer];
    [self startFFmpegConversion:rtspUrl];
    
#else
    NSLog(@"[HLS] FFmpegKit or GCDWebServer not available");
    if (errorCallback) {
        errorCallback(@"FFmpegKit or GCDWebServer not installed. Check Podfile.");
    }
#endif
}

- (void)stopConversion {
    NSLog(@"[HLS] Stopping conversion");
    
    self.isConverting = NO;
    
    [self.hlsCheckTimer invalidate];
    self.hlsCheckTimer = nil;
    
#if HAS_FFMPEG
    if (self.ffmpegSession) {
        [FFmpegKit cancel];
        self.ffmpegSession = nil;
    }
#endif
    
    [self stopWebServer];
}

- (void)switchToUrl:(NSString *)newRtspUrl 
     statusCallback:(RtspHlsStatusCallback)statusCallback {
    
    NSLog(@"[HLS] Switching to URL: %@", newRtspUrl);
    
    self.statusCallback = statusCallback;
    
#if HAS_FFMPEG
    [FFmpegKit cancel];
    self.ffmpegSession = nil;
#endif
    
    [self.hlsCheckTimer invalidate];
    [self setupOutputDirectory];
    
    self.currentRtspUrl = newRtspUrl;
    self.segmentCount = 0;
    
#if HAS_FFMPEG
    [self startFFmpegConversion:newRtspUrl];
#endif
}

- (NSDictionary *)getStats {
    NSTimeInterval duration = 0;
    if (self.startTime) {
        duration = [[NSDate date] timeIntervalSinceDate:self.startTime];
    }
    
    return @{
        @"isConverting": @(self.isConverting),
        @"segmentCount": @(self.segmentCount),
        @"durationSeconds": @(duration),
        @"hlsUrl": self.hlsUrl ?: @""
    };
}

- (void)cleanup {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (self.hlsOutputPath && [fm fileExistsAtPath:self.hlsOutputPath]) {
        [fm removeItemAtPath:self.hlsOutputPath error:nil];
    }
}

#pragma mark - FFmpeg

#if HAS_FFMPEG
- (void)startFFmpegConversion:(NSString *)rtspUrl {
    
    if (self.statusCallback) {
        self.statusCallback(@"CONVERTING", @"Starting FFmpeg...");
    }
    
    NSString *outputPath = [self.hlsOutputPath stringByAppendingPathComponent:@"stream.m3u8"];
    NSString *segmentPath = [self.hlsOutputPath stringByAppendingPathComponent:@"segment%d.ts"];
    
    // FFmpeg command for RTSP → HLS
    NSString *command = [NSString stringWithFormat:
        @"-fflags nobuffer "
        @"-flags low_delay "
        @"-rtsp_transport tcp "
        @"-i \"%@\" "
        @"-vsync 0 "
        @"-copyts "
        @"-vcodec copy "
        @"-acodec aac "
        @"-b:a 128k "
        @"-f hls "
        @"-hls_time 2 "
        @"-hls_list_size 5 "
        @"-hls_flags delete_segments+append_list "
        @"-hls_segment_filename \"%@\" "
        @"-start_number 0 "
        @"\"%@\"",
        rtspUrl, segmentPath, outputPath];
    
    NSLog(@"[HLS] FFmpeg command: %@", command);
    
    self.isConverting = YES;
    self.startTime = [NSDate date];
    self.segmentCount = 0;
    
    [self startHLSMonitoring];
    
    __weak typeof(self) weakSelf = self;
    
    self.ffmpegSession = [FFmpegKit executeAsync:command 
                              withCompleteCallback:^(FFmpegSession *session) {
        dispatch_async(dispatch_get_main_queue(), ^{
            ReturnCode *returnCode = [session getReturnCode];
            
            if ([ReturnCode isSuccess:returnCode]) {
                NSLog(@"[HLS] FFmpeg completed successfully");
            } else if ([ReturnCode isCancel:returnCode]) {
                NSLog(@"[HLS] FFmpeg cancelled");
            } else {
                NSLog(@"[HLS] FFmpeg failed with code: %d", [returnCode getValue]);
                
                if (weakSelf.errorCallback && weakSelf.isConverting) {
                    NSString *output = [session getOutput];
                    weakSelf.errorCallback([NSString stringWithFormat:@"FFmpeg error: %@", 
                                           output ?: @"Unknown"]);
                }
            }
            
            weakSelf.isConverting = NO;
        });
    } 
                                 withLogCallback:nil 
                          withStatisticsCallback:nil];
}
#endif

#pragma mark - HLS Monitoring

- (void)startHLSMonitoring {
    [self.hlsCheckTimer invalidate];
    
    __weak typeof(self) weakSelf = self;
    self.hlsCheckTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 
                                                         repeats:YES 
                                                           block:^(NSTimer *timer) {
        [weakSelf checkHLSFile];
    }];
}

- (void)checkHLSFile {
    NSString *m3u8Path = [self.hlsOutputPath stringByAppendingPathComponent:@"stream.m3u8"];
    NSFileManager *fm = [NSFileManager defaultManager];
    
    if ([fm fileExistsAtPath:m3u8Path]) {
        NSDictionary *attrs = [fm attributesOfItemAtPath:m3u8Path error:nil];
        unsigned long long size = [attrs fileSize];
        
        if (size > 50) {
            NSArray *files = [fm contentsOfDirectoryAtPath:self.hlsOutputPath error:nil];
            NSInteger segments = 0;
            for (NSString *file in files) {
                if ([file hasSuffix:@".ts"]) {
                    segments++;
                }
            }
            
            self.segmentCount = segments;
            
            if (segments >= 1) {
                NSLog(@"[HLS] Ready! Segments: %ld", (long)segments);
                
                [self.hlsCheckTimer invalidate];
                self.hlsCheckTimer = nil;
                
                if (self.statusCallback) {
                    self.statusCallback(@"HLS_READY", self.hlsUrl);
                }
                
                [self startSegmentMonitoring];
            }
        }
    }
}

- (void)startSegmentMonitoring {
    __weak typeof(self) weakSelf = self;
    self.hlsCheckTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 
                                                         repeats:YES 
                                                           block:^(NSTimer *timer) {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSArray *files = [fm contentsOfDirectoryAtPath:weakSelf.hlsOutputPath error:nil];
        NSInteger segments = 0;
        for (NSString *file in files) {
            if ([file hasSuffix:@".ts"]) {
                segments++;
            }
        }
        weakSelf.segmentCount = segments;
    }];
}

#pragma mark - Web Server

- (void)startWebServer {
#if HAS_WEBSERVER
    if (self.webServer && self.webServer.isRunning) {
        return;
    }
    
    self.webServer = [[GCDWebServer alloc] init];
    
    [self.webServer addGETHandlerForBasePath:@"/hls/" 
                               directoryPath:self.hlsOutputPath 
                               indexFilename:nil 
                                    cacheAge:0 
                          allowRangeRequests:YES];
    
    NSError *error = nil;
    NSDictionary *options = @{
        GCDWebServerOption_Port: @(self.serverPort),
        GCDWebServerOption_BindToLocalhost: @YES,
        GCDWebServerOption_AutomaticallySuspendInBackground: @NO
    };
    
    BOOL started = [self.webServer startWithOptions:options error:&error];
    
    if (started) {
        self.hlsUrl = [NSString stringWithFormat:@"http://127.0.0.1:%lu/hls/stream.m3u8", 
                       (unsigned long)self.serverPort];
        NSLog(@"[HLS] Web server started: %@", self.hlsUrl);
    } else {
        NSLog(@"[HLS] Failed to start web server: %@", error);
        
        self.serverPort = 8766;
        options = @{
            GCDWebServerOption_Port: @(self.serverPort),
            GCDWebServerOption_BindToLocalhost: @YES
        };
        
        if ([self.webServer startWithOptions:options error:&error]) {
            self.hlsUrl = [NSString stringWithFormat:@"http://127.0.0.1:%lu/hls/stream.m3u8", 
                           (unsigned long)self.serverPort];
            NSLog(@"[HLS] Web server started on alt port: %@", self.hlsUrl);
        } else {
            if (self.errorCallback) {
                self.errorCallback(@"Failed to start local HLS server");
            }
        }
    }
#endif
}

- (void)stopWebServer {
#if HAS_WEBSERVER
    if (self.webServer && self.webServer.isRunning) {
        [self.webServer stop];
        NSLog(@"[HLS] Web server stopped");
    }
    self.webServer = nil;
#endif
}

@end
