//
//  RtspHlsConverter.h
//  RTSP to HLS Converter using FFmpegKit
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^RtspHlsStatusCallback)(NSString *status, NSString * _Nullable message);
typedef void (^RtspHlsErrorCallback)(NSString *error);

@interface RtspHlsConverter : NSObject

@property (nonatomic, readonly) BOOL isConverting;
@property (nonatomic, readonly) NSString *hlsOutputPath;
@property (nonatomic, readonly) NSString *hlsUrl;

+ (BOOL)isFFmpegAvailable;

- (void)startConversion:(NSString *)rtspUrl
         statusCallback:(RtspHlsStatusCallback)statusCallback
          errorCallback:(RtspHlsErrorCallback)errorCallback;

- (void)stopConversion;

- (void)switchToUrl:(NSString *)newRtspUrl 
     statusCallback:(RtspHlsStatusCallback)statusCallback;

- (NSDictionary *)getStats;

- (void)cleanup;

@end

NS_ASSUME_NONNULL_END
