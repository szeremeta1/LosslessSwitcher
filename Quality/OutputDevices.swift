//
//  OutputDevices.swift
//  Quality
//
//  Created by Vincent Neo on 20/4/22.
//

import Combine
import Foundation
import SimplyCoreAudio
import CoreAudioTypes

class OutputDevices: ObservableObject {
    @Published var selectedOutputDevice: AudioDevice? // auto if nil
    @Published var defaultOutputDevice: AudioDevice?
    @Published var outputDevices = [AudioDevice]()
    @Published var currentSampleRate: Float64?
    @Published var currentBitDepth: UInt32?
    
    private var enableBitDepthDetection = Defaults.shared.userPreferBitDepthDetection
    private var enableBitDepthDetectionCancellable: AnyCancellable?
    
    private let coreAudio = SimplyCoreAudio()
    
    private var changesCancellable: AnyCancellable?
    private var defaultChangesCancellable: AnyCancellable?
    private var timerCancellable: AnyCancellable?
    private var outputSelectionCancellable: AnyCancellable?
    
    private var consoleQueue = DispatchQueue(label: "consoleQueue", qos: .userInteractive)
    
    private var previousSampleRate: Float64?
    var trackAndSample = [MediaTrack : Float64]()
    var previousTrack: MediaTrack?
    var currentTrack: MediaTrack?
    
    var timerActive = false
    var timerCalls = 0
    
    init() {
        self.outputDevices = self.coreAudio.allOutputDevices
        self.defaultOutputDevice = self.coreAudio.defaultOutputDevice
        self.getDeviceSampleRate()
        
        changesCancellable =
            NotificationCenter.default.publisher(for: .deviceListChanged).sink(receiveValue: { _ in
                self.outputDevices = self.coreAudio.allOutputDevices
            })
        
        defaultChangesCancellable =
            NotificationCenter.default.publisher(for: .defaultOutputDeviceChanged).sink(receiveValue: { _ in
                self.defaultOutputDevice = self.coreAudio.defaultOutputDevice
                self.getDeviceSampleRate()
            })
        
        outputSelectionCancellable = selectedOutputDevice.publisher.sink(receiveValue: { _ in
            self.getDeviceSampleRate()
        })
        
        enableBitDepthDetectionCancellable = Defaults.shared.$userPreferBitDepthDetection.sink(receiveValue: { newValue in
            self.enableBitDepthDetection = newValue
        })

        
    }
    
    deinit {
        changesCancellable?.cancel()
        defaultChangesCancellable?.cancel()
        timerCancellable?.cancel()
        enableBitDepthDetectionCancellable?.cancel()
        //timer.upstream.connect().cancel()
    }
    
    func renewTimer() {
        if timerCancellable != nil { return }
        timerCancellable = Timer
            .publish(every: 2, on: .main, in: .default)
            .autoconnect()
            .sink { _ in
                if self.timerCalls == 5 {
                    self.timerCalls = 0
                    self.timerCancellable?.cancel()
                    self.timerCancellable = nil
                }
                else {
                    self.timerCalls += 1
                    self.consoleQueue.async {
                        self.switchLatestSampleRate()
                    }
                }
            }
    }
    
    func getDeviceSampleRate() {
        let defaultDevice = self.selectedOutputDevice ?? self.defaultOutputDevice
        guard let sampleRate = defaultDevice?.nominalSampleRate else { return }
        self.updateSampleRate(sampleRate)
    }
    
    func getSampleRateFromAppleScript() -> Double? {
        let scriptContents = "tell application \"Music\" to get sample rate of current track"
        var error: NSDictionary?
        
        if let script = NSAppleScript(source: scriptContents) {
            let output = script.executeAndReturnError(&error).stringValue
            
            if let error = error {
                print("[APPLESCRIPT] - \(error)")
            }
            guard let output = output else { return nil }

            if output == "missing value" {
                return nil
            }
            else {
                return Double(output)
            }
        }
        
        return nil
    }
    
    func getAllStats() -> [CMPlayerStats] {
        var allStats = [CMPlayerStats]()
        
        do {
            let musicLogs = try Console.getRecentEntries(type: .music)
            let coreAudioLogs = try Console.getRecentEntries(type: .coreAudio)
            let coreMediaLogs = try Console.getRecentEntries(type: .coreMedia)
            
            // Use the new combined parser that handles all sources
            allStats = CMPlayerParser.parseAllSources(
                musicLogs: musicLogs,
                coreAudioLogs: coreAudioLogs,
                coreMediaLogs: coreMediaLogs,
                enableBitDepthDetection: enableBitDepthDetection
            )
            
            print("[getAllStats] Found \(allStats.count) stats: \(allStats)")
        }
        catch {
            print("[getAllStats, error] \(error)")
        }
        
        return allStats
    }
    
    func switchLatestSampleRate(recursion: Bool = false) {
        let allStats = self.getAllStats()
        let defaultDevice = self.selectedOutputDevice ?? self.defaultOutputDevice
        
        guard let device = defaultDevice else {
            print("[switchLatestSampleRate] No output device available")
            return
        }
        
        guard let supported = device.nominalSampleRates, !supported.isEmpty else {
            print("[switchLatestSampleRate] Device has no supported sample rates")
            return
        }
        
        if let first = allStats.first {
            let sampleRate = Float64(first.sampleRate)
            let bitDepth = Int32(first.bitDepth)
            
            print("[switchLatestSampleRate] Best stat: \(first), Target: \(sampleRate) Hz, \(bitDepth)-bit")
            
            if self.currentTrack == self.previousTrack, let prevSampleRate = currentSampleRate, prevSampleRate * 1000 > sampleRate {
                print("[switchLatestSampleRate] Same track, previous sample rate is higher - skipping")
                return
            }
            
            // Retry logic for 48kHz detection (often indicates pending real rate)
            if sampleRate == 48000 && !recursion {
                print("[switchLatestSampleRate] Detected 48kHz, retrying to get actual rate...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self.switchLatestSampleRate(recursion: true)
                }
                return
            }
            
            guard let formats = self.getFormats(bestStat: first, device: device), !formats.isEmpty else {
                print("[switchLatestSampleRate] No available formats for device")
                // Fall back to just setting sample rate without bit depth
                if let nearest = supported.min(by: { abs($0 - sampleRate) < abs($1 - sampleRate) }) {
                    print("[switchLatestSampleRate] Falling back to sample rate only: \(nearest) Hz")
                    if nearest != previousSampleRate {
                        device.setNominalSampleRate(nearest)
                    }
                    self.updateSampleRate(nearest)
                }
                return
            }
            
            // Find nearest supported sample rate
            guard let nearest = supported.min(by: { abs($0 - sampleRate) < abs($1 - sampleRate) }) else {
                print("[switchLatestSampleRate] Could not find nearest sample rate")
                return
            }
            
            print("[switchLatestSampleRate] Nearest supported sample rate: \(nearest) Hz")
            
            // Find formats matching the nearest sample rate
            let formatsAtSampleRate = formats.filter { $0.mSampleRate == nearest }
            
            if formatsAtSampleRate.isEmpty {
                print("[switchLatestSampleRate] No formats at target sample rate, using sample rate only")
                if nearest != previousSampleRate {
                    device.setNominalSampleRate(nearest)
                }
                self.updateSampleRate(nearest)
                return
            }
            
            // Find the best matching bit depth
            let nearestBitDepthFormat = formatsAtSampleRate.min(by: {
                abs(Int32($0.mBitsPerChannel) - bitDepth) < abs(Int32($1.mBitsPerChannel) - bitDepth)
            })
            
            // Find formats matching both sample rate and bit depth
            let nearestFormat = formatsAtSampleRate.filter {
                $0.mBitsPerChannel == nearestBitDepthFormat?.mBitsPerChannel
            }
            
            print("[switchLatestSampleRate] Matching formats: \(nearestFormat.map { "(\($0.mSampleRate)Hz, \($0.mBitsPerChannel)bit)" })")
            
            if let suitableFormat = nearestFormat.first {
                print("[switchLatestSampleRate] Selected format: \(suitableFormat.mSampleRate) Hz, \(suitableFormat.mBitsPerChannel)-bit")
                
                if enableBitDepthDetection {
                    self.setFormats(device: device, format: suitableFormat)
                }
                else if suitableFormat.mSampleRate != previousSampleRate {
                    device.setNominalSampleRate(suitableFormat.mSampleRate)
                }
                
                self.updateSampleRate(suitableFormat.mSampleRate, bitDepth: suitableFormat.mBitsPerChannel)
                
                if let currentTrack = currentTrack {
                    self.trackAndSample[currentTrack] = suitableFormat.mSampleRate
                }
            } else {
                print("[switchLatestSampleRate] No suitable format found, using sample rate only")
                if nearest != previousSampleRate {
                    device.setNominalSampleRate(nearest)
                }
                self.updateSampleRate(nearest, bitDepth: UInt32(bitDepth))
            }
        }
        else if !recursion {
            print("[switchLatestSampleRate] No stats found, retrying...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.switchLatestSampleRate(recursion: true)
            }
        }
        else {
            print("[switchLatestSampleRate] No stats found after retry")
            if self.currentTrack == self.previousTrack {
                print("[switchLatestSampleRate] Same track, ignoring cache")
                return
            }
        }
    }
    
    func getFormats(bestStat: CMPlayerStats, device: AudioDevice) -> [AudioStreamBasicDescription]? {
        // new sample rate + bit depth detection route
        let streams = device.streams(scope: .output)
        guard let availableFormats = streams?.first?.availablePhysicalFormats?.compactMap({ $0.mFormat }), !availableFormats.isEmpty else {
            print("[getFormats] No physical formats available for device: \(device.name)")
            return nil
        }
        print("[getFormats] Available formats for \(device.name): \(availableFormats.map { "(\($0.mSampleRate)Hz, \($0.mBitsPerChannel)bit)" })")
        return availableFormats
    }
    
    func setFormats(device: AudioDevice?, format: AudioStreamBasicDescription?) {
        guard let device = device, let format = format else {
            print("[setFormats] Device or format is nil")
            return
        }
        
        let streams = device.streams(scope: .output)
        guard let stream = streams?.first else {
            print("[setFormats] No output streams found for device: \(device.name)")
            return
        }
        
        let currentFormat = stream.physicalFormat
        
        // Check if we actually need to change the format
        if let current = currentFormat, current == format {
            print("[setFormats] Format already set to \(format.mSampleRate) Hz, \(format.mBitsPerChannel)-bit")
            return
        }
        
        print("[setFormats] Changing format from \(currentFormat?.mSampleRate ?? 0) Hz, \(currentFormat?.mBitsPerChannel ?? 0)-bit to \(format.mSampleRate) Hz, \(format.mBitsPerChannel)-bit")
        
        // Set the physical format
        stream.physicalFormat = format
        
        // Verify the change was applied
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let newFormat = stream.physicalFormat {
                if newFormat == format {
                    print("[setFormats] Format successfully changed to \(newFormat.mSampleRate) Hz, \(newFormat.mBitsPerChannel)-bit")
                } else {
                    print("[setFormats] Warning: Format change may not have been applied. Current: \(newFormat.mSampleRate) Hz, \(newFormat.mBitsPerChannel)-bit")
                }
            }
        }
    }
    
    func updateSampleRate(_ sampleRate: Float64, bitDepth: UInt32? = nil) {
        self.previousSampleRate = sampleRate
        DispatchQueue.main.async {
            let readableSampleRate = sampleRate / 1000
            self.currentSampleRate = readableSampleRate
            self.currentBitDepth = bitDepth
            
            let delegate = AppDelegate.instance
            
            // Format the display string with bit depth if available
            var displayString: String
            if let bitDepth = bitDepth, bitDepth > 0 {
                displayString = String(format: "%.1f kHz / %d-bit", readableSampleRate, bitDepth)
            } else {
                displayString = String(format: "%.1f kHz", readableSampleRate)
            }
            
            delegate?.statusItemTitle = displayString
            print("[updateSampleRate] Updated display: \(displayString)")
        }
        self.runUserScript(sampleRate, bitDepth: bitDepth)
    }
    
    func runUserScript(_ sampleRate: Float64, bitDepth: UInt32? = nil) {
        guard let scriptPath = Defaults.shared.shellScriptPath else { return }
        let argumentSampleRate = String(Int(sampleRate))
        let argumentBitDepth = String(bitDepth ?? 0)
        Task.detached {
            let scriptURL = URL(fileURLWithPath: scriptPath)
            do {
                let task = try NSUserUnixTask(url: scriptURL)
                let arguments = [
                    argumentSampleRate,
                    argumentBitDepth
                ]
                try await task.execute(withArguments: arguments)
                print("[runUserScript] Script executed with args: \(arguments)")
            }
            catch {
                print("[runUserScript] Error: \(error)")
            }
        }
    }
}
