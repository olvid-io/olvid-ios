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
import CoreData
import AVKit

final class CallViewController: UIViewController {

    private(set) var durationFormatter = CallDurationFormatter()

    private static let buttonSize: CGFloat = 80
    private let call: Call

    init(call: Call) {
        self.call = call
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .portrait }
    override var shouldAutorotate: Bool { true }

    private let mainStackView = UIStackView()
    private let contactNameLabel = UILabel()
    private let statusLabel = UILabel()
    private let subStackView = UIStackView()
    private let callButtonsStackView = UIStackView()
    private let speakerButton = UIButton(type: .custom)
    private let muteButton = UIButton(type: .custom)
    private let appButton = UIButton(type: .custom)
    private let hangUpButton = UIButton(type: .custom)
    private let answerCallButton = UIButton(type: .custom)
    private let timerLabel = ObvTimerLabel()
    private let backgroundImageView = UIImageView(image: UIImage(named: "SplashScreenBackground"))


    private var statusBar: UIView? = nil

    private var observationTokens = [NSObjectProtocol]()

    override func viewDidLoad() {
        super.viewDidLoad()
        setNeedsStatusBarAppearanceUpdate()

        setup()
        observeCallHasBeenUpdated()
        observeRouteChangeNotification()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    private func changeHighlight(button: UIButton, highlight: Bool) {
        if highlight {
            button.tintColor = .black
            button.backgroundColor = .white
        } else {
            button.tintColor = .white
            button.backgroundColor = .clear
        }
    }

    private func configureButton(button: UIButton, systemName: String,
                                 highlight: Bool = false, border: Bool = true) {
        button.layer.cornerRadius = 0.5 * CallViewController.buttonSize
        button.layer.masksToBounds = true
        changeHighlight(button: button, highlight: highlight)
        if border {
            button.layer.borderWidth = 2
            button.layer.borderColor = UIColor.white.cgColor
        }
        let image = UIImage.makeSystemImage(systemName: systemName, size: 30.0)
        button.setImage(image, for: .normal)
        button.contentMode = .center
        button.imageView?.contentMode = .scaleAspectFit
    }

    private func setup() {
        self.view.backgroundColor = AppTheme.shared.colorScheme.systemBackground

        backgroundImageView.accessibilityIdentifier = "backgroundImage"
        backgroundImageView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(backgroundImageView)

        mainStackView.accessibilityIdentifier = "mainStackView"
        mainStackView.translatesAutoresizingMaskIntoConstraints = false
        mainStackView.axis = .vertical
        mainStackView.alignment = .center
        mainStackView.distribution = .equalSpacing
        self.view.addSubview(mainStackView)

        contactNameLabel.accessibilityIdentifier = "contactNameLabel"
        contactNameLabel.textColor = .white
        contactNameLabel.font = contactNameLabel.font.withSize(40)
        mainStackView.addArrangedSubview(contactNameLabel)

        statusLabel.accessibilityIdentifier = "statusLabel"
        statusLabel.textColor = .white
        statusLabel.numberOfLines = 2
        mainStackView.addArrangedSubview(statusLabel)

        timerLabel.accessibilityIdentifier = "timer"
        timerLabel.textColor = .white
        timerLabel.text = " " // Hack preventing a glitch when displaying the actual time
        mainStackView.addArrangedSubview(timerLabel)

        subStackView.accessibilityIdentifier = "subStackView"
        subStackView.translatesAutoresizingMaskIntoConstraints = false
        subStackView.axis = .horizontal
        subStackView.alignment = .bottom
        subStackView.distribution = .equalCentering
        mainStackView.addArrangedSubview(subStackView)
        
        callButtonsStackView.accessibilityIdentifier = "callButtonsStackView"
        callButtonsStackView.translatesAutoresizingMaskIntoConstraints = false
        callButtonsStackView.axis = .horizontal
        callButtonsStackView.alignment = .bottom
        callButtonsStackView.distribution = .equalCentering
        callButtonsStackView.spacing = 16
        mainStackView.addArrangedSubview(callButtonsStackView)

        speakerButton.accessibilityIdentifier = "speakerButton"
        configureButton(button: speakerButton, systemName: "speaker.3.fill")
        speakerButton.addTarget(self, action: #selector(speakerPress), for: .touchUpInside)
        subStackView.setCustomSpacing(10, after: speakerButton)
        subStackView.addArrangedSubview(speakerButton)

        muteButton.accessibilityIdentifier = "muteButton"
        configureButton(button: muteButton, systemName: "mic.slash.fill")
        muteButton.addTarget(self, action: #selector(mutePress), for: .touchUpInside)
        subStackView.setCustomSpacing(10, after: muteButton)
        subStackView.addArrangedSubview(muteButton)

        appButton.accessibilityIdentifier = "appButton"
        configureButton(button: appButton, systemName: "text.bubble.fill")
        appButton.addTarget(self, action: #selector(olvidPress), for: .touchUpInside)
        subStackView.addArrangedSubview(appButton)

        hangUpButton.accessibilityIdentifier = "hangUpButton"
        configureButton(button: hangUpButton, systemName: "phone.down.fill", border: false)
        hangUpButton.backgroundColor = .red
        hangUpButton.addTarget(self, action: #selector(hangUpPress), for: .touchUpInside)
        callButtonsStackView.addArrangedSubview(hangUpButton)
        
        answerCallButton.accessibilityIdentifier = "answerCallButton"
        configureButton(button: answerCallButton, systemName: "phone.down.fill", border: false)
        answerCallButton.backgroundColor = .green
        answerCallButton.addTarget(self, action: #selector(answerCallButtonPressed), for: .touchUpInside)
        callButtonsStackView.addArrangedSubview(answerCallButton)

        setupConstraints()

        configure()
    }
    
    @objc func answerCallButtonPressed(sender: UIButton!) {
        guard let incomingCall = call as? IncomingCall else { return }
        switch incomingCall.state {
        case .initial:
            incomingCall.answerCall()
        default:
            return
        }
    }

    @objc func hangUpPress(sender: UIButton!) {
        call.endCall()
    }

    @objc func olvidPress(sender: UIButton!) {
        ObvMessengerInternalNotification.toggleCallView.postOnDispatchQueue()
    }

    @objc func speakerPress(sender: UIButton!) {
        let availableInputs = ObvAudioSessionUtils.shared.getAllInputs()
        if availableInputs.count == 2 {
            availableInputs.first(where: { !$0.isCurrent })?.activate()
        } else {
            // If there is more than one available input, we offer the user a chance to select between those inputs
            let alert = UIAlertController(title: nil, message: nil, preferredStyle: UIDevice.current.actionSheetIfPhoneAndAlertOtherwise)
            for input in availableInputs {
                alert.addAction(UIAlertAction(title: input.label, style: .default, handler: { _ in input.activate() }))
            }
            alert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel, handler: { (_) in
                alert.dismiss(animated: true)
            }))
            self.present(alert, animated: true)
        }
    }

    @objc func mutePress(sender: UIButton!) {
        if call.isMuted {
            call.unmute()
        } else {
            call.mute()
        }
    }

    private func setupConstraints() {
        let margins = view.layoutMarginsGuide
        let constraints = [
            mainStackView.topAnchor.constraint(equalTo: margins.topAnchor, constant: 32),
            mainStackView.bottomAnchor.constraint(equalTo: margins.bottomAnchor, constant: -32),
            mainStackView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            mainStackView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16),

            subStackView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 32),
            subStackView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -32),

            speakerButton.widthAnchor.constraint(equalToConstant: CallViewController.buttonSize),
            speakerButton.heightAnchor.constraint(equalTo: speakerButton.widthAnchor),
            muteButton.widthAnchor.constraint(equalToConstant: CallViewController.buttonSize),
            muteButton.heightAnchor.constraint(equalTo: muteButton.widthAnchor),
            appButton.widthAnchor.constraint(equalToConstant: CallViewController.buttonSize),
            appButton.heightAnchor.constraint(equalTo: appButton.widthAnchor),
            hangUpButton.widthAnchor.constraint(equalToConstant: CallViewController.buttonSize),
            hangUpButton.heightAnchor.constraint(equalTo: hangUpButton.widthAnchor),
            answerCallButton.widthAnchor.constraint(equalToConstant: CallViewController.buttonSize),
            answerCallButton.heightAnchor.constraint(equalTo: answerCallButton.widthAnchor),
            
            backgroundImageView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            backgroundImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        ]
        NSLayoutConstraint.activate(constraints)
    }


    private func configure() {
        contactNameLabel.text = call.callParticipants.first?.displayName
        if statusLabel.text == nil {
            // We do not inform of the failed status, since the call will certainly either hangup or reconnect
            statusLabel.text = call.state.localizedString
        }
        changeHighlight(button: muteButton, highlight: call.isMuted)
        speakerButton.isEnabled = (call.state == .callInProgress)
        changeHighlight(button: speakerButton, highlight: call.state == .callInProgress &&
                            ObvAudioSessionUtils.shared.getAllInputs().first(where: { $0.isCurrent })?.isSpeaker ?? false)

        if let start = call.stateDate[.callInProgress], call.state == .callInProgress {
            timerLabel.schedule(from: start)
        }
        
        if let incomingCall = call as? IncomingWebrtcCall {
            switch incomingCall.state {
            case .initial:
                // We never show the answerCallButton when we use call kit
                answerCallButton.isHidden = call.usesCallKit
            default:
                answerCallButton.isHidden = true
            }
        } else {
            answerCallButton.isHidden = true
        }
        
        self.view.layoutIfNeeded()
    }

    private func observeCallHasBeenUpdated() {
        observationTokens.append(ObvMessengerInternalNotification.observeCallHasBeenUpdated { (call, updateKind) in
            guard call.uuid == self.call.uuid else { return }
            DispatchQueue.main.async {
                self.configure()
            }
        })
    }

    private func observeRouteChangeNotification() {
        observationTokens.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: OperationQueue.main, using: { (_) in
            DispatchQueue.main.async {
                self.configure()
            }
        }))
    }



}


extension CallState {
    
    var localizedString: String {
        switch self {
        case .initial: return NSLocalizedString("CALL_STATE_NEW", comment: "")
        case .gettingTurnCredentials: return NSLocalizedString("CALL_STATE_GETTING_TURN_CREDENTIALS", comment: "")
        case .kicked: return NSLocalizedString("CALL_STATE_KICKED", comment: "")
        case .userAnsweredIncomingCall, .initializingCall: return NSLocalizedString("CALL_STATE_INITIALIZING_CALL", comment: "")
        case .ringing: return NSLocalizedString("CALL_STATE_RINGING", comment: "")
        case .callRejected: return NSLocalizedString("CALL_STATE_CALL_REJECTED", comment: "")
        case .callInProgress: return NSLocalizedString("SECURE_CALL_IN_PROGRESS", comment: "")
        case .hangedUp: return NSLocalizedString("CALL_STATE_HANGED_UP", comment: "")
        case .permissionDeniedByServer: return NSLocalizedString("CALL_STATE_PERMISSION_DENIED_BY_SERVER", comment: "")
        case .unanswered: return NSLocalizedString("UNANSWERED", comment: "")
        case .callInitiationNotSupported: return NSLocalizedString("CALL_INITITION_NOT_SUPPORTED", comment: "")
        }
    }
    
}

extension PeerState {

    var localizedString: String {
        switch self {
        case .initial: return NSLocalizedString("CALL_STATE_NEW", comment: "")
        case .startCallMessageSent: return NSLocalizedString("CALL_STATE_INCOMING_CALL_MESSAGE_WAS_POSTED", comment: "")
        case .ringing: return NSLocalizedString("CALL_STATE_RINGING", comment: "")
        case .busy: return NSLocalizedString("CALL_STATE_BUSY", comment: "")
        case .callRejected: return NSLocalizedString("CALL_STATE_CALL_REJECTED", comment: "")
        case .connectingToPeer: return NSLocalizedString("CALL_STATE_CONNECTING_TO_PEER", comment: "")
        case .connected: return NSLocalizedString("SECURE_CALL_IN_PROGRESS", comment: "")
        case .reconnecting: return NSLocalizedString("CALL_STATE_RECONNECTING", comment: "")
        case .hangedUp: return NSLocalizedString("CALL_STATE_HANGED_UP", comment: "")
        case .kicked: return NSLocalizedString("CALL_STATE_KICKED", comment: "")
        case .timeout: return NSLocalizedString("CALL_STATE_TIMEOUT", comment: "")
        }
    }
}


class CallDurationFormatter: Formatter {

    func string(fromDuration duration: Int) -> String? {
        let duration: TimeInterval = Double(duration)

        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = [ .pad ]
        formatter.allowedUnits = [ .second, .minute ]


        return formatter.string(from: duration)
    }
}
