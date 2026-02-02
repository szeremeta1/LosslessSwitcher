//
//  MediaTrack.swift
//  LosslessSwitcher
//
//  Created by Vincent Neo on 1/5/22.
//

import Foundation
import PrivateMediaRemote

struct MediaTrack: Equatable, Hashable, CustomStringConvertible {
    
    let isMusicApp: Bool
    let id: String?
    let bundleIdentifier: String?
    
    let title: String?
    let album: String?
    let artist: String?
    let trackNumber: String?
    let duration: TimeInterval?
    
    var description: String {
        return "MediaTrack(title: \(title ?? "nil"), artist: \(artist ?? "nil"), album: \(album ?? "nil"), bundle: \(bundleIdentifier ?? "nil"))"
    }
    
    init(mediaRemote info: [String : Any]) {
        self.id = info[kMRMediaRemoteNowPlayingInfoUniqueIdentifier] as? String
        self.isMusicApp = info[kMRMediaRemoteNowPlayingInfoIsMusicApp] as? Bool ?? false
        self.title = info[kMRMediaRemoteNowPlayingInfoTitle] as? String
        self.album = info[kMRMediaRemoteNowPlayingInfoAlbum] as? String
        self.artist = info[kMRMediaRemoteNowPlayingInfoArtist] as? String
        self.trackNumber = info[kMRMediaRemoteNowPlayingInfoTrackNumber] as? String
        self.duration = info[kMRMediaRemoteNowPlayingInfoDuration] as? TimeInterval
        self.bundleIdentifier = info["kMRMediaRemoteNowPlayingInfoClientBundleIdentifier"] as? String
    }
    
    /// Checks if this track is from a supported lossless audio application
    var isFromSupportedApp: Bool {
        return isMusicApp || bundleIdentifier != nil
    }
    
    // Custom equality to handle cases where id might be nil but content is same
    static func == (lhs: MediaTrack, rhs: MediaTrack) -> Bool {
        // If both have IDs, compare by ID
        if let lhsId = lhs.id, let rhsId = rhs.id {
            return lhsId == rhsId
        }
        // Otherwise compare by content
        return lhs.title == rhs.title &&
               lhs.album == rhs.album &&
               lhs.artist == rhs.artist &&
               lhs.trackNumber == rhs.trackNumber
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(title)
        hasher.combine(album)
        hasher.combine(artist)
    }
}
