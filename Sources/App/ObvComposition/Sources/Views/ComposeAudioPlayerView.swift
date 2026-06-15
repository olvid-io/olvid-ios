/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
 *
 *  This file is part of Olvid for iOS.
 *
 *  Olvid is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU Affero General Public License, version 3,
 *  as published by the Free Software Foundation.
 *
 *  Olvid is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Affero General Public License for more details.
 *
 *  You should have received a copy of the GNU Affero General Public License
 *  along with Olvid.  If not, see <https://www.gnu.org/licenses/>.
 */

import SwiftUI
import AVFoundation

struct ComposeAudioPlayerView: View {
    
    private let sharedState: ComposeView.SharedState
    private let audioAttachment: ComposeAttachmentView.AttachmentIdentifier
    private let dataSource: ComposeAttachmentViewDataSource
    
    private let initialDataSourceViewModel: ComposeViewDataSourceFyleModel?
    @State private var streamedDataSourceViewModel: ComposeViewDataSourceFyleModel?
    private var dataSourceViewModel: ComposeViewDataSourceFyleModel? {
        streamedDataSourceViewModel ?? initialDataSourceViewModel
    }
    
    @State private var isPlaying: Bool = false
    
    @State private var currentTime: String = "00:00"
    
    @State private var progress: Float = 0.0
    
    @State private var samples: [Float] = []
    
    @MainActor
    @ObservedObject var audioPlayer = ComposeAudioPlayer.shared
    
    private let formatter = AudioDurationFormatter()
    
    @MainActor
    private class Coordinator: NSObject, @preconcurrency ObvAudioPlayerDelegate {
        @Binding var isPlaying: Bool
        @Binding var currentTime: String
        @Binding var progress: Float
        
        let audioPlayer = ComposeAudioPlayer.shared
        
        let audioURL: URL
        
        let formatter = AudioDurationFormatter()
        
        init(audioURL: URL,
             isPlaying: Binding<Bool>,
             currentTime: Binding<String>,
             progress: Binding<Float>) {
            self.audioURL = audioURL
            _isPlaying = isPlaying
            _currentTime = currentTime
            _progress = progress
        }
        
        func audioPlayerDidFinishPlaying() {
            refreshPlayPause()
        }
        
        func audioPlayerDidStopPlaying() {
            refreshPlayPause()
        }
        
        func audioPlayerDidPause() {
            refreshPlayPause()
        }
        
        private func refreshPlayPause() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let current = self.audioPlayer.currentURL
                if self.audioURL == current {
                    self.isPlaying = self.audioPlayer.isPlaying
                } else {
                    self.isPlaying = false
                }
            }
        }
        
        func audioIsPlaying(currentTime: TimeInterval) {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let current = self.audioPlayer.currentURL
                self.refreshPlayPause()
                if self.audioURL == current, let totalDuration = self.audioPlayer.totalDuration, totalDuration > 0 {
                    self.currentTime = self.formatter.string(from: currentTime) ?? "00:00"
                    self.progress = Float(currentTime / totalDuration)
                } else { // If audio file played is not the current one, we display the duration.
                    if let totalDuration = self.audioPlayer.totalDuration {
                        self.currentTime = self.formatter.string(from: totalDuration) ?? "00:00"
                    } else {
                        self.currentTime = "00:00"
                    }
                    self.progress = 0.0
                }
            }
        }
        
        func playerWillChangeCurrentFyle(previousAudioURL: URL?) {
            if previousAudioURL == self.audioURL {
                self.isPlaying = false
            }
        }
    }
    
    @State private var coordinator: Coordinator?
    
    var isConfiguredWithCurrentAudio: Bool {
        guard let currentAudioURL = ComposeAudioPlayer.shared.currentURL else { return false }
        return currentAudioURL == dataSourceViewModel?.audioURL
    }
    
    private enum GlassEffectID: String {
        case playButton
        case playingRateButton
    }
    
    init(viewModel: ComposeView.SharedState,
         audioAttachment: ComposeAttachmentView.AttachmentIdentifier,
         attachmentDataSource: ComposeAttachmentViewDataSource) {
        self.sharedState = viewModel
        self.audioAttachment = audioAttachment
        self.dataSource = attachmentDataSource
        
        if let initialDataSourceModel = dataSource.getInitialComposeViewDataSourceFyleModel(attachmentIdentifier: audioAttachment) {
            self.initialDataSourceViewModel = initialDataSourceModel
        } else {
            self.initialDataSourceViewModel = nil
        }
    }
    
    private func togglePlay() async throws {
        guard let audioURL = dataSourceViewModel?.audioURL else { return }
        
        if coordinator == nil {
            coordinator = Coordinator(audioURL: audioURL, isPlaying: $isPlaying, currentTime: $currentTime, progress: $progress)
        }
        
        audioPlayer.delegate = coordinator
        
        let duration = try await ComposeAudioPlayer.duration(of: audioURL)
        
        if progress > 0.98 { progress = 0 } // If progress is near the end we set it to the start of the audio
        let time = duration * TimeInterval(progress)
        
        guard isConfiguredWithCurrentAudio else {
            audioPlayer.stop()
            _ = audioPlayer.play(audioURL, at: time)
            self.isPlaying = true
            return
        }
        
        if audioPlayer.isPlaying {
            audioPlayer.pause()
            self.isPlaying = false
        } else {
            audioPlayer.resume(at: time)
            self.isPlaying = true
        }
    }
    
    var content: some View {
        
        HStack(alignment: .center, spacing: 0) {
            if let audioURL = dataSourceViewModel?.audioURL {
                AsyncButton {
                    try? await self.togglePlay()
                } label: {
                    Image(systemIcon: isPlaying ? .pauseFill : .playFill)
                }
                .padding(10.0)
                .glassButtonStyle(glassEffectID: GlassEffectID.playButton.rawValue)
               
                WaveFormView(audioURL: audioURL, progress: $progress, samples: $samples)
                    .padding(.leading, 8.0)
                
                VStack(alignment: .center, spacing: 8.0) {
                    Text(verbatim: currentTime)
                        .font(.caption)
                    
                    if let playRateTitle = audioPlayer.currentPlayRate.title {
                        Button {
                            audioPlayer.setRate(rate: audioPlayer.currentPlayRate.next)
                        } label: {
                            Text(verbatim: playRateTitle)
                                .font(.subheadline)
                        }
                        .padding(.horizontal, 10.0)
                        .padding(.vertical, 2.0)
                        .background(.quaternary.opacity(0.5))
                        .clipShape(Capsule())
                        .foregroundStyle(Color(uiColor: .label))
                    }
                }
                .frame(minWidth: 60.0)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    public var body: some View {
        content
            .task(onTaskForAsyncStreamOfComposeViewDataSourceFyleModel)
    }
}

extension ComposeAudioPlayerView {

    private func onTaskForAsyncStreamOfComposeViewDataSourceFyleModel() async {
        do {
            let (streamUUID, stream) = try await dataSource.getAsyncStreamOfComposeViewDataSourceFyleModel(attachmentIdentifier: audioAttachment)
            for await receivedDataSourceViewModel in stream {
                self.streamedDataSourceViewModel = receivedDataSourceViewModel
                Task {
                    if let audioURL = receivedDataSourceViewModel.audioURL, let totalDuration = try? await ComposeAudioPlayer.duration(of: audioURL) {
                        self.currentTime = self.formatter.string(from: totalDuration) ?? "00:00"
                    }
                }
            }
            dataSource.finishAsyncStreamOfComposeViewDataSourceFyleModel(streamUUID: streamUUID)
        } catch {
            assertionFailure()
        }
    }
    
}

private struct WaveFormView: View {
    
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 2
    
    var audioURL: URL?
    
    @Binding var progress: Float       // 0 = début, 1 = fin

    @Binding var samples: [Float]
    
    @State private var animatedSamples: [Float] = []
    
    @State private var isLoading: Bool = false
    
    @State var size: CGSize = .zero
    
    @State var totalNumberOfSamples: Int = 0
    
    @State private var isDragging = false
    
    @State private var shouldResume: Bool = false

    let audioPlayer = ComposeAudioPlayer.shared
    
    var body: some View {
        HStack(alignment: .center, spacing: 0.0) {
            if let audioURL {
                if samples.isEmpty && !isLoading && totalNumberOfSamples > 0 {
                    Color.clear
                        .frame(width: 0.0, height: 0.0)
                        .task {
                            await loadSamples(from: audioURL)
                        }
                }
                if samples.isEmpty {
                    ForEach(0..<totalNumberOfSamples, id: \.self) { _ in
                        Rectangle()
                            .frame(width: 3.0, height: 3.0)
                            .cornerRadius(3.0)
                            .opacity(0.3)
                            .padding(.horizontal, 1.0)
                    }
                } else {
                   ForEach(animatedSamples.indices, id: \.self) { idx in
                        let fill = (progress * Float(animatedSamples.count) - Float(idx)).clamped(to: 0...1)
                        let opacity = Double(0.3 + 0.7 * fill)
                        Rectangle()
                           .frame(width: barWidth, height: CGFloat(max(3.0, 48.0 * animatedSamples[idx])))
                           .cornerRadius(barWidth / 2.0)
                           .foregroundStyle(Color(uiColor: .label).opacity(opacity))
                           .padding(.horizontal, barSpacing / 2.0)
                    }
                }
            } else {
                ForEach(0..<totalNumberOfSamples, id: \.self) { _ in
                    Rectangle()
                        .frame(width: 3.0, height: 3.0)
                        .cornerRadius(3.0)
                        .opacity(0.3)
                        .padding(.horizontal, 1.0)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 60)
        .contentShape(Rectangle())
        .background(
            GeometryReader(content: { proxy in
                Color.clear
                    .onAppear {
                        size = proxy.size
                        totalNumberOfSamples = Int(proxy.size.width / (barWidth + barSpacing))
                    }
            })
        )
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        if audioURL == audioPlayer.currentURL {
                            self.shouldResume = audioPlayer.isPlaying
                            audioPlayer.pause()
                        }
                    }
                    let locationX = max(0, min(value.location.x, size.width))
                    let p = Float(locationX / size.width)
                    progress = p
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
        .onChange(of: isDragging) { newValue in
            guard let audioURL else { return }
            Task {
                guard audioURL == audioPlayer.currentURL else { return }
                let duration = (try? await ComposeAudioPlayer.duration(of: audioURL)) ?? 0.0
                if !newValue { // Dragging ended
                    let time = duration * TimeInterval(progress)
                    if shouldResume || audioPlayer.isPlaying {
                        audioPlayer.resume(at: time)
                    }
                }
            }
        }
        .onChange(of: samples) { newSamples in
            guard newSamples.count > 0 else { return }
            if newSamples.count != animatedSamples.count {
                animatedSamples = Array(repeating: 0.075, count: newSamples.count)
            }
            Task {
#if targetEnvironment(macCatalyst)
                let delay: UInt64 = 0
#else
                let delay: UInt64 = 500_000
#endif
                for i in newSamples.indices {
                    try? await Task.sleep(nanoseconds: UInt64(i) * delay) // small delay for staggered effect
                    withAnimation(.spring(response: 0.7, dampingFraction: 0.47, blendDuration: 0.25)) {
                        if animatedSamples.indices.contains(i) {
                            animatedSamples[i] = newSamples[i]
                        }
                    }
                }
            }
        }
    }

    private func loadSamples(from url: URL) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        if let cached = await WaveformSamplesCache.shared.get(url: url) {
            samples = cached
            return
        }
        let result = await Task.detached(priority: .background) {
            return await extractWaveformSamples(from: url, count: totalNumberOfSamples)
        }.value
        samples = result
        await WaveformSamplesCache.shared.set(samples: result, for: url)
    }
    
    func extractWaveformSamples(from url: URL, count: Int) async -> [Float] {
        let asset = AVAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else { return [] }
        let readerSettings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM,
                                             AVLinearPCMBitDepthKey: 32,
                                             AVLinearPCMIsBigEndianKey: false,
                                             AVLinearPCMIsFloatKey: true,
                                             AVLinearPCMIsNonInterleaved: false]
        do {
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: readerSettings)
            reader.add(output)
            reader.startReading()
            var sampleData = [Float]()
            while let buffer = output.copyNextSampleBuffer(),
                  let block = CMSampleBufferGetDataBuffer(buffer) {
                let length = CMBlockBufferGetDataLength(block)
                var data = Data(count: length)
                data.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
                    if let base = bytes.baseAddress {
                        CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: base)
                    }
                }
                // We requested 32-bit float interleaved samples, so bytesPerSample = 4.
                let bytesPerSample = 4
                // Ensure buffer is aligned to sample size to avoid out-of-bounds reads.
                guard length % bytesPerSample == 0 else {
                    CMSampleBufferInvalidate(buffer)
                    continue
                }
                let sampleCount = length / bytesPerSample
                // If the source has multiple channels and is interleaved, samples will be interleaved per channel.
                // For simplicity, treat data as mono; if multiple channels exist, averaging can be added later if needed.
                for i in 0..<sampleCount {
                    let sample: Float32 = data.withUnsafeBytes { $0.load(fromByteOffset: i * bytesPerSample, as: Float32.self) }
                    // Float PCM is typically normalized to [-1, 1]. Use absolute value for magnitude.
                    sampleData.append(abs(sample))
                }
                CMSampleBufferInvalidate(buffer)
            }
            let chunkSize = max(1, sampleData.count / count)
            var result = [Float]()
            for i in 0..<count {
                let start = i * chunkSize
                let end = min(sampleData.count, start + chunkSize)
                let maxVal = sampleData[start..<end].max() ?? 0
                result.append(maxVal)
            }
            let maxValue = result.max() ?? 1
            if maxValue > 0 {
                result = result.map { $0 / maxValue }
            }
            return result
        } catch {
            return []
        }
    }
}

// MARK: - Waveform samples cache singleton for reuse across WaveFormView instances
private actor WaveformSamplesCache {
    static let shared = WaveformSamplesCache()
    private var cache: [URL: [Float]] = [:]
    
    func get(url: URL) -> [Float]? {
        return cache[url]
    }
    
    func set(samples: [Float], for url: URL) {
        cache[url] = samples
    }
}

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}

