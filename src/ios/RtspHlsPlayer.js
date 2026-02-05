/**
 * RtspHlsPlayer - RTSP to HLS streaming player for iOS
 * 
 * Converts RTSP stream to HLS using FFmpeg and plays via native AVPlayer.
 * This approach avoids VLCKit issues with IP address detection on iOS.
 */

var exec = require('cordova/exec');

var RtspHlsPlayer = {
    
    /**
     * Start RTSP→HLS conversion and play in fullscreen player
     * 
     * @param {Object} options
     * @param {string} options.frontUrl - RTSP URL for front camera
     * @param {string} [options.rearUrl] - RTSP URL for rear camera
     * @param {string} [options.title] - Title to display
     * @param {string} [options.apiBaseUrl] - Base URL for camera API
     * @param {string} [options.initialCamera] - 'front' or 'rear'
     * @param {Function} statusCallback - Status updates
     * @param {Function} errorCallback - Errors
     * @param {Function} [actionCallback] - User actions
     */
    play: function(options, statusCallback, errorCallback, actionCallback) {
        var args = [{
            frontUrl: options.frontUrl || '',
            rearUrl: options.rearUrl || '',
            title: options.title || 'Live Stream',
            apiBaseUrl: options.apiBaseUrl || 'http://192.168.0.1',
            initialCamera: options.initialCamera || 'front'
        }];
        
        if (actionCallback) {
            RtspHlsPlayer._actionCallback = actionCallback;
        }
        
        exec(
            function(result) {
                if (result && result.type === 'action' && RtspHlsPlayer._actionCallback) {
                    RtspHlsPlayer._actionCallback(result.action, result.camera, result.data);
                } else if (result && result.type === 'status' && statusCallback) {
                    statusCallback(result.status, result.message);
                } else if (statusCallback) {
                    statusCallback(result);
                }
            },
            errorCallback,
            'RtspHlsPlayer',
            'play',
            args
        );
    },
    
    /**
     * Stop streaming and close player
     */
    stop: function(successCallback, errorCallback) {
        exec(successCallback, errorCallback, 'RtspHlsPlayer', 'stop', []);
    },
    
    /**
     * Check if FFmpeg is available
     */
    checkAvailability: function(callback) {
        exec(
            function(result) { callback(result && result.available); },
            function() { callback(false); },
            'RtspHlsPlayer',
            'checkAvailability',
            []
        );
    },
    
    /**
     * Get conversion statistics
     */
    getStats: function(callback) {
        exec(callback, function() { callback(null); }, 'RtspHlsPlayer', 'getStats', []);
    },
    
    _actionCallback: null
};

module.exports = RtspHlsPlayer;
