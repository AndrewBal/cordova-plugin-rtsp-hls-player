# cordova-plugin-rtsp-hls-player

RTSP to HLS streaming player for iOS using FFmpegKit and native AVPlayer.

## Почему этот плагин?

MobileVLCKit имеет хроническую проблему на iOS 14+:
```
Unable to determine our source address: This computer has an invalid IP address: 0.0.0.0
```

Этот плагин решает проблему через конвертацию RTSP → HLS с помощью FFmpeg.

## Структура плагина

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

## Установка

### 1. Добавьте плагин

```bash
cordova plugin add /path/to/cordova-plugin-rtsp-hls-player
```

### 2. Обновите Podfile

В `platforms/ios/Podfile` добавьте зависимости:

```ruby
platform :ios, '14.0'
use_frameworks!

target 'YourApp' do
  # FFmpegKit (community fork - оригинальный закрыт)
  pod 'ffmpeg-kit-ios-full', :podspec => 'https://raw.githubusercontent.com/luthviar/ffmpeg-kit-ios-full/main/ffmpeg-kit-ios-full.podspec'
  
  # Локальный HTTP сервер для HLS
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

### 3. Установите pods

```bash
cd platforms/ios
pod install
```

### 4. Откройте .xcworkspace

```bash
open YourApp.xcworkspace
```

**ВАЖНО**: Открывайте `.xcworkspace`, НЕ `.xcodeproj`!

## Использование

```javascript
// Проверка доступности FFmpeg
RtspHlsPlayer.checkAvailability(function(available) {
    console.log('FFmpeg available:', available);
});

// Запуск стрима
RtspHlsPlayer.play({
    frontUrl: 'rtsp://192.168.0.1:554/livestream/1',
    rearUrl: 'rtsp://192.168.0.1:554/livestream/2',  // опционально
    title: 'Dashcam Live',
    apiBaseUrl: 'http://192.168.0.1'
}, 
function(status, message) {
    // Статусы: STARTING, CONVERTING, HLS_READY, BUFFERING, PLAYING, CLOSED
    console.log('Status:', status, message);
},
function(error) {
    console.error('Error:', error);
},
function(action, camera, data) {
    // Действия: PHOTO, PHOTO_SUCCESS, RECORD_START, RECORD_STOP, CAMERA_SWITCHED
    console.log('Action:', action, camera);
});

// Остановка
RtspHlsPlayer.stop();
```

## Как работает

```
Dashcam (RTSP) 
    ↓
FFmpegKit (конвертация на iPhone)
    ↓
HLS файлы (/tmp/hls_stream/)
    ↓
GCDWebServer (localhost:8765)
    ↓
AVPlayer (нативный плеер)
```

## Задержка

Из-за HLS сегментации задержка составляет ~3-5 секунд.

Для уменьшения задержки можно изменить `hls_time` в RtspHlsConverter.m:
```objc
@"-hls_time 1 "  // 1 секунда вместо 2
```

## Лицензия

MIT
