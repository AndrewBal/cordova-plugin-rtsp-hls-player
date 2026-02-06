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

#if __has_include(<GCDWebServer/GCDWebServerFileResponse.h>)
    #import <GCDWebServer/GCDWebServerFileResponse.h>
#elif __has_include("GCDWebServerFileResponse.h")
    #import "GCDWebServerFileResponse.h"
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
        @"-fflags +genpts+nobuffer "
        @"-flags low_delay "
        @"-rtsp_transport tcp "
        @"-use_wallclock_as_timestamps 1 "
        @"-i \"%@\" "
        @"-an "
        @"-c:v copy "
        @"-f hls "
        @"-hls_time 2 "
        @"-hls_list_size 6 "
        @"-hls_allow_cache 0 "
        @"-hls_flags delete_segments+append_list+independent_segments "
        @"-hls_segment_filename \"%@\" "
        @"-start_number 0 "
        @"\"%@\"",
        rtspUrl, segmentPath, outputPath];
    
    self.isConverting = YES;
    self.startTime = [NSDate date];
    self.segmentCount = 0;
    
    [self startHLSMonitoring];
    
    __weak RtspHlsConverter *weakSelf = self;
    
    self.ffmpegSession = [FFmpegKit executeAsync:command 
                              withCompleteCallback:^(FFmpegSession *session) {
        dispatch_async(dispatch_get_main_queue(), ^{
            RtspHlsConverter *strongSelf = weakSelf;
            if (!strongSelf) return;
            
            ReturnCode *returnCode = [session getReturnCode];
            
            if ([ReturnCode isSuccess:returnCode]) {
                NSLog(@"[HLS] FFmpeg completed successfully");
            } else if ([ReturnCode isCancel:returnCode]) {
                NSLog(@"[HLS] FFmpeg cancelled");
            } else {
                NSLog(@"[HLS] FFmpeg failed with code: %d", [returnCode getValue]);
                
                if (strongSelf.errorCallback && strongSelf.isConverting) {
                    NSString *output = [session getOutput];
                    NSString *errorMessage = [strongSelf extractErrorMessage:output];
                    strongSelf.errorCallback(errorMessage);
                }
            }
            
            strongSelf.isConverting = NO;
        });
    } 
                                 withLogCallback:nil 
                          withStatisticsCallback:nil];
}
#endif

#pragma mark - HLS Monitoring

- (void)startHLSMonitoring {
    [self.hlsCheckTimer invalidate];
    
    __weak RtspHlsConverter *weakSelf = self;
    self.hlsCheckTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 
                                                         repeats:YES 
                                                           block:^(NSTimer *timer) {
        RtspHlsConverter *strongSelf = weakSelf;
        if (strongSelf) {
            [strongSelf checkHLSFile];
        }
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
            
            if (segments >= 3) {
                NSLog(@"[HLS] Ready! Segments: %ld", (long)segments);
                
                [self.hlsCheckTimer invalidate];
                self.hlsCheckTimer = nil;
                
                if (self.statusCallback) {
                    NSString *freshUrl = [NSString stringWithFormat:@"%@?t=%0.f", self.hlsUrl, [[NSDate date] timeIntervalSince1970]];
                    self.statusCallback(@"HLS_READY", self.hlsUrl);
                }
                
                [self startSegmentMonitoring];
            }
        }
    }
}

- (void)startSegmentMonitoring {
    __weak RtspHlsConverter *weakSelf = self;
    self.hlsCheckTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 
                                                         repeats:YES 
                                                           block:^(NSTimer *timer) {
        RtspHlsConverter *strongSelf = weakSelf;
        if (!strongSelf) return;
        
        NSFileManager *fm = [NSFileManager defaultManager];
        NSArray *files = [fm contentsOfDirectoryAtPath:strongSelf.hlsOutputPath error:nil];
        NSInteger segments = 0;
        for (NSString *file in files) {
            if ([file hasSuffix:@".ts"]) {
                segments++;
            }
        }
        strongSelf.segmentCount = segments;
    }];
}

#pragma mark - Web Server

- (void)startWebServer {
#if HAS_WEBSERVER
    if (self.webServer && self.webServer.isRunning) {
        return;
    }

    self.webServer = [[GCDWebServer alloc] init];

    NSString *baseDir = self.hlsOutputPath;

    [self.webServer addHandlerForMethod:@"GET"
                              pathRegex:@"/hls/.*"
                           requestClass:[GCDWebServerRequest class]
                           processBlock:^GCDWebServerResponse * (GCDWebServerRequest *request) {

        NSString *rel = [request.path stringByReplacingOccurrencesOfString:@"/hls/" withString:@""];
        NSString *filePath = [baseDir stringByAppendingPathComponent:rel];

        if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
            return [GCDWebServerResponse responseWithStatusCode:404];
        }

        GCDWebServerFileResponse *resp = [GCDWebServerFileResponse responseWithFile:filePath];

        // no-cache (важно для live m3u8)
        resp.cacheControlMaxAge = 0;
        [resp setValue:@"no-cache, no-store, must-revalidate" forAdditionalHeader:@"Cache-Control"];
        [resp setValue:@"no-cache" forAdditionalHeader:@"Pragma"];
        [resp setValue:@"0" forAdditionalHeader:@"Expires"];

        // правильные content-type (AVPlayer любит)
        if ([rel hasSuffix:@".m3u8"]) {
            resp.contentType = @"application/vnd.apple.mpegurl";
        } else if ([rel hasSuffix:@".ts"]) {
            resp.contentType = @"video/MP2T";
        }

        return resp;
    }];

    NSError *error = nil;
    NSDictionary *options = @{
        GCDWebServerOption_Port: @(self.serverPort),
        GCDWebServerOption_BindToLocalhost: @YES,
        GCDWebServerOption_AutomaticallySuspendInBackground: @NO
    };

    BOOL started = [self.webServer startWithOptions:options error:&error];

    if (!started) {
        NSLog(@"[HLS] Failed to start web server: %@", error);

        self.serverPort = 8766;
        options = @{
            GCDWebServerOption_Port: @(self.serverPort),
            GCDWebServerOption_BindToLocalhost: @YES,
            GCDWebServerOption_AutomaticallySuspendInBackground: @NO
        };

        started = [self.webServer startWithOptions:options error:&error];
    }

    if (started) {
        self.hlsUrl = [NSString stringWithFormat:@"http://127.0.0.1:%lu/hls/stream.m3u8",
                       (unsigned long)self.serverPort];
        NSLog(@"[HLS] Web server started: %@", self.hlsUrl);
    } else {
        NSLog(@"[HLS] Failed to start local HLS server: %@", error);
        if (self.errorCallback) self.errorCallback(@"Failed to start local HLS server");
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

#pragma mark - Error Handling

- (NSString *)extractErrorMessage:(NSString *)ffmpegOutput {
    if (!ffmpegOutput || ffmpegOutput.length == 0) {
        return @"Connection error";
    }
    
    // Split output into lines
    NSArray *lines = [ffmpegOutput componentsSeparatedByString:@"\n"];
    
    // Look for ERROR: lines
    for (NSString *line in lines) {
        if ([line hasPrefix:@"ERROR:"]) {
            // Extract just the error message, not the full line
            NSString *errorMsg = [line substringFromIndex:6]; // Skip "ERROR:"
            errorMsg = [errorMsg stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            
            // Check for specific error types
            if ([errorMsg containsString:@"No route to host"]) {
                return @"Local Network permission required";
            }
            else if ([errorMsg containsString:@"Connection refused"]) {
                return @"Camera not responding";
            }
            else if ([errorMsg containsString:@"timeout"] || [errorMsg containsString:@"timed out"]) {
                return @"Connection timeout";
            }
            else if ([errorMsg containsString:@"Connection to"]) {
                // "Connection to tcp://192.168.0.1:554 failed"
                return @"Cannot connect to camera";
            }
            else if (errorMsg.length < 100) {
                // If error is short, return it
                return errorMsg;
            }
            else {
                // Error too long, return generic message
                return @"Stream connection error";
            }
        }
    }
    
    // No ERROR: line found, check for common issues in full output
    if ([ffmpegOutput containsString:@"No route to host"]) {
        return @"Local Network permission required";
    }
    else if ([ffmpegOutput containsString:@"Connection refused"]) {
        return @"Camera not responding";
    }
    else if ([ffmpegOutput containsString:@"timeout"]) {
        return @"Connection timeout";
    }
    
    // Generic error
    return @"Stream connection error";
}

@end