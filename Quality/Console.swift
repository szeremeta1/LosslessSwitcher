//
//  Console.swift
//  Quality
//
//  Created by Vincent Neo on 19/4/22.
//
// https://developer.apple.com/forums/thread/677068

import OSLog
import Cocoa

struct SimpleConsole {
    let date: Date
    let message: String
    let process: String
}

enum EntryType: String {
    case music = "com.apple.Music"
    case coreAudio = "com.apple.coreaudio"
    case coreMedia = "com.apple.coremedia"
    
    // Supported audio processes for detection
    static let supportedProcesses = ["Music", "Safari", "Chromium", "Google Chrome", "Firefox", "Brave Browser", "Microsoft Edge", "Arc", "Spotify", "Audirvana", "VLC", "Tidal", "Qobuz", "Roon", "Plexamp", "Swinsian"]
    
    var predicate: NSPredicate {
        // For music subsystem, only filter Music app; for CoreAudio/CoreMedia, accept all audio processes
        switch self {
        case .music:
            return NSPredicate(format: "(subsystem = %@) AND (process = %@)", argumentArray: [rawValue, "Music"])
        case .coreAudio, .coreMedia:
            // Accept logs from any audio-related process for CoreAudio/CoreMedia subsystems
            let processPredicates = EntryType.supportedProcesses.map { process in
                NSPredicate(format: "process = %@", process)
            }
            let anyProcessPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: processPredicates)
            let subsystemPredicate = NSPredicate(format: "subsystem = %@", rawValue)
            return NSCompoundPredicate(andPredicateWithSubpredicates: [subsystemPredicate, anyProcessPredicate])
        }
    }
}

class Console {
    /// Extended time window for more reliable log capture (10 seconds instead of 3)
    private static let timeWindowSeconds: Double = -10.0
    
    static func getRecentEntries(type: EntryType) throws -> [SimpleConsole] {
        var messages = [SimpleConsole]()
        let store = try OSLogStore.local()
        let duration = store.position(timeIntervalSinceEnd: timeWindowSeconds)
        let entries = try store.getEntries(with: [], at: duration, matching: type.predicate)
        // for some reason AnySequence to Array turns it into a empty array?
        for entry in entries {
            // Extract process name from the log entry if available
            var processName = "Unknown"
            if let logEntry = entry as? OSLogEntryLog {
                processName = logEntry.process
            }
            let consoleMessage = SimpleConsole(date: entry.date, message: entry.composedMessage, process: processName)
            messages.append(consoleMessage)
        }
        
        return messages.reversed()
    }
    
    /// Get entries from all audio-related subsystems combined, sorted by date
    static func getAllAudioEntries() throws -> [SimpleConsole] {
        var allMessages = [SimpleConsole]()
        
        // Try each entry type and combine results
        for entryType in [EntryType.music, EntryType.coreAudio, EntryType.coreMedia] {
            do {
                let entries = try getRecentEntries(type: entryType)
                allMessages.append(contentsOf: entries)
            } catch {
                print("[Console] Failed to get entries for \(entryType.rawValue): \(error)")
            }
        }
        
        // Sort by date (most recent first)
        return allMessages.sorted { $0.date > $1.date }
    }
}
