//
//  RtspHlsPlayerPlugin.m
//  RTSP to HLS Player Plugin for Cordova
//

#import "RtspHlsPlayerPlugin.h"

@implementation RtspHlsPlayerPlugin

- (void)pluginInitialize {
    [super pluginInitialize];
    NSLog(@"[RtspHlsPlayer] Plugin initialized");
}

#pragma mark - Plugin Methods

- (void)play:(CDVInvokedUrlCommand *)command {
    NSDictionary *options = [command.arguments firstObject];
    
    NSString *frontUrl = options[@"frontUrl"] ?: @"";
    NSString *rearUrl = options[@"rearUrl"] ?: @"";
    NSString *title = options[@"title"] ?: @"Live Stream";
    NSString *initialCamera = options[@"initialCamera"] ?: @"front";
    self.apiBaseUrl = options[@"apiBaseUrl"] ?: @"http://192.168.0.1";
    
    self.callbackId = command.callbackId;
    
    NSLog(@"[RtspHlsPlayer] play - frontUrl: %@", frontUrl);
    
    [self sendStatus:@"STARTING" message:@"Initializing..."];
    
    self.converter = [[RtspHlsConverter alloc] init];
    
    __weak typeof(self) weakSelf = self;
    
    [self.converter startConversion:frontUrl 
                     statusCallback:^(NSString *status, NSString *message) {
        [weakSelf sendStatus:status message:message];
        
        if ([status isEqualToString:@"HLS_READY"]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf showPlayerWithHlsUrl:message
                                      frontUrl:frontUrl
                                       rearUrl:rearUrl
                                         title:title
                                 initialCamera:initialCamera];
            });
        }
    } 
                      errorCallback:^(NSString *error) {
        [weakSelf sendError:error];
    }];
}

- (void)stop:(CDVInvokedUrlCommand *)command {
    NSLog(@"[RtspHlsPlayer] stop");
    
    [self.converter stopConversion];
    
    if (self.playerVC) {
        [self.playerVC dismissViewControllerAnimated:YES completion:nil];
        self.playerVC = nil;
    }
    
    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

- (void)checkAvailability:(CDVInvokedUrlCommand *)command {
    BOOL available = [RtspHlsConverter isFFmpegAvailable];
    
    NSDictionary *result = @{@"available": @(available)};
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK 
                                                  messageAsDictionary:result];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)getStats:(CDVInvokedUrlCommand *)command {
    NSDictionary *stats = [self.converter getStats];
    
    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK 
                                            messageAsDictionary:stats ?: @{}];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

#pragma mark - Player

- (void)showPlayerWithHlsUrl:(NSString *)hlsUrl 
                    frontUrl:(NSString *)frontUrl 
                     rearUrl:(NSString *)rearUrl 
                       title:(NSString *)title 
               initialCamera:(NSString *)initialCamera {
    
    self.playerVC = [[HlsPlayerViewController alloc] init];
    self.playerVC.hlsUrl = hlsUrl;
    self.playerVC.frontRtspUrl = frontUrl;
    self.playerVC.rearRtspUrl = rearUrl;
    self.playerVC.titleText = title;
    self.playerVC.currentCamera = initialCamera;
    self.playerVC.apiBaseUrl = self.apiBaseUrl;
    self.playerVC.delegate = self;
    self.playerVC.modalPresentationStyle = UIModalPresentationFullScreen;
    
    [self.viewController presentViewController:self.playerVC animated:YES completion:nil];
}

#pragma mark - HlsPlayerViewControllerDelegate

- (void)hlsPlayerDidChangeStatus:(NSString *)status {
    [self sendStatus:status message:nil];
}

- (void)hlsPlayerDidClose {
    NSLog(@"[RtspHlsPlayer] Player closed");
    [self.converter stopConversion];
    [self sendStatus:@"CLOSED" message:nil];
}

- (void)hlsPlayerDidTriggerAction:(NSString *)action camera:(NSString *)camera data:(NSDictionary *)data {
    NSLog(@"[RtspHlsPlayer] Action: %@, camera: %@", action, camera);
    
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"type"] = @"action";
    result[@"action"] = action;
    result[@"camera"] = camera;
    if (data) result[@"data"] = data;
    
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK 
                                                  messageAsDictionary:result];
    [pluginResult setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
}

- (void)hlsPlayerDidReceiveError:(NSString *)error {
    [self sendError:error];
}

- (void)hlsPlayerNeedsSwitchCamera:(NSString *)camera {
    NSString *newRtspUrl;
    if ([camera isEqualToString:@"rear"]) {
        newRtspUrl = self.playerVC.rearRtspUrl;
    } else {
        newRtspUrl = self.playerVC.frontRtspUrl;
    }
    
    if (!newRtspUrl || newRtspUrl.length == 0) {
        NSLog(@"[RtspHlsPlayer] No URL for camera: %@", camera);
        return;
    }
    
    [self sendStatus:@"SWITCHING_CAMERA" message:camera];
    
    __weak typeof(self) weakSelf = self;
    [self.converter switchToUrl:newRtspUrl 
                 statusCallback:^(NSString *status, NSString *message) {
        [weakSelf sendStatus:status message:message];
        
        if ([status isEqualToString:@"HLS_READY"]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf.playerVC updateHlsUrl:message];
            });
        }
    }];
}

#pragma mark - Callbacks

- (void)sendStatus:(NSString *)status message:(NSString *)message {
    if (!self.callbackId) return;
    
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"type"] = @"status";
    result[@"status"] = status;
    if (message) result[@"message"] = message;
    
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK 
                                                  messageAsDictionary:result];
    [pluginResult setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
}

- (void)sendError:(NSString *)error {
    if (!self.callbackId) return;
    
    NSLog(@"[RtspHlsPlayer] Error: %@", error);
    
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR 
                                                      messageAsString:error];
    [pluginResult setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
}

@end
