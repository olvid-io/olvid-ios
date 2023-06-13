/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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

import UIKit
import QuickLookThumbnailing
import CoreData
import ObvUICoreData

@available(iOS 14.0, *)
fileprivate extension AudioPlayerView.Configuration {

    var canReadAudio: Bool {
        switch self {
        case .complete: return true
        case .uploadableOrUploading, .downloadable, .downloading, .completeButReadRequiresUserInteraction, .cancelledByServer:
            return false
        }
    }

    var tapToReadViewIsHidden: Bool {
        switch self {
        case .completeButReadRequiresUserInteraction: return false
        case .uploadableOrUploading, .downloadable, .downloading, .cancelledByServer, .complete: return true
        }
    }

    var messageObjectID: TypeSafeManagedObjectID<PersistedMessageReceived>? {
        switch self {
        case .completeButReadRequiresUserInteraction(messageObjectID: let messageObjectID, fileSize: _, uti: _): return messageObjectID
        case .uploadableOrUploading, .downloadable, .downloading, .cancelledByServer, .complete: return nil
        }
    }

    var duration: Double? {
        switch self {
        case .complete(hardlink: let hardlink, _, _, _, _, _):
            guard let url = hardlink?.hardlinkURL else { return nil }
            return ObvAudioPlayer.duration(of: url)
        case .uploadableOrUploading, .downloadable, .downloading, .completeButReadRequiresUserInteraction, .cancelledByServer: return nil
        }
    }

    var wasOpened: Bool? {
        switch self {
        case .complete(_, _, _, _, _, wasOpened: let wasOpened):
            return wasOpened
        case .uploadableOrUploading, .downloadable, .downloading, .completeButReadRequiresUserInteraction, .cancelledByServer:
            return nil
        }
    }
}

protocol AudioPlayerViewDelegate: AnyObject {
    func audioHasBeenPlayed(_: HardLinkToFyle)
}

@available(iOS 14.0, *)
final class AudioPlayerView: ViewForOlvidStack, ObvAudioPlayerDelegate, ViewWithExpirationIndicator, ViewShowingHardLinks, UIViewWithTappableStuff {

    typealias Configuration = AttachmentsView.Configuration

    private var currentConfiguration: Configuration?

    let expirationIndicator = ExpirationIndicatorView()
    let expirationIndicatorSide: ExpirationIndicatorView.Side

    weak var delegate: AudioPlayerViewDelegate?

    private let bubble = BubbleView()
    private let playPauseButton = UIButton(type: .custom)
    private let slider = TappableSlider()
    private let vStack = UIStackView()
    private let formatter = AudioDurationFormatter()
    private var shouldResume: Bool = false
    private let tapToReadView = TapToReadView(showText: false)
    private let fyleProgressView = FyleProgressView()
    private let title = UILabel()
    private let subtitle = UILabel()
    private let durationLabel = UILabel()
    private let byteCountFormatter = ByteCountFormatter()
    private let speakerButton = UIButton(type: .custom)
    private let badge = UIImageView(image: UIImage(systemIcon: .circleFill))

    private var speakerButtonState: Bool = false
    private let playPauseButtonSize: CGFloat = 26.0

    private let internalQueue = DispatchQueue(label: "Sleeping queue", qos: .userInitiated)

    var bubbleColor: UIColor? {
        get { bubble.backgroundColor }
        set { bubble.backgroundColor = newValue }
    }

    init(expirationIndicatorSide side: ExpirationIndicatorView.Side) {
        self.expirationIndicatorSide = side
        super.init(frame: .zero)
        setDefaultValues()
        setupInternalViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func getAllShownHardLink() -> [(hardlink: HardLinkToFyle, viewShowingHardLink: UIView)] {
        guard self.showInStack else { return [] }
        if let hardlink = currentConfiguration?.hardlink {
            return [(hardlink, self)]
        } else {
            return []
        }
    }

    func configure(with newConfiguration: Configuration) {
        guard self.currentConfiguration != newConfiguration else { return }
        self.currentConfiguration = newConfiguration
        refresh()
    }


    private func refresh() {
        guard let configuration = self.currentConfiguration else { assertionFailure(); return }

        slider.isEnabled = configuration.canReadAudio
        playPauseButton.isHidden = !configuration.canReadAudio
        tapToReadView.isHidden = configuration.tapToReadViewIsHidden
        tapToReadView.messageObjectID = configuration.messageObjectID
        if let duration = configuration.duration {
            slider.minimumValue = 0.0
            slider.maximumValue = Float(duration)
            subtitle.text = formatter.string(from: 0)
            durationLabel.text = formatter.string(from: duration)
            durationLabel.alpha = 1.0
        } else {
            durationLabel.text = formatter.string(from: 0)
            durationLabel.alpha = 0.0
        }

        switch configuration {
        case .uploadableOrUploading(hardlink: let hardlink, thumbnail: _, fileSize: let fileSize, uti: let uti, filename: let filename, progress: let progress):
            fyleProgressView.setConfiguration(.uploadableOrUploading(progress: progress))
            if let url = hardlink?.hardlinkURL {
                setTitle(url: url)
                setSubtitle(url: url)
            } else {
                setTitle(filename: filename)
                setSubtitle(fileSize: fileSize, uti: uti)
            }
        case .downloadable(receivedJoinObjectID: let receivedJoinObjectID, progress: let progress, fileSize: let fileSize, uti: let uti, filename: let filename):
            fyleProgressView.setConfiguration(.downloadable(receivedJoinObjectID: receivedJoinObjectID, progress: progress))
            setTitle(filename: filename)
            setSubtitle(fileSize: fileSize, uti: uti)
        case .downloading(receivedJoinObjectID: let receivedJoinObjectID, progress: let progress, fileSize: let fileSize, uti: let uti, filename: let filename):
            fyleProgressView.setConfiguration(.downloading(receivedJoinObjectID: receivedJoinObjectID, progress: progress))
            setTitle(filename: filename)
            setSubtitle(fileSize: fileSize, uti: uti)
        case .completeButReadRequiresUserInteraction(messageObjectID: _, fileSize: let fileSize, uti: let uti):
            fyleProgressView.setConfiguration(.complete)
            setTitle(filename: nil)
            setSubtitle(fileSize: fileSize, uti: uti)
        case .complete(hardlink: let hardlink, thumbnail: _, fileSize: let fileSize, uti: let uti, filename: let filename, wasOpened: _):
            fyleProgressView.setConfiguration(.complete)
            if let url = hardlink?.hardlinkURL {
                setTitle(url: url)
            } else {
                setTitle(filename: filename)
                setSubtitle(fileSize: fileSize, uti: uti)
            }
        case .cancelledByServer(fileSize: let fileSize, uti: let uti, filename: let filename):
            fyleProgressView.setConfiguration(.cancelled)
            setTitle(filename: filename)
            setSubtitle(fileSize: fileSize, uti: uti)
        }

        if let hardlink = currentConfiguration?.hardlink,
           let current = ObvAudioPlayer.shared.current,
           hardlink == current {
            ObvAudioPlayer.shared.delegate = self
            refreshPlayPause()
        }
        badge.isHidden = configuration.wasOpened ?? true
        configureSpeakerButton()
    }

    private func setDefaultValues() {
        self.bubbleColor = .secondarySystemFill
    }

    private func setSubtitle(url: URL) {
        var fileSize = 0
        if let resources = try? url.resourceValues(forKeys: [.fileSizeKey]) {
            fileSize = resources.fileSize!
        }
        let uti = UTType(filenameExtension: url.pathExtension)?.identifier ?? ""
        setSubtitle(fileSize: fileSize, uti: uti)
    }


    private func setSubtitle(fileSize: Int, uti: String) {
        var subtitleElements = [String]()
        subtitleElements.append(byteCountFormatter.string(fromByteCount: Int64(fileSize)))
        if let uti = UTType(uti), let type = uti.localizedDescription {
            subtitleElements.append(type)
        }
        subtitle.text = subtitleElements.joined(separator: " - ")
    }


    private func setTitle(url: URL) {
        let filename = url.lastPathComponent
        setTitle(filename: filename)
    }

    private func setTitle(filename: String?) {
        title.text = filename
    }

    private func setPlayPauseButtonImage(toPause: Bool) {
        let largeConfig = UIImage.SymbolConfiguration(pointSize: playPauseButtonSize, weight: .regular, scale: .large)
        let image: UIImage?
        if toPause {
            image = UIImage(systemIcon: .pauseCircle, withConfiguration: largeConfig)
        } else {
            image = UIImage(systemIcon: .playCircle, withConfiguration: largeConfig)
        }
        playPauseButton.setImage(image, for: .normal)
    }

    private func setSpeakerButtonImage(isSpeakerEnable: Bool) {
        let largeConfig = UIImage.SymbolConfiguration(pointSize: 10, weight: .regular, scale: .large)
        let image: UIImage?
        if isSpeakerEnable {
            image = UIImage(systemIcon: .speakerWave3Fill, withConfiguration: largeConfig)
        } else {
            image = UIImage(systemIcon: .speakerSlashFill, withConfiguration: largeConfig)?.withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal)
        }
        speakerButton.setImage(image, for: .normal)
    }

    private func refreshPlayPause() {
        guard let hardlink = currentConfiguration?.hardlink else { return }
        let current = ObvAudioPlayer.shared.current
        if hardlink == current {
            setPlayPauseButtonImage(toPause: ObvAudioPlayer.shared.isPlaying)
        } else {
            setPlayPauseButtonImage(toPause: false /* play */)
        }
    }

    private func setupInternalViews() {

        addSubview(bubble)
        bubble.translatesAutoresizingMaskIntoConstraints = false

        addSubview(expirationIndicator)
        expirationIndicator.translatesAutoresizingMaskIntoConstraints = false

        bubble.addSubview(playPauseButton)
        playPauseButton.translatesAutoresizingMaskIntoConstraints = false
        playPauseButton.addTarget(self, action: #selector(playPausePress), for: .touchUpInside)
        setPlayPauseButtonImage(toPause: false /* play */)

        bubble.addSubview(badge)
        badge.translatesAutoresizingMaskIntoConstraints = false
        let badgeConfig = UIImage.SymbolConfiguration(font: .systemFont(ofSize: 10))
        badge.preferredSymbolConfiguration = badgeConfig
        badge.tintColor = .red

        bubble.addSubview(title)
        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = UIFont.preferredFont(forTextStyle: .caption1)
        title.textColor = .label

        bubble.addSubview(slider)
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.isContinuous = false
        slider.addTarget(self, action: #selector(self.sliderValueChanged(_:)), for: .valueChanged)
        slider.addTarget(self, action: #selector(self.sliderBeganTracking(_:)), for: .touchDown)
        let thumbImage = UIImage(systemIcon: .circleFill)?.withTintColor(.white, renderingMode: .alwaysOriginal)
        slider.setThumbImage(thumbImage, for: .normal)

        bubble.addSubview(durationLabel)
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.font = UIFont.preferredFont(forTextStyle: .caption2)
        durationLabel.textColor = .secondaryLabel

        bubble.addSubview(subtitle)
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.font = UIFont.preferredFont(forTextStyle: .caption2)
        subtitle.textColor = .secondaryLabel

        bubble.addSubview(speakerButton)
        speakerButton.translatesAutoresizingMaskIntoConstraints = false
        speakerButton.addTarget(self, action: #selector(speakerButtonPress), for: .touchUpInside)

        addSubview(fyleProgressView)
        fyleProgressView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(tapToReadView)
        tapToReadView.translatesAutoresizingMaskIntoConstraints = false
        tapToReadView.tapToReadLabelTextColor = .label

        let verticalSpace = 2
        let trailingPadding = CGFloat(12)
        let borderSpace = 4

        let constraints = [
            bubble.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            bubble.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            bubble.topAnchor.constraint(equalTo: self.topAnchor),
            bubble.bottomAnchor.constraint(equalTo: self.bottomAnchor),

            playPauseButton.leadingAnchor.constraint(equalTo: bubble.leadingAnchor),
            playPauseButton.trailingAnchor.constraint(equalTo: slider.leadingAnchor),
            playPauseButton.centerYAnchor.constraint(equalTo: self.centerYAnchor),

            title.leadingAnchor.constraint(equalTo: slider.leadingAnchor),
            title.trailingAnchor.constraint(equalTo: slider.trailingAnchor),
            title.topAnchor.constraint(equalTo: bubble.topAnchor, constant: CGFloat(borderSpace)),

            slider.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -CGFloat(trailingPadding)),
            slider.topAnchor.constraint(equalTo: title.bottomAnchor, constant: CGFloat(verticalSpace + 2)),

            durationLabel.trailingAnchor.constraint(equalTo: slider.trailingAnchor),
            durationLabel.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: CGFloat(verticalSpace + 2)),
            durationLabel.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -CGFloat(borderSpace)),

            subtitle.leadingAnchor.constraint(equalTo: slider.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: durationLabel.topAnchor),
            subtitle.bottomAnchor.constraint(equalTo: durationLabel.bottomAnchor),

            speakerButton.centerXAnchor.constraint(equalTo: slider.centerXAnchor),
            speakerButton.topAnchor.constraint(equalTo: durationLabel.topAnchor),
            speakerButton.bottomAnchor.constraint(equalTo: durationLabel.bottomAnchor),
            speakerButton.widthAnchor.constraint(equalToConstant: 44.0),

            fyleProgressView.centerXAnchor.constraint(equalTo: playPauseButton.centerXAnchor),
            fyleProgressView.centerYAnchor.constraint(equalTo: playPauseButton.centerYAnchor),

            tapToReadView.centerXAnchor.constraint(equalTo: playPauseButton.centerXAnchor),
            tapToReadView.centerYAnchor.constraint(equalTo: playPauseButton.centerYAnchor),

            badge.centerXAnchor.constraint(equalTo: playPauseButton.centerXAnchor, constant: playPauseButtonSize / 2.3),
            badge.centerYAnchor.constraint(equalTo: playPauseButton.centerYAnchor, constant: -playPauseButtonSize / 2.3),
            badge.heightAnchor.constraint(equalTo: badge.widthAnchor),
        ]

        setupConstraintsForExpirationIndicator(gap: MessageCellConstants.gapBetweenExpirationViewAndBubble)

        title.setContentCompressionResistancePriority(.required, for: .vertical)
        slider.setContentCompressionResistancePriority(.required, for: .vertical)
        subtitle.setContentCompressionResistancePriority(.required, for: .vertical)
        durationLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        constraints.forEach { $0.priority -= 1 }
        NSLayoutConstraint.activate(constraints)

        let sizeConstraints = [
            self.widthAnchor.constraint(equalToConstant: MessageCellConstants.singleAttachmentViewWidth),
            playPauseButton.widthAnchor.constraint(equalToConstant: MessageCellConstants.attachmentIconSize),
            playPauseButton.heightAnchor.constraint(equalToConstant: MessageCellConstants.attachmentIconSize),
            tapToReadView.widthAnchor.constraint(equalToConstant: MessageCellConstants.attachmentIconSize),
            tapToReadView.heightAnchor.constraint(equalToConstant: MessageCellConstants.attachmentIconSize),
        ]

        sizeConstraints.forEach { $0.priority -= 1 }
        NSLayoutConstraint.activate(sizeConstraints)
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
    
    
    var isConfiguredWithCurrentAudio: Bool {
        guard let hardlink = currentConfiguration?.hardlink else { return false }
        guard let current = ObvAudioPlayer.shared.current else { return false }
        return current == hardlink
    }

    @objc private func playPausePress() {
        defer {
            refreshPlayPause()
        }
        guard let hardlink = currentConfiguration?.hardlink else { return }

        let time = TimeInterval(self.slider.value)
        guard isConfiguredWithCurrentAudio else {
            ObvAudioPlayer.shared.stop()
            ObvAudioPlayer.shared.delegate = self
            _ = ObvAudioPlayer.shared.play(hardlink, enableSpeaker: speakerButtonState, at: time)
            delegate?.audioHasBeenPlayed(hardlink)
            return
        }

        if ObvAudioPlayer.shared.isPlaying {
            ObvAudioPlayer.shared.pause()
        } else {
            ObvAudioPlayer.shared.resume(enableSpeaker: speakerButtonState, at: time)
        }
    }

    @objc private func speakerButtonPress() {
        self.speakerButtonState.toggle()
        setSpeakerButtonImage(isSpeakerEnable: self.speakerButtonState)
        internalQueue.async {
            if self.isConfiguredWithCurrentAudio, ObvAudioPlayer.shared.isPlaying {
                let newSpeakerValue = !ObvAudioPlayer.shared.isSpeakerEnable
                ObvAudioPlayer.shared.setSpeaker(to: newSpeakerValue)
                DispatchQueue.main.async {
                    self.speakerButtonState = ObvAudioPlayer.shared.isSpeakerEnable
                }
            }
        }
    }

    var isSpeakerEnableForCurrentPlayer: Bool {
        if isConfiguredWithCurrentAudio, ObvAudioPlayer.shared.isPlaying {
            return ObvAudioPlayer.shared.isSpeakerEnable
        } else {
            return speakerButtonState
        }
    }

    func configureSpeakerButton() {
        if let currentConfiguration = currentConfiguration, currentConfiguration.canReadAudio {
            speakerButton.isHidden = false
            setSpeakerButtonImage(isSpeakerEnable: isSpeakerEnableForCurrentPlayer)
        } else {
            speakerButton.isHidden = true
        }
    }

    func audioPlayerDidStopPlaying() {
        assert(Thread.isMainThread)
        self.refreshPlayPause()
    }

    func audioPlayerDidFinishPlaying() {
        assert(Thread.isMainThread)
        self.slider.setValue(0.0, animated: true)
        self.refreshPlayPause()
        self.speakerButtonState = false
        setSpeakerButtonImage(isSpeakerEnable: speakerButtonState)
    }

    func audioIsPlaying(currentTime: TimeInterval) {
        DispatchQueue.main.async {
            self.slider.setValue(Float(currentTime), animated: true)
            self.subtitle.text = self.formatter.string(from: currentTime)
        }
    }

    @objc private func sliderBeganTracking(_ slider: UISlider) {
        self.shouldResume = ObvAudioPlayer.shared.isPlaying
        ObvAudioPlayer.shared.pause()
        refreshPlayPause()
    }

    @objc private func sliderValueChanged(_ slider: UISlider) {
        let time = TimeInterval(slider.value)
        self.subtitle.text = self.formatter.string(from: time)
        if shouldResume || ObvAudioPlayer.shared.isPlaying {
            ObvAudioPlayer.shared.resume(enableSpeaker: speakerButtonState, at: time)
            refreshPlayPause()
        }
    }

}

class AudioDurationFormatter: Formatter {

    func string(from duration: Double) -> String? {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = [ .pad ]
        formatter.allowedUnits = [ .second, .minute ]

        return formatter.string(from: duration)
    }
}

class TappableSlider: UISlider {

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupView()
    }

    private func setupView() {
        addTapGesture()
    }

    private func addTapGesture() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
    }

    @objc private func handleTap(_ sender: UITapGestureRecognizer) {
        let location = sender.location(in: self)
        let percent = minimumValue + Float(location.x / bounds.width) * maximumValue
        setValue(percent, animated: true)
        sendActions(for: .valueChanged)
    }
}
