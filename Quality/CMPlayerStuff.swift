//
//  CMPlayerStats.swift
//  Quality
//
//  Created by Vincent Neo on 19/4/22.
//

import Foundation
import OSLog
import Sweep

struct CMPlayerStats: CustomStringConvertible {
    let sampleRate: Double // Hz
    let bitDepth: Int
    let date: Date
    let priority: Int
    let source: String // Source of the detection (for debugging)
    
    var description: String {
        return "CMPlayerStats(sampleRate: \(sampleRate) Hz, bitDepth: \(bitDepth)-bit, priority: \(priority), source: \(source))"
    }
    
    /// Validates the stats are within reasonable audio ranges
    var isValid: Bool {
        // Valid sample rates: 8kHz to 768kHz (covers all known formats)
        let validSampleRate = sampleRate >= 8000 && sampleRate <= 768000
        // Valid bit depths: 8 to 64 bits
        let validBitDepth = bitDepth >= 8 && bitDepth <= 64
        return validSampleRate && validBitDepth
    }
}

class CMPlayerParser {
    /// Time window to accept related log entries (in seconds)
    private static let kTimeDifferenceAcceptance = 10.0
    
    static func parseMusicConsoleLogs(_ entries: [SimpleConsole]) -> [CMPlayerStats] {
        var lastDate: Date?
        var sampleRate: Double?
        var bitDepth: Int?
        
        var stats = [CMPlayerStats]()
        
        for entry in entries {
            // ignore useless log messages for faster switching
            if !entry.message.contains("audioCapabilities:") {
                continue
            }
            
            let date = entry.date
            let rawMessage = entry.message
            
            if let lastDate = lastDate, date.timeIntervalSince(lastDate) > kTimeDifferenceAcceptance {
                sampleRate = nil
                bitDepth = nil
            }
            
            // Try multiple patterns for sample rate detection
            if sampleRate == nil {
                // Pattern 1: "asbdSampleRate = X kHz"
                if let subSampleRate = rawMessage.firstSubstring(between: "asbdSampleRate = ", and: " kHz") {
                    let strSampleRate = String(subSampleRate).trimmingCharacters(in: .whitespaces)
                    sampleRate = Double(strSampleRate)
                }
                // Pattern 2: "sampleRate: X" (raw Hz)
                else if let subSampleRate = rawMessage.firstSubstring(between: "sampleRate: ", and: ",") {
                    let strSampleRate = String(subSampleRate).trimmingCharacters(in: .whitespaces)
                    if let sr = Double(strSampleRate), sr > 1000 { // Likely in Hz if > 1000
                        sampleRate = sr / 1000 // Convert to kHz for consistency
                    }
                }
            }
            
            // Try multiple patterns for bit depth detection
            if bitDepth == nil {
                // Pattern 1: "sdBitDepth = X bit"
                if let subBitDepth = rawMessage.firstSubstring(between: "sdBitDepth = ", and: " bit") {
                    let strBitDepth = String(subBitDepth).trimmingCharacters(in: .whitespaces)
                    bitDepth = Int(strBitDepth)
                }
                // Pattern 2: "bitDepth: X"
                else if let subBitDepth = rawMessage.firstSubstring(between: "bitDepth: ", and: ",") {
                    let strBitDepth = String(subBitDepth).trimmingCharacters(in: .whitespaces)
                    bitDepth = Int(strBitDepth)
                }
                // Pattern 3: "X-bit" anywhere in the message
                else if let subBitDepth = rawMessage.firstSubstring(between: " ", and: "-bit") {
                    // Find the number right before "-bit"
                    let components = String(subBitDepth).split(separator: " ")
                    if let lastComponent = components.last, let bd = Int(lastComponent) {
                        bitDepth = bd
                    }
                }
                // Pattern 4: Lossy content indicator
                else if rawMessage.contains("sdBitRate") || rawMessage.contains("lossy") {
                    bitDepth = 16
                }
            }
            
            if let sr = sampleRate, let bd = bitDepth {
                let stat = CMPlayerStats(sampleRate: sr * 1000, bitDepth: bd, date: date, priority: 1, source: "Music")
                if stat.isValid {
                    stats.append(stat)
                    print("[CMPlayerParser] Detected from Music: \(stat)")
                } else {
                    print("[CMPlayerParser] Invalid stat detected from Music: \(stat)")
                }
                sampleRate = nil
                bitDepth = nil
                break
            }
            
            lastDate = date
        }
        return stats
    }
    
    static func parseCoreAudioConsoleLogs(_ entries: [SimpleConsole]) -> [CMPlayerStats] {
        var lastDate: Date?
        var sampleRate: Double?
        var bitDepth: Int?
        
        var stats = [CMPlayerStats]()
        
        for entry in entries {
            let date = entry.date
            let rawMessage = entry.message
            
            if let lastDate = lastDate, date.timeIntervalSince(lastDate) > kTimeDifferenceAcceptance {
                sampleRate = nil
                bitDepth = nil
            }
            
            // Pattern 1: Apple Lossless Decoder format
            if rawMessage.contains("ACAppleLosslessDecoder") && rawMessage.contains("Input format:") {
                if let subSampleRate = rawMessage.firstSubstring(between: "ch, ", and: " Hz") {
                    let strSampleRate = String(subSampleRate).trimmingCharacters(in: .whitespaces)
                    sampleRate = Double(strSampleRate)
                }
                
                if let subBitDepth = rawMessage.firstSubstring(between: "from ", and: "-bit source") {
                    let strBitDepth = String(subBitDepth).trimmingCharacters(in: .whitespaces)
                    bitDepth = Int(strBitDepth)
                }
            }
            
            // Pattern 2: FLAC Decoder format
            if rawMessage.contains("ACFLACDecoder") || rawMessage.contains("FLAC") {
                // Try to extract sample rate
                if sampleRate == nil, let subSampleRate = rawMessage.firstSubstring(between: "ch, ", and: " Hz") {
                    let strSampleRate = String(subSampleRate).trimmingCharacters(in: .whitespaces)
                    sampleRate = Double(strSampleRate)
                }
                if sampleRate == nil, let subSampleRate = rawMessage.firstSubstring(between: "@", and: "Hz") {
                    let strSampleRate = String(subSampleRate).trimmingCharacters(in: .whitespaces)
                    sampleRate = Double(strSampleRate)
                }
                
                // Try to extract bit depth
                if bitDepth == nil, let subBitDepth = rawMessage.firstSubstring(between: "from ", and: "-bit") {
                    let strBitDepth = String(subBitDepth).trimmingCharacters(in: .whitespaces)
                    bitDepth = Int(strBitDepth)
                }
                if bitDepth == nil, let subBitDepth = rawMessage.firstSubstring(between: " ", and: " bit") {
                    let components = String(subBitDepth).split(separator: " ")
                    if let lastComponent = components.last, let bd = Int(lastComponent) {
                        bitDepth = bd
                    }
                }
            }
            
            // Pattern 3: Generic audio format log (handles Safari, etc.)
            if rawMessage.contains("AudioStreamBasicDescription") || rawMessage.contains("ASBD") {
                // Sample rate patterns
                if sampleRate == nil {
                    if let subSampleRate = rawMessage.firstSubstring(between: "mSampleRate=", and: ",") {
                        let strSampleRate = String(subSampleRate).trimmingCharacters(in: .whitespaces)
                        sampleRate = Double(strSampleRate)
                    } else if let subSampleRate = rawMessage.firstSubstring(between: "mSampleRate: ", and: ",") {
                        let strSampleRate = String(subSampleRate).trimmingCharacters(in: .whitespaces)
                        sampleRate = Double(strSampleRate)
                    }
                }
                
                // Bit depth patterns
                if bitDepth == nil {
                    if let subBitDepth = rawMessage.firstSubstring(between: "mBitsPerChannel=", and: ",") {
                        let strBitDepth = String(subBitDepth).trimmingCharacters(in: .whitespaces)
                        bitDepth = Int(strBitDepth)
                    } else if let subBitDepth = rawMessage.firstSubstring(between: "mBitsPerChannel: ", and: ",") {
                        let strBitDepth = String(subBitDepth).trimmingCharacters(in: .whitespaces)
                        bitDepth = Int(strBitDepth)
                    }
                }
            }
            
            // Pattern 4: AudioConverter format
            if rawMessage.contains("AudioConverter") || rawMessage.contains("kAudioFormat") {
                if sampleRate == nil, let subSampleRate = rawMessage.firstSubstring(between: "sampleRate:", and: " ") {
                    let strSampleRate = String(subSampleRate).trimmingCharacters(in: .whitespaces)
                    sampleRate = Double(strSampleRate)
                }
                if bitDepth == nil, let subBitDepth = rawMessage.firstSubstring(between: "bits:", and: " ") {
                    let strBitDepth = String(subBitDepth).trimmingCharacters(in: .whitespaces)
                    bitDepth = Int(strBitDepth)
                }
            }
            
            if let sr = sampleRate, let bd = bitDepth {
                let stat = CMPlayerStats(sampleRate: sr, bitDepth: bd, date: date, priority: 5, source: "CoreAudio:\(entry.process)")
                if stat.isValid {
                    stats.append(stat)
                    print("[CMPlayerParser] Detected from CoreAudio: \(stat)")
                } else {
                    print("[CMPlayerParser] Invalid stat detected from CoreAudio: \(stat)")
                }
                sampleRate = nil
                bitDepth = nil
                break
            }
            
            lastDate = date
        }
        return stats
    }
    
    static func parseCoreMediaConsoleLogs(_ entries: [SimpleConsole]) -> [CMPlayerStats] {
        var lastDate: Date?
        var sampleRate: Double?
        var bitDepth: Int? = nil
        
        var stats = [CMPlayerStats]()
        
        for entry in entries {
            let date = entry.date
            let rawMessage = entry.message
            
            if let lastDate = lastDate, date.timeIntervalSince(lastDate) > kTimeDifferenceAcceptance {
                sampleRate = nil
                bitDepth = nil
            }
            
            // Pattern 1: Creating AudioQueue
            if rawMessage.contains("Creating AudioQueue") || rawMessage.contains("AudioQueue") {
                if sampleRate == nil {
                    // Try various patterns
                    if let subSampleRate = rawMessage.firstSubstring(between: "sampleRate:", and: .end) {
                        var strSampleRate = String(subSampleRate).trimmingCharacters(in: .whitespaces)
                        // Remove trailing non-numeric characters
                        strSampleRate = strSampleRate.components(separatedBy: CharacterSet.decimalDigits.inverted.subtracting(CharacterSet(charactersIn: "."))).joined()
                        sampleRate = Double(strSampleRate)
                    }
                    else if let subSampleRate = rawMessage.firstSubstring(between: "sampleRate: ", and: ",") {
                        let strSampleRate = String(subSampleRate).trimmingCharacters(in: .whitespaces)
                        sampleRate = Double(strSampleRate)
                    }
                }
                
                // Try to get bit depth from CoreMedia too
                if bitDepth == nil {
                    if let subBitDepth = rawMessage.firstSubstring(between: "bits:", and: ",") {
                        let strBitDepth = String(subBitDepth).trimmingCharacters(in: .whitespaces)
                        bitDepth = Int(strBitDepth)
                    }
                    else if let subBitDepth = rawMessage.firstSubstring(between: "bitsPerChannel:", and: ",") {
                        let strBitDepth = String(subBitDepth).trimmingCharacters(in: .whitespaces)
                        bitDepth = Int(strBitDepth)
                    }
                }
            }
            
            // Pattern 2: Format description logs
            if rawMessage.contains("CMFormatDescription") || rawMessage.contains("AudioFormatDescription") {
                if sampleRate == nil, let subSampleRate = rawMessage.firstSubstring(between: "sampleRate:", and: ",") {
                    let strSampleRate = String(subSampleRate).trimmingCharacters(in: .whitespaces)
                    sampleRate = Double(strSampleRate)
                }
                if bitDepth == nil, let subBitDepth = rawMessage.firstSubstring(between: "bitsPerChannel:", and: ",") {
                    let strBitDepth = String(subBitDepth).trimmingCharacters(in: .whitespaces)
                    bitDepth = Int(strBitDepth)
                }
            }
            
            if let sr = sampleRate {
                // Default bit depth to 24 if not detected (common for lossless)
                let bd = bitDepth ?? 24
                let stat = CMPlayerStats(sampleRate: sr, bitDepth: bd, date: date, priority: 2, source: "CoreMedia:\(entry.process)")
                if stat.isValid {
                    stats.append(stat)
                    print("[CMPlayerParser] Detected from CoreMedia: \(stat)")
                } else {
                    print("[CMPlayerParser] Invalid stat detected from CoreMedia: \(stat)")
                }
                sampleRate = nil
                bitDepth = nil
                break
            }
            
            lastDate = date
        }
        return stats
    }
    
    /// Parse all available log sources and combine results
    static func parseAllSources(musicLogs: [SimpleConsole], coreAudioLogs: [SimpleConsole], coreMediaLogs: [SimpleConsole], enableBitDepthDetection: Bool) -> [CMPlayerStats] {
        var allStats = [CMPlayerStats]()
        
        // Parse Music app logs (highest reliability for Apple Music)
        allStats.append(contentsOf: parseMusicConsoleLogs(musicLogs))
        
        // Parse CoreAudio logs (includes Safari and other apps, has bit depth)
        if enableBitDepthDetection {
            allStats.append(contentsOf: parseCoreAudioConsoleLogs(coreAudioLogs))
        }
        
        // Parse CoreMedia logs (fallback, may not have bit depth)
        allStats.append(contentsOf: parseCoreMediaConsoleLogs(coreMediaLogs))
        
        // Sort by priority (higher = more reliable), then by date (most recent first)
        allStats.sort { stat1, stat2 in
            if stat1.priority != stat2.priority {
                return stat1.priority > stat2.priority
            }
            return stat1.date > stat2.date
        }
        
        // Filter out invalid stats
        allStats = allStats.filter { $0.isValid }
        
        return allStats
    }
}
