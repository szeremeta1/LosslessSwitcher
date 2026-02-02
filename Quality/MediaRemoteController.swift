//
//  MediaRemoteController.swift
//  LosslessSwitcher
//
//  Created by Vincent Neo on 1/5/22.
//

import Cocoa
import Combine
import PrivateMediaRemote

fileprivate let kMusicAppBundle = "com.apple.Music"

/// Supported audio application bundle identifiers
fileprivate let kSupportedAudioBundles = [
    "com.apple.Music",
    "com.apple.Safari",
    "com.spotify.client",
    "tv.plex.plexamp",
    "com.roon.Roon",
    "com.tidal.desktop",
    "com.qobuz.Qobuz",
    "com.audirvana.Audirvana-Plus",
    "com.audirvana.Audirvana-Origin",
    "org.videolan.vlc",
    "com.swinsian.Swinsian"
]

class MediaRemoteController {
    
    private var infoChangedCancellable: AnyCancellable?
    private var queueChangedCancellable: AnyCancellable?
    private var playingAppChangedCancellable: AnyCancellable?
    
    private weak var outputDevices: OutputDevices?
    private var lastProcessedTime: Date?
    private let processingInterval: TimeInterval = 0.5 // Minimum interval between processing
    
    init(outputDevices: OutputDevices) {
        self.outputDevices = outputDevices
        
        // Debounce notifications to avoid excessive processing
        infoChangedCancellable = NotificationCenter.default.publisher(for: NSNotification.Name.mrMediaRemoteNowPlayingInfoDidChange)
                .throttle(for: .seconds(0.5), scheduler: DispatchQueue.main, latest: true)
                .sink(receiveValue: { [weak self] notification in
                    self?.handleInfoChanged()
                })
        
        // Also listen for app changes
        playingAppChangedCancellable = NotificationCenter.default.publisher(for: NSNotification.Name.mrMediaRemoteNowPlayingApplicationDidChange)
                .throttle(for: .seconds(0.5), scheduler: DispatchQueue.main, latest: true)
                .sink(receiveValue: { [weak self] notification in
                    print("[MediaRemote] Now playing application changed")
                    self?.handleInfoChanged()
                })
        
        MRMediaRemoteRegisterForNowPlayingNotifications(.main)
        
        print("[MediaRemote] Initialized and listening for notifications")
    }
    
    private func handleInfoChanged() {
        // Prevent processing too frequently
        let now = Date()
        if let lastTime = lastProcessedTime, now.timeIntervalSince(lastTime) < processingInterval {
            return
        }
        lastProcessedTime = now
        
        print("[MediaRemote] Info Changed Notification Received")
        
        MRMediaRemoteGetNowPlayingInfo(.main) { [weak self] info in
            guard let self = self, let outputDevices = self.outputDevices else { return }
            
            if let info = info as? [String : Any] {
                let currentTrack = MediaTrack(mediaRemote: info)
                
                // Log detected info for debugging
                if let title = currentTrack.title {
                    print("[MediaRemote] Current track: \(title) by \(currentTrack.artist ?? "Unknown")")
                }
                
                // Use a shorter delay for faster response
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let previousTrack = outputDevices.currentTrack
                    outputDevices.previousTrack = previousTrack
                    outputDevices.currentTrack = currentTrack
                    
                    let trackChanged = previousTrack != currentTrack
                    print("[MediaRemote] Track changed: \(trackChanged), Current: \(currentTrack.title ?? "nil"), Previous: \(previousTrack?.title ?? "nil")")
                    
                    if trackChanged {
                        outputDevices.renewTimer()
                    }
                    
                    // Always try to switch sample rate when info changes
                    outputDevices.switchLatestSampleRate()
                }
            } else {
                print("[MediaRemote] Could not parse now playing info")
            }
        }
    }
    
    func send(command: MRMediaRemoteCommand, ifBundleMatches bundleId: String, completion: @escaping () -> ()) {
        MRMediaRemoteGetNowPlayingClient(.main) { client in
            guard let client = client else {
                print("[MediaRemote] No client available")
                completion()
                return
            }
            
            print("[MediaRemote] Current client bundle: \(client.bundleIdentifier ?? "unknown")")
            
            if client.bundleIdentifier == bundleId {
                MRMediaRemoteSendCommand(command, nil)
            }
            completion()
        }
    }
    
    /// Get the currently playing application's bundle identifier
    func getCurrentPlayingApp(completion: @escaping (String?) -> Void) {
        MRMediaRemoteGetNowPlayingClient(.main) { client in
            completion(client?.bundleIdentifier)
        }
    }
}
