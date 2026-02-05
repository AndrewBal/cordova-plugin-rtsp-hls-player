//
//  RtspHlsPlayerPlugin.h
//  RTSP to HLS Player Plugin for Cordova
//

#import <Cordova/CDV.h>
#import "RtspHlsConverter.h"
#import "HlsPlayerViewController.h"

@interface RtspHlsPlayerPlugin : CDVPlugin <HlsPlayerViewControllerDelegate>

@property (nonatomic, strong) RtspHlsConverter *converter;
@property (nonatomic, strong) HlsPlayerViewController *playerVC;
@property (nonatomic, copy) NSString *callbackId;
@property (nonatomic, copy) NSString *apiBaseUrl;

- (void)play:(CDVInvokedUrlCommand *)command;
- (void)stop:(CDVInvokedUrlCommand *)command;
- (void)checkAvailability:(CDVInvokedUrlCommand *)command;
- (void)getStats:(CDVInvokedUrlCommand *)command;

@end
