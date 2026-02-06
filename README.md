# cordova-plugin-rtsp-hls-player

RTSP → HLS streaming player for iOS using FFmpegKit and native AVPlayer.

## Why this plugin?

MobileVLCKit has a chronic issue on iOS 14+:

```
Unable to determine our source address: This computer has an invalid IP address: 0.0.0.0
```

This plugin avoids that problem by converting **RTSP → HLS** using FFmpeg.

## Plugin structure

```
cordova-plugin-rtsp-hls-player/
├── plugin.xml
├── package.json
├── README.md
├── www/
│   └── RtspHlsPlayer.js
└── src/
    └── ios/
        ├── RtspHlsPlayerPlugin.h
        ├── RtspHlsPlayerPlugin.m
        ├── RtspHlsConverter.h
        ├── RtspHlsConverter.m
        ├── HlsPlayerViewController.h
        └── HlsPlayerViewController.m
```

## Installation

### 1. Add the plugin

```bash
cordova plugin add https://github.com/AndrewBal/cordova-plugin-rtsp-hls-player.git
```

### 2. Update the Podfile

In `platforms/ios/Podfile`, add the dependencies:

```ruby
platform :ios, '14.0'
use_frameworks!

target 'YourApp' do
  # FFmpegKit (community fork — the original is discontinued/closed)
  pod 'ffmpeg-kit-ios-full', :podspec => 'https://raw.githubusercontent.com/luthviar/ffmpeg-kit-ios-full/main/ffmpeg-kit-ios-full.podspec'
  
  # Local HTTP server for HLS playback
  pod 'GCDWebServer', '~> 3.5'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '14.0'
      config.build_settings['ENABLE_BITCODE'] = 'NO'
    end
  end
end
```

### 3. Install pods

```bash
cd platforms/ios
pod update
```

### 4. Open the workspace

```bash
open YourApp.xcworkspace
```

**IMPORTANT**: Open `.xcworkspace`, NOT `.xcodeproj`.

## Usage

```javascript
// Check FFmpeg availability
RtspHlsPlayer.checkAvailability(function(available) {
    console.log('FFmpeg available:', available);
});

// Start streaming
RtspHlsPlayer.play({
    frontUrl: 'rtsp://192.168.0.1:554/livestream/1',
    rearUrl: 'rtsp://192.168.0.1:554/livestream/2',  // optional
    title: 'Dashcam Live',
    apiBaseUrl: 'http://192.168.0.1'
}, 
function(status, message) {
    // Statuses: STARTING, CONVERTING, HLS_READY, BUFFERING, PLAYING, CLOSED
    console.log('Status:', status, message);
},
function(error) {
    console.error('Error:', error);
},
function(action, camera, data) {
    // Actions: PHOTO, PHOTO_SUCCESS, RECORD_START, RECORD_STOP, CAMERA_SWITCHED
    console.log('Action:', action, camera);
});

// Stop
RtspHlsPlayer.stop();
```

## How it works

```
Dashcam (RTSP) 
    ↓
FFmpegKit (conversion on iPhone)
    ↓
HLS files (/tmp/hls_stream/)
    ↓
GCDWebServer (localhost:8765)
    ↓
AVPlayer (native player)
```

## Latency

Because of HLS segmentation, the typical latency is ~3–5 seconds.

To reduce latency, change `hls_time` in `RtspHlsConverter.m`:

```objc
@"-hls_time 1 "  // 1 second instead of 2
```

## License

MIT
