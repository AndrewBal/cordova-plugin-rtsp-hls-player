//
//  HlsPlayerViewController.h
//  Native AVPlayer-based HLS player
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol HlsPlayerViewControllerDelegate <NSObject>

- (void)hlsPlayerDidChangeStatus:(NSString *)status;
- (void)hlsPlayerDidClose;
- (void)hlsPlayerDidTriggerAction:(NSString *)action camera:(NSString *)camera data:(nullable NSDictionary *)data;
- (void)hlsPlayerDidReceiveError:(NSString *)error;
- (void)hlsPlayerNeedsSwitchCamera:(NSString *)camera;

@end

@interface HlsPlayerViewController : UIViewController

@property (nonatomic, weak) id<HlsPlayerViewControllerDelegate> delegate;

@property (nonatomic, copy) NSString *hlsUrl;
@property (nonatomic, copy) NSString *frontRtspUrl;
@property (nonatomic, copy) NSString *rearRtspUrl;
@property (nonatomic, copy) NSString *titleText;
@property (nonatomic, copy) NSString *currentCamera;
@property (nonatomic, copy) NSString *apiBaseUrl;

- (void)updateHlsUrl:(NSString *)newUrl;

@end

NS_ASSUME_NONNULL_END
