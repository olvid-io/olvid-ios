/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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

import Foundation
import SwiftUI
import AVFoundation
import ObvDesignSystem
import ObvUICoreData
import Speech

protocol AudioWaveFormViewDelegate: AnyObject {
    func audioHasBeenPlayed(_: HardLinkToFyle)
    func audioWaveFormShouldInvalidateCollectionLayout()
}

fileprivate extension AudioWaveFormView.Configuration {

    var canReadAudio: Bool {
        switch self {
        case .uploadableOrUploading, .complete:
            return true
        case .downloadable, .downloading, .completeButReadRequiresUserInteraction, .cancelledByServer, .downloadableSent, .downloadingSent:
            return false
        }
    }

    var tapToReadViewIsHidden: Bool {
        switch self {
        case .completeButReadRequiresUserInteraction:
            return false
        case .uploadableOrUploading, .downloadable, .downloading, .cancelledByServer, .complete, .downloadableSent, .downloadingSent:
            return true
        }
    }

    var messageObjectID: TypeSafeManagedObjectID<PersistedMessageReceived>? {
        switch self {
        case .completeButReadRequiresUserInteraction(messageObjectID: let messageObjectID, fileSize: _, uti: _):
            return messageObjectID
        case .uploadableOrUploading, .downloadable, .downloading, .cancelledByServer, .complete, .downloadableSent, .downloadingSent:
            return nil
        }
    }
    
    var duration: Double? {
        get async throws {
            switch self {
            case .complete(hardlink: let hardlink, _, _, _, _, _),
                    .uploadableOrUploading(hardlink: let hardlink, _, _, _, _, _):
                guard let url = hardlink?.hardlinkURL else { return nil }
                return try await ObvAudioPlayer.duration(of: url)
            case .downloadable, .downloading, .completeButReadRequiresUserInteraction, .cancelledByServer, .downloadableSent, .downloadingSent:
                return nil
            }
        }
    }

    var wasOpened: Bool? {
        switch self {
        case .complete(_, _, _, _, _, wasOpened: let wasOpened):
            return wasOpened
        case .uploadableOrUploading, .downloadable, .downloading, .completeButReadRequiresUserInteraction, .cancelledByServer, .downloadableSent, .downloadingSent:
            return nil
        }
    }
}

final class AudioWaveFormView: ViewForOlvidStack, ViewWithMaskedCorners, ViewWithExpirationIndicator, AudioWaveFormContentViewActions, ViewShowingHardLinks, UIViewWithTappableStuff {
    
    typealias Configuration = SingleAttachmentView.Configuration
    
    private var currentConfiguration: Configuration?
    
    private let bubble = BubbleView()
    let expirationIndicator = ExpirationIndicatorView()
    let expirationIndicatorSide: ExpirationIndicatorView.Side
    private let tapToReadView = TapToReadView(showText: false)
    private let fyleProgressView = FyleProgressView()
    
    private var hostingController: UIHostingController<AudioWaveFormContentView>?
    
    weak var delegate: AudioWaveFormViewDelegate?
    
    init(expirationIndicatorSide side: ExpirationIndicatorView.Side) {
        self.expirationIndicatorSide = side
        super.init(frame: .zero)
        setupInternalViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(_ newConfiguration: Configuration) {
        guard currentConfiguration != newConfiguration else { return }
        currentConfiguration = newConfiguration
        refresh()
    }
    
    var maskedCorner: UIRectCorner {
        get { bubble.maskedCorner }
        set { bubble.maskedCorner = newValue }
    }

    private func setupInternalViews() {
        addSubview(bubble)
        bubble.backgroundColor =  AppTheme.shared.colorScheme.newReceivedCellBackground
        bubble.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(expirationIndicator)
        expirationIndicator.translatesAutoresizingMaskIntoConstraints = false
        
        let viewModel = AudioWaveFormContentViewModel(isEnabled: false, hardlink: nil)
        let contentView = AudioWaveFormContentView(viewModel: viewModel, delegate: self.delegate, actions: self)

        let hostingController = UIHostingController(rootView: contentView)
        hostingController.sizingOptions = .intrinsicContentSize
        guard let hostingView = hostingController.view else { return }
        bubble.addSubview(hostingView)
        hostingView.backgroundColor = .clear
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        
        let verticalInset = MessageCellConstants.bubbleVerticalInset
        let horizontalInsets = MessageCellConstants.bubbleHorizontalInsets
        
        addSubview(tapToReadView)
        tapToReadView.translatesAutoresizingMaskIntoConstraints = false
        tapToReadView.tapToReadLabelTextColor = .label
        
        addSubview(fyleProgressView)
        fyleProgressView.translatesAutoresizingMaskIntoConstraints = false
        
        let constraints = [
            bubble.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            bubble.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            bubble.topAnchor.constraint(equalTo: self.topAnchor),
            bubble.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: horizontalInsets),
            hostingView.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -horizontalInsets),
            hostingView.topAnchor.constraint(equalTo: bubble.topAnchor, constant: verticalInset),
            hostingView.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -verticalInset),
            tapToReadView.centerXAnchor.constraint(equalTo: hostingView.centerXAnchor),
            tapToReadView.centerYAnchor.constraint(equalTo: hostingView.centerYAnchor),
            fyleProgressView.leadingAnchor.constraint(equalTo: hostingView.leadingAnchor),
            fyleProgressView.centerYAnchor.constraint(equalTo: hostingView.centerYAnchor),
        ]
        
        constraints.forEach { $0.priority -= 1 }
        NSLayoutConstraint.activate(constraints)
        
        setupConstraintsForExpirationIndicator(gap: MessageCellConstants.gapBetweenExpirationViewAndBubble)
        
        self.hostingController = hostingController
        
        let sizeConstraints = [
            tapToReadView.widthAnchor.constraint(equalToConstant: MessageCellConstants.attachmentIconSize),
            tapToReadView.heightAnchor.constraint(equalToConstant: MessageCellConstants.attachmentIconSize),
        ]

        sizeConstraints.forEach { $0.priority -= 1 }
        NSLayoutConstraint.activate(sizeConstraints)
        
    }
    
    private func refresh() {
        
        guard let configuration = self.currentConfiguration else { assertionFailure(); return }
        
        tapToReadView.isHidden = configuration.tapToReadViewIsHidden
        tapToReadView.messageObjectID = configuration.messageObjectID
        
        switch configuration {
        case .uploadableOrUploading(hardlink: _, thumbnail: _, fileSize: _, uti: _, filename: _, progress: _):
//            fyleProgressView.setConfiguration(.uploadableOrUploading(progress: progress))
            fyleProgressView.setConfiguration(.complete) // Hide FyleProgressView when uploadableOrUploading because audio is already playable.
        case .downloadable(receivedJoinObjectID: let receivedJoinObjectID, progress: let progress, fileSize: _, uti: _, filename: _):
            fyleProgressView.setConfiguration(.downloadable(receivedJoinObjectID: receivedJoinObjectID, progress: progress))
        case .downloadableSent(sentJoinObjectID: let sentJoinObjectID, progress: let progress, fileSize: _, uti: _, filename: _):
            fyleProgressView.setConfiguration(.downloadableSent(sentJoinObjectID: sentJoinObjectID, progress: progress))
        case .downloading(receivedJoinObjectID: let receivedJoinObjectID, progress: let progress, fileSize: _, uti: _, filename: _):
            fyleProgressView.setConfiguration(.downloading(receivedJoinObjectID: receivedJoinObjectID, progress: progress))
        case .downloadingSent(sentJoinObjectID: let sentJoinObjectID, progress: let progress, fileSize: _, uti: _, filename: _):
            fyleProgressView.setConfiguration(.downloadingSent(sentJoinObjectID: sentJoinObjectID, progress: progress))
        case .completeButReadRequiresUserInteraction(messageObjectID: _, fileSize: _, uti: _):
            fyleProgressView.setConfiguration(.complete)
        case .complete:
            fyleProgressView.setConfiguration(.complete)
        case .cancelledByServer:
            fyleProgressView.setConfiguration(.cancelled)
        }
        
        if let hostingController {
     
            let viewModel = AudioWaveFormContentViewModel(isEnabled: configuration.tapToReadViewIsHidden && configuration.canReadAudio, hardlink: configuration.hardlink)
            
            hostingController.rootView = AudioWaveFormContentView(viewModel: viewModel, delegate: self.delegate, actions: self)
            
            hostingController.view.isHidden = !configuration.tapToReadViewIsHidden
            hostingController.view.invalidateIntrinsicContentSize()
            
        }
    }
    
    func shouldInvalidateIntrinsicSize() async {
        hostingController?.view.invalidateIntrinsicContentSize()
        delegate?.audioWaveFormShouldInvalidateCollectionLayout()
    }
    
    func tappedStuff(tapGestureRecognizer: UITapGestureRecognizer, acceptTapOutsideBounds: Bool) -> TappedStuffForCell? {
        guard self.bounds.contains(tapGestureRecognizer.location(in: self)) else { return nil }
        if !tapToReadView.isHidden {
            return tapToReadView.tappedStuff(tapGestureRecognizer: tapGestureRecognizer, acceptTapOutsideBounds: true)
        } else {
            // Note that the following call returns nil if the configuration is not downloading or downloadable
            return fyleProgressView.tappedStuff(tapGestureRecognizer: tapGestureRecognizer, acceptTapOutsideBounds: true)
        }
    }
    
    func getAllShownHardLink() -> [(hardlink: HardLinkToFyle, viewShowingHardLink: UIView)] {
        guard self.showInStack else { return [] }
        if let hardlink = currentConfiguration?.hardlink {
            return [(hardlink, self)]
        } else {
            return []
        }
    }
}

private protocol AudioWaveFormContentViewActions: AnyObject {
    func shouldInvalidateIntrinsicSize() async
}

private struct AudioWaveFormContentViewModel: Hashable, Equatable {
    
    let isEnabled: Bool
    let hardlink: HardLinkToFyle?
    
    var isConfiguredWithCurrentAudio: Bool {
        guard let hardlink = hardlink else { return false }
        guard let current = ObvAudioPlayer.shared.current else { return false }
        return current == hardlink
    }
}

// MARK: - Waveform samples cache singleton for reuse across WaveFormView instances
class WaveformSamplesCache {
    static let shared = WaveformSamplesCache()
    private let queue = DispatchQueue(label: "WaveformSamplesCache.queue", attributes: .concurrent)
    private var cache: [URL: [Float]] = [:]
    
    private init() {}
    
    func get(url: URL) -> [Float]? {
        var result: [Float]?
        queue.sync {
            result = cache[url]
        }
        return result
    }
    
    func set(samples: [Float], for url: URL) {
        queue.async(flags: .barrier) {
            self.cache[url] = samples
        }
    }
}

struct WaveFormView: View {
    var totalNumberOfSamples: Int = 35
    var hardlink: HardLinkToFyle?
    @Binding var progress: Float       // 0 = début, 1 = fin

    @Binding var samples: [Float]
    
    @State private var animatedSamples: [Float] = []
    
    @State private var isLoading: Bool = false
    
    @State var size: CGSize = .zero
    
    @State private var isDragging = false
    
    @State private var shouldResume: Bool = false

    @ObservedObject var audioPlayer = ObvAudioPlayer.shared
    
    var body: some View {
        HStack(alignment: .center, spacing: 0.0) {
            if let audioURL = hardlink?.hardlinkURL {
                if samples.isEmpty && !isLoading {
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
                            .frame(width: 3.0, height: CGFloat(max(3.0, 40.0 * animatedSamples[idx])))
                            .cornerRadius(3.0)
                            .opacity(opacity)
                            .padding(.horizontal, 1.0)
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
        .frame(height: 48)
        .contentShape(Rectangle())
        .background(
            GeometryReader(content: { proxy in
                Color.clear
                    .onAppear {
                        size = proxy.size
                    }
            })
        )
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        if hardlink == audioPlayer.current {
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
            guard let audioURL = hardlink?.hardlinkURL else { return }
            guard hardlink == audioPlayer.current else { return }
            Task {
                guard hardlink == audioPlayer.current else { return }
                let duration = (try? await ObvAudioPlayer.duration(of: audioURL)) ?? 0.0
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
                for i in newSamples.indices {
                    try? await Task.sleep(nanoseconds: UInt64(i) * 500_000) // small delay for staggered effect
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
        if let cached = WaveformSamplesCache.shared.get(url: url) {
            samples = cached
            return
        }
        let result = await Task.detached(priority: .background) {
            return (try? await extractWaveformSamples(from: url, count: totalNumberOfSamples)) ?? []
        }.value
        samples = result
        WaveformSamplesCache.shared.set(samples: result, for: url)
    }
    

    func extractWaveformSamples(from url: URL, count numberOfSamples: Int) async throws -> [Float] {
        
        let asset = AVAsset(url: url)
        guard !(try await asset.loadTracks(withMediaType: .audio).isEmpty) else { return [] }

        let duration = try await asset.load(.duration)
        let interval = duration.seconds / Double(numberOfSamples) // In seconds
        var amplitudes: [Float] = []

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMBitDepthKey: 32,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 44100.0
        ]
                
        for i in 0..<numberOfSamples {
        
            let assetReader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderAudioMixOutput(
                audioTracks: try await asset.loadTracks(withMediaType: .audio),
                audioSettings: outputSettings
            )
            assetReader.add(output)

            let startTime = CMTime(seconds: Double(i) * interval, preferredTimescale: 600)
            let timeRange = CMTimeRange(start: startTime, duration: CMTime(seconds: 0.5, preferredTimescale: 600))
            assetReader.timeRange = timeRange

            assetReader.startReading()
            if let sampleBuffer = output.copyNextSampleBuffer() {
                
                var blockBuffer: CMBlockBuffer?
                var audioBufferList = AudioBufferList()
                
                CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
                    sampleBuffer,
                    bufferListSizeNeededOut: nil,
                    bufferListOut: &audioBufferList,
                    bufferListSize: MemoryLayout<AudioBufferList>.stride,
                    blockBufferAllocator: nil,
                    blockBufferMemoryAllocator: nil,
                    flags: 0,
                    blockBufferOut: &blockBuffer
                )

                let audioBuffer = audioBufferList.mBuffers
                let samples = UnsafeBufferPointer<Float>(
                    start: audioBuffer.mData?.assumingMemoryBound(to: Float.self),
                    count: Int(audioBuffer.mDataByteSize) / MemoryLayout<Float>.stride
                )

                var sumOfSquares: Float = 0
                for sample in samples {
                    sumOfSquares += sample * sample
                }
                let rmsAmplitude = sqrt(sumOfSquares / Float(samples.count))
                amplitudes.append(rmsAmplitude)

            }
            assetReader.cancelReading()
        }
        
        // Normalize the amplitudes
        guard let maxAmplitude = amplitudes.max(), maxAmplitude > 0 else {
            return []
        }
        let normalizedAmplitudes = amplitudes.map { $0 / maxAmplitude }
        return normalizedAmplitudes

    }

}

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}

struct AudioWaveFormContentView: View {

    private let viewModel: AudioWaveFormContentViewModel
    
    private weak var actions: AudioWaveFormContentViewActions?
    
    private weak var delegate: AudioWaveFormViewDelegate?
    
    @State private var isPlaying: Bool = false
    
    @State private var currentTime: String = "00:00"
    
    @State private var progress: Float = 0.0
    
    @State private var samples: [Float] = []
    
//    @State private var showTranscript: Bool = false
//    @State private var transcript: String? = nil
//    @State private var isTranscribing: Bool = false
    
    @ObservedObject var audioPlayer = ObvAudioPlayer.shared
    
    private let formatter = AudioDurationFormatter()
    
    private class Coordinator: NSObject, ObvAudioPlayerDelegate {
        @Binding var isPlaying: Bool
        @Binding var currentTime: String
        @Binding var progress: Float
        
        @ObservedObject var audioPlayer = ObvAudioPlayer.shared
        
        let hardlink: HardLinkToFyle
        
        let formatter = AudioDurationFormatter()
        
        init(hardlink: HardLinkToFyle,
             isPlaying: Binding<Bool>,
             currentTime: Binding<String>,
             progress: Binding<Float>) {
            self.hardlink = hardlink
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
            DispatchQueue.main.async {
                let current = self.audioPlayer.current
                if self.hardlink == current {
                    self.isPlaying = self.audioPlayer.isPlaying
                } else {
                    self.isPlaying = false
                }
            }
        }
        
        func audioIsPlaying(currentTime: TimeInterval) {
            DispatchQueue.main.async {
                let current = self.audioPlayer.current
                self.refreshPlayPause()
                if self.hardlink == current, let totalDuration = self.audioPlayer.totalDuration, totalDuration > 0 {
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
        
        func playerWillChangeCurrentFyle(previousHardlink: HardLinkToFyle?) {
            if previousHardlink == self.hardlink {
                self.isPlaying = false
            }
        }
    }
    
    @State private var coordinator: Coordinator?
    
    fileprivate init(viewModel: AudioWaveFormContentViewModel, delegate: AudioWaveFormViewDelegate?, actions: AudioWaveFormContentViewActions?) {
        self.viewModel = viewModel
        self.delegate = delegate
        self.actions = actions
    }
    
    private func togglePlay() async throws {
        guard let hardlink = viewModel.hardlink, let audioURL = hardlink.hardlinkURL else { return }
        
        if coordinator == nil {
            coordinator = Coordinator(hardlink: hardlink, isPlaying: $isPlaying, currentTime: $currentTime, progress: $progress)
        }
        audioPlayer.delegate = coordinator
        
        let duration = try await ObvAudioPlayer.duration(of: audioURL)
        
        if progress > 0.98 { progress = 0 } // If progress is near the end we set it to the start of the audio
        let time = duration * TimeInterval(progress)
        
        guard viewModel.isConfiguredWithCurrentAudio else {
            audioPlayer.stop()
            _ = audioPlayer.play(hardlink, at: time)
            self.isPlaying = true
            delegate?.audioHasBeenPlayed(hardlink)
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
    
//    private func transcribeIfNeeded() {
//        guard transcript == nil, !isTranscribing, let url = viewModel.hardlink?.hardlinkURL else { return }
//        isTranscribing = true
//        
//        let request = SFSpeechURLRecognitionRequest(url: url)
//        let recognizer = SFSpeechRecognizer()
//        guard let recognizer, recognizer.isAvailable else {
//            showTranscript = false
//            isTranscribing = false
//            return
//        }
//        
//        recognizer.recognitionTask(with: request) { result, error in
//            guard viewModel.hardlink?.hardlinkURL == url else { return }
//            guard let result = result else {
//                showTranscript = false
//                transcript = nil
//                isTranscribing = false
//                return
//            }
//            
//            if result.isFinal {
//                transcript = result.bestTranscription.formattedString
//                isTranscribing = false
//            }
//        }
//        
//    }
    
    var body: some View {
        VStack(alignment: .center) {
            HStack(alignment: .center, spacing: 4.0) {
                Button {
                    Task {
                        try? await self.togglePlay()
                    }
                } label: {
                    Image(systemIcon: isPlaying ? .pauseFill : .playFill)
                }
                .padding(20.0)
                .opacity(viewModel.isEnabled ? 1.0 : 0.0)
                
                WaveFormView(hardlink: viewModel.hardlink, progress: $progress, samples: $samples)
                
                VStack(alignment: .center, spacing: 14.0) {
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
                    }
                }
                .frame(minWidth: 60.0)
            }
            
//            if viewModel.hardlink?.hardlinkURL != nil  {
//                VStack(alignment: .center) {
//                    if showTranscript {
//                        if isTranscribing {
//                            ProgressView()
//                        } else if let transcript {
//                            Text(transcript)
//                                .lineLimit(nil)
//                                .font(.caption)
//                                .padding(.vertical, 4.0)
//                                .padding(.horizontal, 16.0)
//                                .onAppear {
//                                    Task {
//                                        await actions?.shouldInvalidateIntrinsicSize()
//                                    }
//                                }
//                        }
//                    } else {
//                        Button {
//                            transcribeIfNeeded()
//                            showTranscript.toggle()
//                        } label: {
//                            HStack(alignment: .center) {
//                                Image(systemIcon: .waveform)
//                                Text("TRANSCRIPTION_AUDIO_ACTION")
//                                    .font(.caption)
//                            }
//                        }
//                        .padding(.leading, 8.0)
//                        .padding(.trailing, 10.0)
//                        .padding(.vertical, 4.0)
//                        .background(.quaternary.opacity(0.5))
//                        .clipShape(Capsule())
//                    }
//
//                }
//                .frame(minHeight: 30.0)
//            }
        }
        .onChange(of: viewModel) { newViewModel in // Mise à jour de la duration lorsque le viewModel change
            if viewModel.hardlink?.hardlinkURL != newViewModel.hardlink?.hardlinkURL {
                samples = [] // Reset sample when viewModel changes.
                self.progress = 0
            }
            let currentAudioURL = newViewModel.hardlink?.hardlinkURL
            
            Task {
                if let hardlink = newViewModel.hardlink, let audioURL = hardlink.hardlinkURL, let totalDuration = try? await ObvAudioPlayer.duration(of: audioURL), audioURL == currentAudioURL {
                    self.currentTime = self.formatter.string(from: totalDuration) ?? "00:00"
                    
                    if newViewModel.isConfiguredWithCurrentAudio, ObvAudioPlayer.shared.isPlaying {
                        if coordinator == nil {
                            coordinator = Coordinator(hardlink: hardlink, isPlaying: $isPlaying, currentTime: $currentTime, progress: $progress)
                        }
                        audioPlayer.delegate = coordinator
                        self.isPlaying = true
                    }
                    
                } else {
                    self.currentTime = "00:00"
                }
            }
        }
        .onChange(of: progress) { newProgress in
            let currentAudioURL = viewModel.hardlink?.hardlinkURL
            Task {
                if let audioURL = viewModel.hardlink?.hardlinkURL, let totalDuration = try? await ObvAudioPlayer.duration(of: audioURL), currentAudioURL == audioURL {
                    self.currentTime = self.formatter.string(from: totalDuration * Double(newProgress)) ?? "00:00"
                } else {
                    self.currentTime = "00:00"
                }
            }
        }
        .foregroundStyle(Color(uiColor: .label))
    }
}

#if DEBUG

private let viewModelForPreviews = AudioWaveFormContentViewModel(isEnabled: true, hardlink: nil)

#Preview {
    AudioWaveFormContentView(viewModel: viewModelForPreviews, delegate: nil, actions: nil)
        .padding(30.0)
        .background(Color(uiColor: AppTheme.shared.colorScheme.newReceivedCellBackground))
        .cornerRadius(16.0)
        
}

#endif

