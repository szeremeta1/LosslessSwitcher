# Improved Audio Format Detection and Reliability

This PR significantly improves the reliability of detecting and setting audio sample rate and bit depth from Apple Music, Safari, and other audio applications on the DAC.

## Problem

The app was failing to correctly read bitrate and kHz (e.g., 24-bit, 192kHz) from Apple Music and other applications like Safari, and was not reliably setting these values on the DAC.

## Root Causes Identified

1. **Too short time window** - Console log capture used only 3 seconds, missing log entries
2. **Music app only** - Log filtering only targeted the Music process, ignoring Safari and other apps
3. **Limited parsing patterns** - Log message formats vary between macOS versions and apps
4. **Force unwrap crashes** - Potential crashes when device was nil
5. **Race conditions** - Multiple async operations without proper synchronization
6. **No validation** - Invalid parsed values could be used

## Changes Made

### 1. Console.swift - Improved Log Capture

**Extended time window** from 3 seconds to 10 seconds for more reliable log capture:
```swift
private static let timeWindowSeconds: Double = -10.0
```

**Added support for multiple audio applications**:
```swift
static let supportedProcesses = ["Music", "Safari", "Chromium", "Google Chrome", "Firefox", 
    "Brave Browser", "Microsoft Edge", "Arc", "Spotify", "Audirvana", "VLC", "Tidal", 
    "Qobuz", "Roon", "Plexamp", "Swinsian"]
```

**Improved predicate filtering** - For CoreAudio/CoreMedia subsystems, accept logs from any audio-related process, not just Music.

**Added process name tracking** to identify which app is producing audio.

**Added `getAllAudioEntries()` method** to combine logs from all audio subsystems sorted by date.

---

### 2. CMPlayerStuff.swift - Enhanced Pattern Matching

**Added validation** for parsed stats to ensure values are within valid ranges:
```swift
var isValid: Bool {
    let validSampleRate = sampleRate >= 8000 && sampleRate <= 768000
    let validBitDepth = bitDepth >= 8 && bitDepth <= 64
    return validSampleRate && validBitDepth
}
```

**Added source tracking** to identify where each stat came from (Music, CoreAudio, CoreMedia).

**Extended time difference acceptance** from 5 seconds to 10 seconds.

**Added multiple parsing patterns for different log message formats**:

- **Music app patterns**:
  - `asbdSampleRate = X kHz`
  - `sampleRate: X` (raw Hz)
  - `sdBitDepth = X bit`
  - `bitDepth: X`
  - `X-bit` anywhere in message
  - `sdBitRate` / `lossy` indicators

- **CoreAudio patterns**:
  - Apple Lossless Decoder format (`ACAppleLosslessDecoder`)
  - FLAC Decoder format (`ACFLACDecoder`)
  - AudioStreamBasicDescription (ASBD) format
  - AudioConverter format

- **CoreMedia patterns**:
  - Creating AudioQueue
  - CMFormatDescription
  - AudioFormatDescription

**Added combined `parseAllSources()` method** for comprehensive parsing with proper priority sorting.

---

### 3. OutputDevices.swift - Better Format Switching

**Added `currentBitDepth` property** for UI display:
```swift
@Published var currentBitDepth: UInt32?
```

**Fixed force unwrap crash** - Replaced `defaultDevice!` with proper guard statements:
```swift
guard let device = defaultDevice else {
    print("[switchLatestSampleRate] No output device available")
    return
}
```

**Added comprehensive error handling** throughout `switchLatestSampleRate()`:
- Check for nil device
- Check for empty supported sample rates
- Check for empty available formats
- Fallback logic when format matching fails

**Improved format matching algorithm**:
- First find formats at the nearest supported sample rate
- Then find the best matching bit depth within those formats
- Fallback to sample rate only if no full format match

**Enhanced logging** for easier debugging:
```swift
print("[switchLatestSampleRate] Best stat: \(first), Target: \(sampleRate) Hz, \(bitDepth)-bit")
print("[switchLatestSampleRate] Selected format: \(suitableFormat.mSampleRate) Hz, \(suitableFormat.mBitsPerChannel)-bit")
```

**Updated `updateSampleRate()` to display bit depth** in status bar:
```swift
if let bitDepth = bitDepth, bitDepth > 0 {
    displayString = String(format: "%.1f kHz / %d-bit", readableSampleRate, bitDepth)
}
```

**Updated `runUserScript()` to pass bit depth** as second argument for custom scripts.

**Improved `setFormats()` with verification** - Confirms the format change was actually applied.

---

### 4. MediaRemoteController.swift - Improved Notification Handling

**Added listener for app change notifications**:
```swift
playingAppChangedCancellable = NotificationCenter.default
    .publisher(for: NSNotification.Name.mrMediaRemoteNowPlayingApplicationDidChange)
    .throttle(for: .seconds(0.5), scheduler: DispatchQueue.main, latest: true)
    .sink(receiveValue: { [weak self] notification in
        self?.handleInfoChanged()
    })
```

**Reduced throttle time** from 1 second to 0.5 seconds for faster response.

**Added rate limiting** to prevent excessive processing:
```swift
private var lastProcessedTime: Date?
private let processingInterval: TimeInterval = 0.5
```

**Used weak references** to prevent memory leaks:
```swift
.sink(receiveValue: { [weak self] notification in
    self?.handleInfoChanged()
})
```

**Added support for multiple audio app bundle identifiers**:
```swift
fileprivate let kSupportedAudioBundles = [
    "com.apple.Music", "com.apple.Safari", "com.spotify.client",
    "tv.plex.plexamp", "com.roon.Roon", "com.tidal.desktop", ...
]
```

---

### 5. MediaTrack.swift - Enhanced Track Info

**Added bundle identifier tracking**:
```swift
let bundleIdentifier: String?
```

**Added duration property** for additional context.

**Improved equality checking** to handle cases where ID might be nil:
```swift
static func == (lhs: MediaTrack, rhs: MediaTrack) -> Bool {
    if let lhsId = lhs.id, let rhsId = rhs.id {
        return lhsId == rhsId
    }
    return lhs.title == rhs.title && lhs.album == rhs.album && 
           lhs.artist == rhs.artist && lhs.trackNumber == rhs.trackNumber
}
```

**Added `CustomStringConvertible`** for better debugging output.

---

### 6. ContentView.swift - UI Improvements

**Added bit depth display** alongside sample rate:
```swift
if let bitDepth = outputDevices.currentBitDepth, bitDepth > 0 {
    Text("/")
        .font(.system(size: 18, weight: .regular, design: .default))
        .foregroundColor(.secondary)
    Text("\(bitDepth)-bit")
        .font(.system(size: 18, weight: .medium, design: .default))
}
```

**Improved layout** with proper spacing and padding.

**Added line limit** for long device names.

---

## Summary of Reliability Improvements

| Issue | Before | After |
|-------|--------|-------|
| Time window | 3 seconds | 10 seconds |
| Supported apps | Music only | Music, Safari, Chrome, Firefox, Spotify, Tidal, VLC, etc. |
| Parsing patterns | 2-3 per source | 6+ per source |
| Validation | None | Range validation (8kHz-768kHz, 8-64 bit) |
| Error handling | Force unwraps | Comprehensive guards |
| UI feedback | Sample rate only | Sample rate + bit depth |
| Script args | Sample rate only | Sample rate + bit depth |

## Testing

- [x] Build succeeds
- [ ] Test with Apple Music lossless content
- [ ] Test with Safari audio playback
- [ ] Test with various DACs
- [ ] Test format switching at different sample rates (44.1kHz, 48kHz, 96kHz, 192kHz)
- [ ] Test bit depth switching (16-bit, 24-bit, 32-bit)
