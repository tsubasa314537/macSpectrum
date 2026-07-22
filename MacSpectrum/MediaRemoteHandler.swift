//
//  MediaRemoteHandler.swift
//  MacSpectrum
//
//  Created by 郭鹏 on 2026/4/19.
//

import MediaPlayer

class MediaRemoteHandler {
    
    var onPrevious:  (() -> Void)?
    var onPlayPause: (() -> Void)?
    var onNext:      (() -> Void)?
    
    init() {
        let center = MPRemoteCommandCenter.shared()
        
        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.onPrevious?()
            return .success
        }
        
        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.onPlayPause?()
            return .success
        }
        
        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.onNext?()
            return .success
        }
    }
    
    deinit {
        let center = MPRemoteCommandCenter.shared()
        center.previousTrackCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
    }
}
