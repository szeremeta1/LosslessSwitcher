//
//  ContentView.swift
//  Quality
//
//  Created by Vincent Neo on 18/4/22.
//

import SwiftUI
import OSLog
import SimplyCoreAudio

struct ContentView: View {
    @EnvironmentObject var outputDevices: OutputDevices
    
    var body: some View {
        VStack(spacing: 4) {
            if let currentSampleRate = outputDevices.currentSampleRate {
                HStack(spacing: 4) {
                    let formattedSampleRate = String(format: "%.1f kHz", currentSampleRate)
                    Text(formattedSampleRate)
                        .font(.system(size: 23, weight: .semibold, design: .default))
                    
                    if let bitDepth = outputDevices.currentBitDepth, bitDepth > 0 {
                        Text("/")
                            .font(.system(size: 18, weight: .regular, design: .default))
                            .foregroundColor(.secondary)
                        Text("\(bitDepth)-bit")
                            .font(.system(size: 18, weight: .medium, design: .default))
                    }
                }
            }
            if let device = outputDevices.selectedOutputDevice ?? outputDevices.defaultOutputDevice {
                Text(device.name)
                    .font(.system(size: 14.5, weight: .regular, design: .default))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}


