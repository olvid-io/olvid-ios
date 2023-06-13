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
import PhotosUI
import Combine
import MobileCoreServices
import os.log
import VisionKit
import PDFKit
import SwiftUI
import ObvUI
import Platform_Base
import ObvUICoreData
import Components_TextInputShortcutsResultView
import UI_CircledInitialsView_CircledInitialsConfiguration
import Discussions_Mentions_ComposeMessageBuilder

/// Namespace for everything `NewComposeMessageView` related
enum NewComposeMessageViewTypes {
    /// Represents a text shortcut
    ///
    /// - mention: A user mention, prefixed with `@`
    enum TextShortcut {
        /// A user mention, prefixed with `@`
        case mention
    }

    /// Represents a shortcut item
    /// A shortcut item is something invoked when the user enters a special keystroke (i.e. `@` for mentions, `:` for emojis, etc.)
    struct TextShortcutItem: Hashable {
        /// Available accessories for text shortcuts
        ///
        /// - `circledInitialsView`: Represents the configuration for ``NewCircledInitialsView``. See also ``CircledInitialsConfiguration``
        enum Accessory: Hashable {
            /// Represents the configuration for ``NewCircledInitialsView``. See also ``CircledInitialsConfiguration``
            case circledInitialsView(configuration: CircledInitialsConfiguration)
        }

        /// A string to be used against searching
        let searchMatcher: String

        /// The user-facing visible title that will be presented from a dropdown menu
        let title: String

        /// A user-facing subtitle that will be presented from a dropdown menu
        let subtitle: String?

        /// An optional accessory associated with ``title``
        let accessory: Accessory?

        /// The actual value that will be rendered within the text
        /// An instance of `NSAttributedString` is exposed as such to pass special attributes
        ///
        /// - SeeAlso: `NSAttributedString.Key`
        let value: NSAttributedString
     }
}

@available(iOS 15.0, *)
protocol NewComposeMessageViewDelegate: UIViewController {

    /// Method called when the shortcuts view will be displayed, used in conjunction with ``NewComposeMessageViewDelegate/newComposeMessageViewShortcutPickerGeometryPlacementSiblingView(_:)`` and ``NewComposeMessageViewDelegate/newComposeMessageViewShortcutPickerSuperview(_:)``
    ///
    /// - Parameter newComposeMessageView: The compose view responsible for this call
    /// - Returns: The view for which the shortcuts view will be placed directly above. Must have the value returned by ``NewComposeMessageViewDelegate/newComposeMessageViewShortcutPickerSuperview(_:)`` as its superview
    func newComposeMessageViewShortcutPickerAboveSiblingView(_ newComposeMessageView: NewComposeMessageView) -> UIView

    /// Method called when the shortcuts view will be displayed, used in conjunction with ``NewComposeMessageViewDelegate/newComposeMessageViewShortcutPickerAboveSiblingView(_:)`` and ``NewComposeMessageViewDelegate/newComposeMessageViewShortcutPickerSuperview(_:)``
    /// - Parameter newComposeMessageView: The compose view responsible for this call
    /// - Returns: The view for which to perform geometrical placements
    func newComposeMessageViewShortcutPickerGeometryPlacementSiblingView(_ newComposeMessageView: NewComposeMessageView) -> UIView

    /// Method returning the superview for which to add the shortcuts view as a subview, used in conjunction with ``NewComposeMessageViewDelegate/newComposeMessageViewShortcutPickerAboveSiblingView(_:)`` and ``NewComposeMessageViewDelegate/newComposeMessageViewShortcutPickerGeometryPlacementSiblingView(_:)``
    /// - Parameter newComposeMessageView: The compose view responsible for this call
    /// - Returns: The superview to add the picker view to, same superview as ``NewComposeMessageViewDelegate/newComposeMessageViewShortcutPickerAboveSiblingView(_:)``
    func newComposeMessageViewShortcutPickerSuperview(_ newComposeMessageView: NewComposeMessageView) -> UIView
    
}

/// Protocol that acts as the datsource for an instance of ``NewComposeMessageView``
@available(iOS 15.0, *)
protocol NewComposeMessageViewDatasource: AnyObject {
    func newComposeMessageView(_ newComposeMessageView: NewComposeMessageView, itemsForTextShortcut shortcut: NewComposeMessageViewTypes.TextShortcut, text: String) -> [NewComposeMessageViewTypes.TextShortcutItem]
}

@available(iOS 15.0, *)
final class NewComposeMessageView: UIView, UITextViewDelegate, ViewShowingHardLinks {
    
    private enum Constants {
        static let defaultTypingAttributes: [NSAttributedString.Key: Any] = [.font: UIFont.preferredFont(forTextStyle: .body),
                                                                             .foregroundColor: UIColor.label]
    }

    private let backgroundBlurVisualEffect = UIBlurEffect(style: .regular)
    private lazy var backgroundVisualEffectView = UIVisualEffectView(effect: backgroundBlurVisualEffect)

    /// Helper boolean to defer the initial cal to ``_insertShortcutsViewIntoHierachy()``, called from `didMoveToSuperview()`
    private var hasDoneInitialSetupOfShortcutsView = false

    private lazy var shortcutsView = TextInputShortcutsResultView(blurEffect: backgroundBlurVisualEffect)..{
        $0.delegate = self
    }

    /// These constraints are those that we add when inserting ``shortcutsView`` to its superview
    private var shortcutsViewSuperviewConstraints: [NSLayoutConstraint] = []

    /// This view will contain all of the subviews, except for ``shortcutsView``.
    private(set) lazy var mainContentView = UIView()
    private var mainContentViewHeight: CGFloat?

    private let multipleButtonsStackView = UIStackView()
    let textViewForTyping: AutoGrowingTextView
    private let padding = CGFloat(8)
    private let textFieldBubble = BubbleView()
    private var flameFillButton: UIButton!
    private var plusCircleButton: UIButton!
    private var paperclipButton: UIButton!
    private var photoButton: UIButton!
    private var cameraButton: UIButton!
    private var scannerButton: UIButton!
    private var microButton: UIButton!
    private var trashCircleButton: UIButton!
    private var introduceButton: UIButton?
    private var composeMessageSettingsButton: UIButton?
    private var chevronButton: UIButton!
    private let buttonSize = CGFloat(44)
    private var emojiButton = UIButton(type: .system)
    private var paperplaneButton: UIButton!
    private let sendButtonsHolder = UIView()
    private let sendButtonAnimator = UIViewPropertyAnimator(duration: 0.5, dampingRatio: 0.5)
    private let textPlaceholder = UILabel()
    private let durationLabel = UILabel()
    private let replyToView: ReplyToView

    private var lastScreenWidthConsideredForMultipleButtonsStackView = CGFloat.zero
    private var lastButtonWidthConsideredForMultipleButtonsStackView = CGFloat.zero

    private var constraintsForState = [State: [NSLayoutConstraint]]()
    private var constraintsWhenButtonsHolderIsHiden: [NSLayoutConstraint]!
    private var currentState = State.initial
    private var viewsToShowForState = [State: [UIView]]()
    
    private var constraintsWhenShowingReplyTo = [NSLayoutConstraint]()
    private var constraintsWhenHidingReplyTo = [NSLayoutConstraint]()

    private var discussionViewDidAppearWasCalled = false
    private let buttonsAnimationValues: (duration: Double, options: UIView.AnimationOptions) = (0.25, UIView.AnimationOptions([.curveEaseInOut]))
    
    let draft: PersistedDraft
    let attachmentsCollectionViewController: AttachmentsCollectionViewController
    
    private var textFieldBubbleWasJustTapped = false
    
    weak var delegateViewController: UIViewController?
    
    private var cancellables = [AnyCancellable]()
    private var kvo = [NSKeyValueObservation]()

    private var numberOfAttachments = 0
    
    private var constraintsForAttachmentsState = [AttachmentsState: [NSLayoutConstraint]]()
    private var viewsToShowForAttachmentsState = [AttachmentsState: [UIView]]()
    private var currentAttachmentsState = AttachmentsState.noAttachment
    
    private var currentSendButtonType: SendButtonType?
    
    private var currentFreezeId: UUID?
    private var currentFreezeProgress: Progress?
    private var freezableButtons = [UIButton]()
    private var notificationTokens = [NSObjectProtocol]()

    private var recordDurationTimer: Timer?
    private let durationFormatter = AudioDurationFormatter()

    weak var delegate: NewComposeMessageViewDelegate? {
        didSet {
            _insertShortcutsViewIntoHierachy()
        }
    }

    /// Publishes the latest frame of the main content view. This is used by the new single discussion view controller to adapt the insets of the collection view of messages.
    @Published private(set) var mainContentViewFrame: CGRect = .zero

    weak var datasource: NewComposeMessageViewDatasource?
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: NewComposeMessageView.self))

    // When switching state, we often perfom multiple views animations. If multiple events occurs, it might occur that we start an animation for switching from state A to B, and start another animation for switch from B to C before the previous animation finishes. To prevent this situation, we use a DispatchGroup and a serial queue in order to wait until an animation is finished before starting the next one.
    private let dispatchGroupForCoordinatingStateSwitches = DispatchGroup() // Tested
    private let queueForCoordinatingStateSwitches = DispatchQueue(label: "Compose view animation coordinator queue", qos: .userInteractive)

    private static let errorDomain = "NewComposeMessageView"
    private func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: Self.errorDomain, code: 0, userInfo: userInfo)
    }
    private struct DraftBodyWithId: Equatable {
        let body: String
        let id: UUID
    }

    var preventTextViewFromEditing = false

    private let textSubject = PassthroughSubject<DraftBodyWithId, Never>()
    private var textPublisher: AnyPublisher<DraftBodyWithId, Never> {
        textSubject.eraseToAnyPublisher()
    }

    private let mentionsSubject: CurrentValueSubject<Set<MessageJSON.UserMention>, Never>

    private let mentionsPublisher: AnyPublisher<Set<MessageJSON.UserMention>, Never>

    private let saveDraftImmediatelySubject = PassthroughSubject<Void, Never>()
    private var saveDraftImmediatelyPublisher: AnyPublisher<Void, Never> {
        return saveDraftImmediatelySubject.eraseToAnyPublisher()
    }
    private var currentDraftId = UUID()
    private let internalQueue = DispatchQueue(label: "NewComposeMessageView internal queue")

    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return df
    }()

    private func button(for action: NewComposeMessageViewAction) -> UIButton? {
        switch action {
        case .oneTimeEphemeralMessage:
            return flameFillButton
        case .scanDocument:
            return scannerButton
        case .shootPhotoOrMovie:
            return cameraButton
        case .chooseImageFromLibrary:
            return photoButton
        case .choseFile:
            return paperclipButton
        case .introduceThisContact:
            return introduceButton
        case .composeMessageSettings:
            return composeMessageSettingsButton
        }
    }
    
    private func actionTitle(for action: NewComposeMessageViewAction) -> String {
        if case .introduceThisContact = action {
            switch try? draft.discussion.kind {
            case .oneToOne(withContactIdentity: let contact):
                if let contact = contact {
                    /// Override action.title to show the name of contact
                    let contactName = contact.shortOriginalName
                    return String.localizedStringWithFormat(NSLocalizedString("INTRODUCE_CONTACT_%@_TO", comment: ""), contactName)
                } else {
                    return action.title
                }
            case .groupV1, .groupV2, .none:
                return action.title
            }
        } else {
            return action.title
        }
    }

    private func isActionAvailable(for action: NewComposeMessageViewAction) -> Bool {
        guard !draft.isDeleted else { return false }
        switch action {
        case .oneTimeEphemeralMessage,
                .scanDocument,
                .shootPhotoOrMovie,
                .chooseImageFromLibrary,
                .choseFile,
                .composeMessageSettings:
            return true
        case .introduceThisContact:
            switch try? draft.discussion.kind {
            case .oneToOne(withContactIdentity: let contactIdentity):
                return contactIdentity != nil
            case .groupV1, .groupV2, .none:
                return false
            }
        }
    }

    private func uiAction(for action: NewComposeMessageViewAction) -> UIAction? {
        let symbolConfiguration = UIImage.SymbolConfiguration(textStyle: .body)
        let image = UIImage(systemIcon: action.icon, withConfiguration: symbolConfiguration)
        guard isActionAvailable(for: action) else { return nil }
        let title = actionTitle(for: action)
        return UIAction(title: title, image: image) { [weak self] _ in
            switch action {
            case .oneTimeEphemeralMessage:
                self?.flameFillButtonTapped()
            case .scanDocument:
                self?.scannerButtonTapped()
            case .shootPhotoOrMovie:
                self?.cameraButtonTapped()
            case .chooseImageFromLibrary:
                self?.photoButtonTapped()
            case .choseFile:
                self?.paperclipButtonTapped()
            case .introduceThisContact:
                self?.introduceButtonTapped()
            case .composeMessageSettings:
                self?.composeMessageSettingsButtonTapped()
            }
        }
    }
    
    
    init(draft: PersistedDraft, viewShowingHardLinksDelegate: ViewShowingHardLinksDelegate, cacheDelegate: DiscussionCacheDelegate?, delegate: NewComposeMessageViewDelegate?, datasource: NewComposeMessageViewDatasource?) {
        textViewForTyping = AutoGrowingTextView(defaultTypingAttributes: Constants.defaultTypingAttributes)

        assert(draft.managedObjectContext?.concurrencyType == .mainQueueConcurrencyType)
        self.replyToView = ReplyToView(draftObjectID: draft.typedObjectID, cacheDelegate: cacheDelegate)
        self.draft = draft
        self.attachmentsCollectionViewController = AttachmentsCollectionViewController(draftObjectID: draft.typedObjectID,
                                                                                       delegate: viewShowingHardLinksDelegate,
                                                                                       cacheDelegate: cacheDelegate)
        self.delegate = delegate
        self.datasource = datasource

        let userMentions = Set(draft.mentions.compactMap({ try? $0.userMention }))
        
        mentionsSubject = .init(userMentions)

        mentionsPublisher = mentionsSubject
            .eraseToAnyPublisher()

        super.init(frame: .zero)

        (currentFreezeId, currentFreezeProgress) = CompositionViewFreezeManager.shared.register(self)

        setupInternalViews()
        continuouslySaveDraftText()
        observeAttachmentsChanges()
        observeDraftBodyChanges()
        observeMessageChanges()
        observeDiscussionLocalConfigurationHasBeenUpdatedNotifications()
        observeNotifications()
        observeDefaultEmojiInAppSettings()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        cancellables.forEach({ $0.cancel() })
        CompositionViewFreezeManager.shared.unregister(self)
    }

    
    override func layoutSubviews() {
        super.layoutSubviews()
        unhideSelf()
        hideOrShowButtonsForAvailableWidth()
        updateMainContentViewFramePublisher()
    }
    
    
    /// When entering a discussion, this view's alpha is set to 0 until the current state is not `.initial` anymore and ``layoutSubviews()`` is called.
    /// This allows to hide early animation glitches of this view when entering the discussion.
    private func unhideSelf() {
        if currentState != .initial && self.alpha != 1.0 {
            UIViewPropertyAnimator.runningPropertyAnimator(withDuration: 0.2, delay: 0) { [weak self] in
                self?.alpha = 1.0
            }
        }
    }
    
    
    /// Called from ``func layoutSubviews()``
    private func updateMainContentViewFramePublisher() {
        if let superview {
            let mainContentViewBounds = mainContentView.bounds
            let newMainContentViewFrame = superview.convert(mainContentViewBounds, from: mainContentView)
            if self.mainContentViewFrame != newMainContentViewFrame {
                self.mainContentViewFrame = newMainContentViewFrame
            }
        }
    }
    

    private func observeNotifications() {
        notificationTokens.append(
            ObvMessengerSettingsNotifications.observePreferredComposeMessageViewActionsDidChange(queue: OperationQueue.main) { [weak self] in
                self?.processPreferredComposeMessageViewActionsDidChange()
            })
        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioInterruption), name: AVAudioSession.interruptionNotification, object: nil)
    }

    private func _insertShortcutsViewIntoHierachy() {
        shortcutsView.removeFromSuperview()

        NSLayoutConstraint.deactivate(shortcutsViewSuperviewConstraints)

        shortcutsViewSuperviewConstraints.removeAll()

        guard let delegate else {
            assertionFailure("we're missing our delegate…")
            return
        }

        let shortcutsViewSuperview = delegate.newComposeMessageViewShortcutPickerSuperview(self)

        let shortcutsSiblingView = delegate.newComposeMessageViewShortcutPickerAboveSiblingView(self)

        let shortcutsGeometricalPlacementView = delegate.newComposeMessageViewShortcutPickerGeometryPlacementSiblingView(self)

        #if DEBUG
        if let shortcutsSiblingViewSuperview = shortcutsSiblingView.superview,
           let shortcutsGeometricalPlacementViewSuperView = shortcutsGeometricalPlacementView.superview {
            assert(shortcutsSiblingViewSuperview.isDescendant(of: shortcutsViewSuperview), "expected sibling to belong to same superview")
            assert(shortcutsGeometricalPlacementViewSuperView.isDescendant(of: shortcutsViewSuperview), "expected sibling to belong to same superview")
        } else {
            assertionFailure("expected shortcutsSiblingView to have a superview…")
        }
        #endif

        shortcutsViewSuperview.insertSubview(shortcutsView, aboveSubview: shortcutsSiblingView)

        let pendingShortcutsViewSuperviewConstraints = [
            shortcutsView.placementLayoutGuide.leadingAnchor.constraint(equalTo: shortcutsViewSuperview.leadingAnchor),
            shortcutsView.placementLayoutGuide.trailingAnchor.constraint(equalTo: shortcutsViewSuperview.trailingAnchor),

            shortcutsView.placementLayoutGuide.topAnchor.constraint(equalTo: shortcutsGeometricalPlacementView.topAnchor)
        ]

        shortcutsViewSuperviewConstraints = pendingShortcutsViewSuperviewConstraints

        NSLayoutConstraint.activate(pendingShortcutsViewSuperviewConstraints)
    }

    private func setupInternalViews() {
        
        self.alpha = 0 // Set to 1 in layoutSubviews()

        addSubview(backgroundVisualEffectView)
        backgroundVisualEffectView.translatesAutoresizingMaskIntoConstraints = false
        backgroundVisualEffectView.contentView.isUserInteractionEnabled = true

        addSubview(mainContentView) // f u UIVisualEffectView; its contentView isn't propagating the bounds change when we need it
        mainContentView.isUserInteractionEnabled = true
        mainContentView.translatesAutoresizingMaskIntoConstraints = false

        mainContentView.addSubview(replyToView)
        replyToView.translatesAutoresizingMaskIntoConstraints = false
        
        // Configure the multiple buttons stack and all its buttons
        
        mainContentView.addSubview(multipleButtonsStackView)
        multipleButtonsStackView.translatesAutoresizingMaskIntoConstraints = false
        multipleButtonsStackView.axis = .horizontal
        multipleButtonsStackView.distribution = .fill
        multipleButtonsStackView.alignment = .fill

        let symbolConfig = UIImage.SymbolConfiguration(textStyle: .body)

        // Configure the "+" action button
        
        let symbolConfiguration = UIImage.SymbolConfiguration(textStyle: .body)
        let plusActionImage = UIImage(systemIcon: .plusCircle, withConfiguration: symbolConfiguration)
        let plusAction = UIAction(
            image: plusActionImage,
            state: .on,
            handler: { _ in })
        instantiateAndConfigureButton(button: &plusCircleButton, uiAction: plusAction)
        
        // Configure the remaining action buttons
        
        for action in ObvMessengerSettings.Interface.preferredComposeMessageViewActions.reversed() {
            guard isActionAvailable(for: action) else { continue }
            switch action {
            case .oneTimeEphemeralMessage:
                instantiateAndConfigureButton(button: &flameFillButton, uiAction: uiAction(for: action))
            case .scanDocument:
                instantiateAndConfigureButton(button: &scannerButton, uiAction: uiAction(for: action))
            case .shootPhotoOrMovie:
                instantiateAndConfigureButton(button: &cameraButton, uiAction: uiAction(for: action))
            case .chooseImageFromLibrary:
                instantiateAndConfigureButton(button: &photoButton, uiAction: uiAction(for: action))
            case .choseFile:
                instantiateAndConfigureButton(button: &paperclipButton, uiAction: uiAction(for: action))
            case .introduceThisContact:
                instantiateAndConfigureButton(button: &introduceButton, uiAction: uiAction(for: action))
            case .composeMessageSettings:
                instantiateAndConfigureButton(button: &composeMessageSettingsButton, uiAction: uiAction(for: action))
            }
        }
        
        // Configure the chevron button
        
        let chevron = UIImage(systemIcon: .chevronRightCircle, withConfiguration: symbolConfig)!
        chevronButton = UIButton.systemButton(with: chevron, target: self, action: #selector(chevronButtonTapped))
        chevronButton.translatesAutoresizingMaskIntoConstraints = false
        mainContentView.addSubview(chevronButton)
        freezableButtons.append(chevronButton)
        constrainSizeOfButton(chevronButton)

        // Configure the trash button for audio messages
        
        let trashCircle = UIImage(systemIcon: .trashCircle, withConfiguration: symbolConfig)!
        trashCircleButton = UIButton.systemButton(with: trashCircle, target: self, action: #selector(cancelRecordButtonTapped))
        mainContentView.addSubview(trashCircleButton)
        trashCircleButton.translatesAutoresizingMaskIntoConstraints = false
        freezableButtons.append(trashCircleButton)
        constrainSizeOfButton(trashCircleButton)

        // Configure the text fields bubble, all its label and text views, and the microphone button
        
        mainContentView.addSubview(textFieldBubble)
        textFieldBubble.translatesAutoresizingMaskIntoConstraints = false
        textFieldBubble.backgroundColor = .systemFill
        
        textFieldBubble.addSubview(textViewForTyping)
        textViewForTyping.translatesAutoresizingMaskIntoConstraints = false
        textViewForTyping.font = UIFont.preferredFont(forTextStyle: .body)
        textViewForTyping.maxHeight = 100
        textViewForTyping.backgroundColor = .none
        textViewForTyping.delegate = self
        textViewForTyping.autoGrowingTextViewDelegate = self

        textFieldBubble.addSubview(textPlaceholder)
        textPlaceholder.translatesAutoresizingMaskIntoConstraints = false
        textPlaceholder.font = textViewForTyping.font
        textPlaceholder.textColor = .secondaryLabel
        textPlaceholder.lineBreakMode = .byTruncatingTail
        textPlaceholder.numberOfLines = 1

        textFieldBubble.addSubview(durationLabel)
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.font = textViewForTyping.font
        durationLabel.textColor = .white

        let micro = UIImage(systemIcon: .micFill, withConfiguration: symbolConfig)!
        microButton = UIButton.systemButton(with: micro, target: self, action: #selector(microButtonTapped))
        microButton.tintColor = AppTheme.shared.colorScheme.olvidLight
        textFieldBubble.addSubview(microButton)
        microButton.translatesAutoresizingMaskIntoConstraints = false
        freezableButtons.append(microButton)
        constrainSizeOfButton(microButton)
        
        // Configure the send buttons holder, and the emoji and send buttons
        
        mainContentView.addSubview(sendButtonsHolder)
        sendButtonsHolder.translatesAutoresizingMaskIntoConstraints = false

        let paperplane = UIImage(systemIcon: .paperplaneFill, withConfiguration: symbolConfig)!
        paperplaneButton = UIButton.systemButton(with: paperplane, target: self, action: #selector(paperplaneButtonTapped))
        sendButtonsHolder.addSubview(paperplaneButton)
        paperplaneButton.translatesAutoresizingMaskIntoConstraints = false
        freezableButtons.append(paperplaneButton)
        constrainSizeOfButton(paperplaneButton)

        configureEmojiButton()

        emojiButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body)
        sendButtonsHolder.addSubview(emojiButton)
        emojiButton.translatesAutoresizingMaskIntoConstraints = false
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(emojiButtonTappedOnce))
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(emojiButtonTappedTwice))
        let tripleTap = UITapGestureRecognizer(target: self, action: #selector(emojiButtonTappedThreeTimes))
        doubleTap.numberOfTapsRequired = 2
        tripleTap.numberOfTapsRequired = 3
        doubleTap.require(toFail: tripleTap)
        singleTap.require(toFail: doubleTap)
        emojiButton.addGestureRecognizer(singleTap)
        emojiButton.addGestureRecognizer(doubleTap)
        emojiButton.addGestureRecognizer(tripleTap)
        freezableButtons.append(emojiButton)
        constrainSizeOfButton(emojiButton)
        
        // Configure the attachments collection view
        
        assert(delegate != nil)
        attachmentsCollectionViewController.willMove(toParent: delegate)
        delegate?.addChild(attachmentsCollectionViewController)
        attachmentsCollectionViewController.didMove(toParent: delegate)
        mainContentView.addSubview(attachmentsCollectionViewController.view)
        attachmentsCollectionViewController.view.translatesAutoresizingMaskIntoConstraints = false
        
        // Setup constraints
        
        setupConstraints()

        // Configure the initial state
        
        let newState: State
        if let body = draft.body, !body.isEmpty {
            newState = .multipleButtonsWithText

            let mentionedUsers = draft
                .mentions
                .mentionableIdentityTypesFromRange_WARNING_VIEW_CONTEXT

            let attributedText = ComposeMessageViewAttributedStringBuilder.createInitialMessageAttributedString(
                for: body,
                mentionedUsers: mentionedUsers,
                typingAttributes: Constants.defaultTypingAttributes
            )

            textPlaceholder.attributedText = attributedText

            textViewForTyping.attributedText = attributedText

            textViewForTyping.resetTypingAttributesToDefaults()

        } else {
            newState = .multipleButtonsWithoutText

            textViewForTyping.resetTextInput()
        }

        switchToState(newState: newState, newAttachmentsState: evaluateNewAttachmentState(), animationValues: nil, completionForSendButton: nil)

        // Freeze now if necessary
        
        if currentFreezeId != nil {
            localFreeze()
        }

    }

    private func configureEmojiButton() {
        let defaultEmojiButton = ObvMessengerSettings.Emoji.defaultEmojiButton ?? ObvMessengerConstants.defaultEmoji
        let emojiButtonTitle = draft.discussion.localConfiguration.defaultEmoji ?? defaultEmojiButton

        emojiButton.setTitle(emojiButtonTitle, for: .normal)
    }

    private func updateMultipleButtonsStackView() {
        for view in multipleButtonsStackView.arrangedSubviews {
            multipleButtonsStackView.removeArrangedSubview(view)
        }
        multipleButtonsStackView.addArrangedSubview(plusCircleButton)
        for action in ObvMessengerSettings.Interface.preferredComposeMessageViewActions.reversed() {
            guard isActionAvailable(for: action) else { continue }
            guard let button = button(for: action) else { continue }
            multipleButtonsStackView.addArrangedSubview(button)
        }
    }
    
    private var currentMaximumButtonSizeWithinStackView: CGFloat {
        multipleButtonsStackView.arrangedSubviews
            .compactMap({ $0 as? UIButton })
            .reduce(buttonSize, { max($0, max($1.frame.width, $1.frame.height)) })
    }
    
    
    private var minTextFieldBubbleWidth: CGFloat {
        3*currentMaximumButtonSizeWithinStackView
    }

    private func hideOrShowButtonsForAvailableWidth(forceUpdate: Bool = false) {

        guard !draft.isDeleted else { return }
        guard !multipleButtonsStackView.isHidden else { return }

        let currentAvailableWidth = frame.width - safeAreaInsets.left - safeAreaInsets.right
        guard lastScreenWidthConsideredForMultipleButtonsStackView != currentAvailableWidth || lastButtonWidthConsideredForMultipleButtonsStackView != currentMaximumButtonSizeWithinStackView || forceUpdate else { return }
        lastScreenWidthConsideredForMultipleButtonsStackView = currentAvailableWidth
        lastButtonWidthConsideredForMultipleButtonsStackView = currentMaximumButtonSizeWithinStackView
                
        guard multipleButtonsStackView.arrangedSubviews.count > 1 else { return }

        var availableWidthForButtons = lastScreenWidthConsideredForMultipleButtonsStackView
        availableWidthForButtons -= padding*2 // Left and right paddings
        availableWidthForButtons -= lastButtonWidthConsideredForMultipleButtonsStackView // Send Button
        availableWidthForButtons -= minTextFieldBubbleWidth
        
        let numberOfButtonsThatCanBeDisplayed = max(1, Int(floor(availableWidthForButtons / lastButtonWidthConsideredForMultipleButtonsStackView)))

        let candidates = Array(multipleButtonsStackView.arrangedSubviews[1...].reversed())

        candidates[0..<min(numberOfButtonsThatCanBeDisplayed, candidates.count)].forEach({ $0.isHidden = false })
        candidates[min(numberOfButtonsThatCanBeDisplayed, candidates.count)...].forEach({ $0.isHidden = true })

        let oneCandidateHasNotEnoughWidth = candidates.contains { $0.isHidden }
        if oneCandidateHasNotEnoughWidth {
            // Hide one more candidate and show the plus button
            candidates.last(where: { !$0.isHidden })?.isHidden = true
            multipleButtonsStackView.arrangedSubviews.first?.isHidden = false
        } else {
            // Hide the plus button
            multipleButtonsStackView.arrangedSubviews.first?.isHidden = true
        }
        
        // Prevent animation glitches when rotating the screen
        
        multipleButtonsStackView.arrangedSubviews.forEach({
            $0.alpha = $0.isHidden ? 0.0 : 1.0
        })

        // Finally, if the plus button is shown, configure it with the hidden actions
        if let plusButton = multipleButtonsStackView.arrangedSubviews.first as? UIButton, !plusButton.isHidden {
            let reorderableElements: [UIMenuElement] = ObvMessengerSettings.Interface.preferredComposeMessageViewActions.filter({ $0.canBeReordered }).compactMap({ action in
                guard let button = button(for: action) else { return nil }
                guard button.isHidden else { return nil }
                return uiAction(for: action)
            })
            let unreorderableElements: [UIMenuElement] = ObvMessengerSettings.Interface.preferredComposeMessageViewActions.filter({ !$0.canBeReordered }).compactMap({ action in
                guard let button = button(for: action) else { return nil }
                guard button.isHidden else { return nil }
                return uiAction(for: action)
            })
            assert(!reorderableElements.isEmpty || !unreorderableElements.isEmpty)
            plusButton.menu = UIMenu(children: [
                UIMenu(options: .displayInline, children: reorderableElements),
                UIMenu(options: .displayInline, children: unreorderableElements),
            ])
            plusButton.showsMenuAsPrimaryAction = true
        }
        
    }
    
    
    private func instantiateAndConfigureButton(button: inout UIButton?, uiAction: UIAction?) {
        button = UIButton(type: .system, primaryAction: uiAction)
        button?.setTitle(nil, for: .normal)
        multipleButtonsStackView.addArrangedSubview(button!)
        button!.translatesAutoresizingMaskIntoConstraints = false
        freezableButtons.append(button!)
        constrainSizeOfButton(button!)
        button!.setContentCompressionResistancePriority(.required, for: .horizontal)
        button!.setContentCompressionResistancePriority(.required, for: .vertical)
    }
    
    
    private func setupConstraints() {
        
        // Configure the set of constrains required to show or hide the reply-to view (and hide to reply-to view)

        NSLayoutConstraint.activate([
            mainContentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainContentView.trailingAnchor.constraint(equalTo: trailingAnchor),

            mainContentView.topAnchor.constraint(equalTo: topAnchor),
            mainContentView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])

        constraintsWhenShowingReplyTo = [
            replyToView.topAnchor.constraint(equalTo: topAnchor, constant: padding),
            replyToView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            replyToView.bottomAnchor.constraint(equalTo: textFieldBubble.topAnchor, constant: -padding),
            replyToView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
        ]
        
        constraintsWhenHidingReplyTo = [
            textFieldBubble.topAnchor.constraint(equalTo: topAnchor, constant: padding),
        ]
        
        hideReplyToView()
        
        // Configure the constraints that are common to all states (note that the button sizes are already set in `setupInternalViews()`)
        
        let constraints = [
            backgroundVisualEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundVisualEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),

            backgroundVisualEffectView.topAnchor.constraint(equalTo: topAnchor),
            backgroundVisualEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),

            chevronButton.leadingAnchor.constraint(equalTo: self.safeAreaLayoutGuide.leadingAnchor, constant: padding),
            
            multipleButtonsStackView.leadingAnchor.constraint(equalTo: self.safeAreaLayoutGuide.leadingAnchor, constant: padding),
            
            trashCircleButton.leadingAnchor.constraint(equalTo: self.safeAreaLayoutGuide.leadingAnchor, constant: padding),
            trashCircleButton.bottomAnchor.constraint(equalTo: attachmentsCollectionViewController.view.topAnchor, constant: -padding),

            textFieldBubble.trailingAnchor.constraint(equalTo: sendButtonsHolder.leadingAnchor),
        
            sendButtonsHolder.trailingAnchor.constraint(equalTo: self.safeAreaLayoutGuide.trailingAnchor, constant: -padding),

            paperplaneButton.topAnchor.constraint(equalTo: sendButtonsHolder.topAnchor),
            paperplaneButton.trailingAnchor.constraint(equalTo: sendButtonsHolder.trailingAnchor),
            paperplaneButton.bottomAnchor.constraint(equalTo: sendButtonsHolder.bottomAnchor),
            paperplaneButton.leadingAnchor.constraint(equalTo: sendButtonsHolder.leadingAnchor),

            emojiButton.topAnchor.constraint(equalTo: sendButtonsHolder.topAnchor),
            emojiButton.trailingAnchor.constraint(equalTo: sendButtonsHolder.trailingAnchor),
            emojiButton.bottomAnchor.constraint(equalTo: sendButtonsHolder.bottomAnchor),
            emojiButton.leadingAnchor.constraint(equalTo: sendButtonsHolder.leadingAnchor),

            attachmentsCollectionViewController.view.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            attachmentsCollectionViewController.view.bottomAnchor.constraint(equalTo: mainContentView.safeAreaLayoutGuide.bottomAnchor),
            attachmentsCollectionViewController.view.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            
        ]
        NSLayoutConstraint.activate(constraints)
        
        textFieldBubble.setContentHuggingPriority(.defaultLow, for: .vertical)

        // Configure the set of constraints that depend on the state of the interface
        
        for state in State.allCases {
            switch state {
            case .initial:
                constraintsForState[state] = []
                viewsToShowForState[state] = []
            case .multipleButtonsWithoutText:
                constraintsForState[state] = [
                    textFieldBubble.topAnchor.constraint(equalTo: multipleButtonsStackView.topAnchor),
                    multipleButtonsStackView.trailingAnchor.constraint(equalTo: textFieldBubble.leadingAnchor),
                    textPlaceholder.leadingAnchor.constraint(equalTo: textFieldBubble.leadingAnchor, constant: padding),
                    textPlaceholder.centerYAnchor.constraint(equalTo: textFieldBubble.centerYAnchor),
                    microButton.centerYAnchor.constraint(equalTo: textFieldBubble.centerYAnchor),
                    microButton.trailingAnchor.constraint(equalTo: textFieldBubble.trailingAnchor),
                ]
                viewsToShowForState[state] = [
                    multipleButtonsStackView, textPlaceholder, microButton
                ]
            case .multipleButtonsWithText:
                constraintsForState[state] = [
                    textFieldBubble.topAnchor.constraint(equalTo: multipleButtonsStackView.topAnchor),
                    multipleButtonsStackView.trailingAnchor.constraint(equalTo: textFieldBubble.leadingAnchor),
                    textPlaceholder.leadingAnchor.constraint(equalTo: textFieldBubble.leadingAnchor, constant: padding),
                    textPlaceholder.trailingAnchor.constraint(equalTo: textFieldBubble.trailingAnchor, constant: -padding),
                    textPlaceholder.centerYAnchor.constraint(equalTo: textFieldBubble.centerYAnchor),
                ]
                viewsToShowForState[state] = [
                    multipleButtonsStackView, textPlaceholder
                ]
            case .typing:
                let growBubbleConstraint = textFieldBubble.heightAnchor.constraint(equalTo: textViewForTyping.heightAnchor, constant: 2*padding)
                growBubbleConstraint.priority = .defaultHigh // Larger than the constraints that pins the buttons to the top, smaller than the minimum height constraint on the bubble
                let minimumBubbleHeightConstraint = textFieldBubble.heightAnchor.constraint(greaterThanOrEqualTo: chevronButton.heightAnchor)
                minimumBubbleHeightConstraint.priority = .required
                constraintsForState[state] = [
                    growBubbleConstraint,
                    minimumBubbleHeightConstraint,
                    chevronButton.trailingAnchor.constraint(equalTo: textFieldBubble.leadingAnchor),
                    textViewForTyping.centerYAnchor.constraint(equalTo: textFieldBubble.centerYAnchor),
                    textViewForTyping.trailingAnchor.constraint(equalTo: textFieldBubble.trailingAnchor, constant: -padding),
                    textViewForTyping.leadingAnchor.constraint(equalTo: textFieldBubble.leadingAnchor, constant: padding),
                ]
                viewsToShowForState[state] = [
                    chevronButton, textViewForTyping
                ]
            case .recording:
                constraintsForState[state] = [
                    textFieldBubble.topAnchor.constraint(equalTo: trashCircleButton.topAnchor),
                    trashCircleButton.trailingAnchor.constraint(equalTo: textFieldBubble.leadingAnchor),
                    microButton.centerYAnchor.constraint(equalTo: textFieldBubble.centerYAnchor),
                    microButton.trailingAnchor.constraint(equalTo: textFieldBubble.trailingAnchor),
                    durationLabel.leadingAnchor.constraint(equalTo: textFieldBubble.leadingAnchor, constant: padding),
                    durationLabel.centerYAnchor.constraint(equalTo: textFieldBubble.centerYAnchor),
                ]
                viewsToShowForState[state] = [
                    trashCircleButton, microButton, durationLabel
                ]
            }
        }
        
        for attachmentsState in AttachmentsState.allCases {
            switch attachmentsState {
            case .noAttachment:
                constraintsForAttachmentsState[attachmentsState] = [
                    chevronButton.bottomAnchor.constraint(equalTo: mainContentView.safeAreaLayoutGuide.bottomAnchor, constant: -padding),
                    multipleButtonsStackView.bottomAnchor.constraint(equalTo: mainContentView.safeAreaLayoutGuide.bottomAnchor, constant: -padding),
                    textFieldBubble.bottomAnchor.constraint(equalTo: mainContentView.safeAreaLayoutGuide.bottomAnchor, constant: -padding),
                    sendButtonsHolder.bottomAnchor.constraint(equalTo: mainContentView.safeAreaLayoutGuide.bottomAnchor, constant: -padding),
                ]
                viewsToShowForAttachmentsState[attachmentsState] = []
            case .hasAttachments:
                constraintsForAttachmentsState[attachmentsState] = [
                    chevronButton.bottomAnchor.constraint(equalTo: attachmentsCollectionViewController.view.topAnchor, constant: -padding),
                    multipleButtonsStackView.bottomAnchor.constraint(equalTo: attachmentsCollectionViewController.view.topAnchor, constant: -padding),
                    textFieldBubble.bottomAnchor.constraint(equalTo: attachmentsCollectionViewController.view.topAnchor, constant: -padding),
                    sendButtonsHolder.bottomAnchor.constraint(equalTo: attachmentsCollectionViewController.view.topAnchor, constant: -padding),
                ]
                viewsToShowForAttachmentsState[attachmentsState] = [attachmentsCollectionViewController.view]
            }
        }
                
    }
    
    
    /// Used to set the width and height constraints of all buttons of this view
    private func constrainSizeOfButton(_ button: UIButton) {
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: buttonSize),
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: buttonSize),
            button.widthAnchor.constraint(equalTo: button.heightAnchor),
        ])
    }
    
    
    /// We return .zero since this implies the use of autolayout
    override var intrinsicContentSize: CGSize { .zero }

    
    func discussionViewDidAppear() {
        guard !discussionViewDidAppearWasCalled else { return }
        discussionViewDidAppearWasCalled = true
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
        textFieldBubble.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(textFieldBubbleWasTapped)))
        notificationTokens.append(contentsOf: [
            ObvMessengerInternalNotification.observeDraftExpirationWasBeenUpdated(queue: OperationQueue.main) { [weak self] draftObjectID in
                self?.processDraftExpirationWasUpdated(draftObjectID) },
        ])
        if currentFreezeId != nil {
            delegateViewController?.showHUD(type: .progress(progress: currentFreezeProgress))
        }
    }

    func discussionViewWillDisappear() {
        saveDraftImmediatelySubject.send()

        if ObvAudioRecorder.shared.isRecording {
            ObvAudioRecorder.shared.cancelRecording()
        }
    }
    
    
    private func processDraftExpirationWasUpdated(_ draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) {
        assert(Thread.isMainThread)
        guard draft.typedObjectID == draftObjectID else { return }
        switchToState(newState: currentState, newAttachmentsState: evaluateNewAttachmentState(), animationValues: buttonsAnimationValues, completionForSendButton: nil)
    }

    private func continuouslySaveDraftText() {
        let draftObjectID = draft.typedObjectID

        Publishers.CombineLatest3(
            textPublisher
                .removeDuplicates(),
            mentionsPublisher
                .removeDuplicates(),
            saveDraftImmediatelyPublisher
                .prepend(()))
        .map { draftBody, mentions, _ -> (DraftBodyWithId, Set<MessageJSON.UserMention>) in
            return (draftBody, mentions)
        }
        .debounce(for: 0.5, scheduler: RunLoop.main)
        .filter { [weak self] in
            $0.0.id == self?.currentDraftId
        }
        .sink(receiveValue: { [weak self] (body, mentions) in
            guard let _self = self else { return }
            NewSingleDiscussionNotification.userWantsToUpdateDraftBodyAndMentions(draftObjectID: draftObjectID,
                                                                                  body: body.body,
                                                                                  mentions: mentions)
            .postOnDispatchQueue(_self.internalQueue)
        })
        .store(in: &cancellables)
    }

    private func processPreferredComposeMessageViewActionsDidChange() {
        updateMultipleButtonsStackView()
        hideOrShowButtonsForAvailableWidth(forceUpdate: true)
    }

    @objc private func handleAudioInterruption(_ notification: Notification) {
        assert(Thread.isMainThread)
        stopRecordingAudioMessage()
    }
}



// MARK: - Action called by the `CompositionViewFreezeManager`

@available(iOS 15.0, *)
extension NewComposeMessageView {
    
    /// Exclusively called by the `CompositionViewFreezeManager`
    func freeze(withFreezeId freezeId: UUID) {
        assert(Thread.isMainThread)
        assert(currentFreezeId == nil)
        currentFreezeId = freezeId
        localFreeze()
    }
    
    
    private func localFreeze() {
        assert(Thread.isMainThread)
        assert(currentFreezeId != nil)
        guard currentFreezeId != nil else { return }
        freezableButtons.forEach({ $0.isUserInteractionEnabled = false })
        freezableButtons.forEach({ $0.isEnabled = false })
        textViewForTyping.lookLikeNotEditable()
    }


    /// Exclusively called by the `CompositionViewFreezeManager` or from one of the other "unfreeze" methods called by this singleton.
    func unfreeze(withFreezeId freezeId: UUID, success: Bool) {
        assert(Thread.isMainThread)
        guard currentFreezeId == freezeId else { assertionFailure(); return }
        currentFreezeId = nil
        let newState: State
        if currentState == .typing {
            newState = .typing
        } else {
            newState = textViewForTyping.hasText ? .multipleButtonsWithText : .multipleButtonsWithoutText
        }
        switchToState(newState: newState, newAttachmentsState: evaluateNewAttachmentState(), animationValues: buttonsAnimationValues) { [weak self] in
            guard let _self = self else { return }
            if _self.currentAttachmentsState == .hasAttachments {
                assert(_self.currentSendButtonType == .paperplane)
            }
            self?.freezableButtons.forEach({ $0.isUserInteractionEnabled = true })
            self?.freezableButtons.forEach({ $0.isEnabled = true })
            self?.textViewForTyping.lookLikeEditable()
            self?.delegateViewController?.hideHUD()
        }
    }
    
    
    func unfreezeAfterDraftToSendWasReset(_ sentDraftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, freezeId: UUID) {
        assert(Thread.isMainThread)
        guard draft.objectPermanentID == sentDraftPermanentID else { return }
        textViewForTyping.attributedText = nil
        textViewForTyping.resetTextInput()
        textPlaceholder.isHidden = false
        unfreeze(withFreezeId: freezeId, success: true)
    }

    
    func unfreezeAfterDraftCouldNotBeSent(_ sentDraftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, freezeId: UUID) {
        assert(Thread.isMainThread)
        guard draft.objectPermanentID == sentDraftPermanentID else { return }
        unfreeze(withFreezeId: freezeId, success: false)
    }
    
    
    func newFreezeProgressAvailable(_ sentDraftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, freezeId: UUID, progress: Progress) {
        assert(Thread.isMainThread)
        guard draft.objectPermanentID == sentDraftPermanentID else { return }
        guard currentFreezeId == freezeId else { return }
        delegateViewController?.showHUD(type: .progress(progress: progress))
    }

}



// MARK: - Tap actions

@available(iOS 15.0, *)
extension NewComposeMessageView {
    
    private func paperclipButtonTapped() {
        // See UTCoreTypes.h for types
        // Since we have kUTTypeItem, other elements in the array may be useless
        let documentTypes: [UTType] = [.image, .movie, .pdf, .data, .item]
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: documentTypes, asCopy: true)
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = true
        animatedEndEditing { [weak self] _ in
            self?.delegateViewController?.present(documentPicker, animated: true)
        }
    }
    
    
    private func introduceButtonTapped() {
        switch try? draft.discussion.kind {
        case .oneToOne(withContactIdentity: let contactIdentity):
            guard let contactObjectID = contactIdentity?.typedObjectID else { return }
            guard let viewController = self.delegate else { return }
            ObvMessengerInternalNotification.userWantsToDisplayContactIntroductionScreen(contactObjectID: contactObjectID, viewController: viewController)
                .postOnDispatchQueue()
        case .groupV1, .groupV2, .none:
            assertionFailure()
        }
    }
    
    
    private func photoButtonTapped() {
        guard UIImagePickerController.isSourceTypeAvailable(.photoLibrary) else { return }
        var configuration = PHPickerConfiguration()
        configuration.selectionLimit = 0
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        animatedEndEditing { [weak self] _ in
            self?.delegateViewController?.present(picker, animated: true)
        }
    }

    
    private func cameraButtonTapped() {
        guard ObvMessengerConstants.isRunningOnRealDevice else { return }
        switch AVCaptureDevice.authorizationStatus(for: AVMediaType.video) {
        case .authorized:
            setupAndPresentCaptureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async {
                        self?.setupAndPresentCaptureSession()
                    }
                }
            }
        case .denied,
             .restricted:
            let NotificationType = MessengerInternalNotification.UserTriedToAccessCameraButAccessIsDenied.self
            NotificationCenter.default.post(name: NotificationType.name, object: nil)
        @unknown default:
            assertionFailure("A recent AVCaptureDevice.authorizationStatus is not properly handled")
            return
        }
    }
    
    
    private func setupAndPresentCaptureSession() {
        assert(Thread.isMainThread)
        let imagePicker = UIImagePickerController()
        imagePicker.sourceType = .camera
        imagePicker.mediaTypes = [kUTTypeImage, kUTTypeMovie] as [String]
        imagePicker.delegate = self
        imagePicker.allowsEditing = false
        animatedEndEditing { [weak self] _ in
            self?.delegateViewController?.present(imagePicker, animated: true)
        }
    }
    
    
    private func scannerButtonTapped() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) && VNDocumentCameraViewController.isSupported else { return }
        switch AVCaptureDevice.authorizationStatus(for: AVMediaType.video) {
        case .authorized:
            setupAndPresentDocumentCameraViewController()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async {
                        self?.setupAndPresentDocumentCameraViewController()
                    }
                }
            }
        case .denied,
             .restricted:
            let NotificationType = MessengerInternalNotification.UserTriedToAccessCameraButAccessIsDenied.self
            NotificationCenter.default.post(name: NotificationType.name, object: nil)
        @unknown default:
            assertionFailure("A recent AVCaptureDevice.authorizationStatus is not properly handled")
            return
        }
    }

    func switchToAppropriateRecordingState() {
        if ObvAudioRecorder.shared.isRecording {
            switchToState(newState: .recording, newAttachmentsState: evaluateNewAttachmentState(), animationValues: buttonsAnimationValues, completionForSendButton: nil)
            microButton.tintColor = .red
        } else {
            switchToState(newState: .multipleButtonsWithoutText, newAttachmentsState: evaluateNewAttachmentState(), animationValues: buttonsAnimationValues, completionForSendButton: nil)
            microButton.tintColor = AppTheme.shared.colorScheme.olvidLight
        }
    }

    @objc func microButtonTapped() {
        assert(Thread.isMainThread)
        let log = self.log
        if ObvAudioRecorder.shared.isRecording {
            stopRecordingAudioMessage()
        } else {
            animatedEndEditing { [weak self] _ in
                guard let _self = self else { return }
                ObvAudioRecorder.shared.delegate = _self
                let uti = AVFileType.m4a.rawValue
                guard let fileExtention = ObvUTIUtils.preferredTagWithClass(inUTI: uti, inTagClass: .FilenameExtension) else { return }
                let name = "Recording @ \(_self.dateFormatter.string(from: Date()))"
                let tempFileName = [name, fileExtention].joined(separator: ".")
                let url = ObvUICoreDataConstants.ContainerURL.forTempFiles.appendingPathComponent(tempFileName)

                let settings = [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVSampleRateKey: 44_100,
                    AVEncoderBitRateKey: 48_000,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
                ]

                ObvAudioRecorder.shared.startRecording(url: url, settings: settings) { result in
                    switch result {
                    case .success:
                        os_log("🎤 Start Recording", log: log, type: .info)
                        DispatchQueue.main.async { [weak self] in
                            self?.switchToAppropriateRecordingState()
                            self?.recordDurationTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { timer in
                                assert(Thread.isMainThread)
                                guard ObvAudioRecorder.shared.isRecording else {
                                    timer.invalidate()
                                    self?.recordDurationTimer = nil
                                    return
                                }
                                guard let duration = ObvAudioRecorder.shared.duration else { return }
                                self?.durationLabel.text = _self.durationFormatter.string(from: duration)
                            }
                        }
                        return
                    case .failure(let error):
                        switch error {
                        case .recordingInProgress:
                            assertionFailure()
                        case .noRecordPermission:
                            ObvMessengerInternalNotification.voiceMessageFailedBecauseUserDeniedRecordPermission
                                .postOnDispatchQueue()
                        case .audioSessionError(let error):
                            os_log("🎤 Failed to record: audio session error %{public}@", log: _self.log, type: .fault, error.localizedDescription)
                            assertionFailure()
                        case .audioRecorderError(let error):
                            os_log("🎤 Failed to record: audio recorder error %{public}@", log: _self.log, type: .fault, error.localizedDescription)
                            assertionFailure()
                        }
                        return
                    }
                }
            }
        }
    }
    
    
    private func stopRecordingAudioMessage() {
        assert(Thread.isMainThread)
        guard ObvAudioRecorder.shared.isRecording else { return }
        let draftPermanentID = draft.objectPermanentID
        do { try CompositionViewFreezeManager.shared.freeze(self) } catch { assertionFailure() }
        ObvAudioRecorder.shared.stopRecording { [weak self] result in
            guard let _self = self else { return }
            switch result {
            case .success(let url):
                NewSingleDiscussionNotification.userWantsToAddAttachmentsToDraftFromURLs(draftPermanentID: draftPermanentID, urls: [url]) { success in
                    do { try CompositionViewFreezeManager.shared.unfreeze(draftPermanentID, success: success) } catch { assertionFailure() }
                }
                .postOnDispatchQueue()
                _self.switchToAppropriateRecordingState()
            case .failure(let error):
                os_log("🎤 Failed to record: %{public}@", log: _self.log, type: .fault, error.localizedDescription)
                _self.cancelRecordButtonTapped()
            }
        }
    }
    

    @objc func cancelRecordButtonTapped() {
        ObvAudioRecorder.shared.cancelRecording()
        switchToAppropriateRecordingState()
    }
    
    
    private func flameFillButtonTapped() {
        guard let vc = DraftSettingsHostingViewController(draft: draft) else {
            assertionFailure()
            return
        }
        if let sheet = vc.sheetPresentationController {
            sheet.detents = [ .medium() ]
            sheet.prefersGrabberVisible = true
            sheet.delegate = vc
            sheet.preferredCornerRadius = 30.0
        }
        animatedEndEditing { [weak self] _ in
            self?.delegateViewController?.present(vc, animated: true)
        }
    }

    private func composeMessageSettingsButtonTapped() {
        let vc = ComposeMessageViewSettingsViewController(input: .local(configuration: draft.discussion.localConfiguration))
        if let sheet = vc.sheetPresentationController {
            sheet.detents = [ .large() ]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 30.0
        }
        let nav = ObvNavigationController(rootViewController: vc)
        vc.navigationItem.rightBarButtonItem = UIBarButtonItem.forClosing(target: self, action: #selector(dismissComposeMessageViewSettingsViewController))
        animatedEndEditing { [weak self] _ in
            self?.delegateViewController?.present(nav, animated: true)
        }
    }

    @objc private func dismissComposeMessageViewSettingsViewController() {
        self.delegateViewController?.presentedViewController?.dismiss(animated: true)
    }
    
    func animatedEndEditing(completion: @escaping (Bool) -> Void) {
        guard textViewForTyping.isFirstResponder else {
            completion(true)
            return
        }
        endEditing(true)
        setNeedsLayout()
        UIView.animate(withDuration: 0.3) { [weak self] in
            self?.layoutIfNeeded()
        } completion: { finished in
            completion(finished)
        }

    }

    private func setupAndPresentDocumentCameraViewController() {
        assert(Thread.isMainThread)
        let documentCameraViewController = VNDocumentCameraViewController()
        documentCameraViewController.delegate = self
        animatedEndEditing { [weak self] _ in
            self?.delegateViewController?.present(documentCameraViewController, animated: true)
        }
    }


    @objc func chevronButtonTapped() {
        assert(currentState == .typing)
        let newState: State = textViewForTyping.hasText ? .multipleButtonsWithText : .multipleButtonsWithoutText
        switchToState(newState: newState, newAttachmentsState: evaluateNewAttachmentState(), animationValues: buttonsAnimationValues, completionForSendButton: nil)
    }
    

    @objc func textFieldBubbleWasTapped() {
        guard currentState != .recording else { return }
        textFieldBubbleWasJustTapped = true
        if textViewForTyping.isFirstResponder {
            switchToState(newState: .typing, newAttachmentsState: evaluateNewAttachmentState(), animationValues: buttonsAnimationValues, completionForSendButton: nil)
        } else {
            textViewForTyping.becomeFirstResponder()
            // The state is switched when the keyboard appears
        }
    }
    
    
    @objc func paperplaneButtonTapped() {
        do { try CompositionViewFreezeManager.shared.freeze(self) } catch { assertionFailure() }
        switch currentState {
        case .initial:
            do { try CompositionViewFreezeManager.shared.unfreeze(draft.objectPermanentID, success: true) } catch { assertionFailure() }
            return
        case .recording:
            if ObvAudioRecorder.shared.isRecording {
                let draftPermanentID = draft.objectPermanentID
                ObvAudioRecorder.shared.stopRecording { [weak self] result in
                    guard let _self = self else { return }
                    switch result {
                    case .success(let url):
                        NewSingleDiscussionNotification.userWantsToSendDraftWithOneAttachment(draftPermanentID: draftPermanentID, attachmentURL: url)
                            .postOnDispatchQueue()
                    case .failure(let error):
                        os_log("🎤 Failed to record: %{public}@", log: _self.log, type: .fault, error.localizedDescription)
                    }
                    DispatchQueue.main.async {
                        _self.switchToAppropriateRecordingState()
                    }
                }
            }
        case .typing, .multipleButtonsWithoutText, .multipleButtonsWithText:
            let textBody = textViewForTyping.textStorage.string
            sendUserWantsToSendDraftNotification(with: textBody, mentions: mentionsSubject.value)
        }
    }
    
    
    @objc func emojiButtonTappedOnce() {
        emojiButtonTapped(numberOfTimes: 1)
    }

    @objc func emojiButtonTappedTwice() {
        emojiButtonTapped(numberOfTimes: 2)
    }
    
    @objc func emojiButtonTappedThreeTimes() {
        emojiButtonTapped(numberOfTimes: 3)
    }

    private func emojiButtonTapped(numberOfTimes: Int) {
        guard textViewForTyping.textStorage.string.trimmingWhitespacesAndNewlines().isEmpty else { return } // This happens if the user is really fast
        guard let buttonTitle = emojiButton.title(for: .normal) else { return }
        guard buttonTitle.isSingleEmoji else { return }
        let textBody = String(repeating: buttonTitle, count: numberOfTimes)
        do { try CompositionViewFreezeManager.shared.freeze(self) } catch { assertionFailure() }
        sendUserWantsToSendDraftNotification(with: textBody, mentions: mentionsSubject.value)
    }

    private func sendUserWantsToSendDraftNotification(with textBody: String, mentions: Set<MessageJSON.UserMention>) {
        shortcutsView.configure(with: [], animated: true)
        currentDraftId = UUID()
        NewSingleDiscussionNotification.userWantsToSendDraft(draftPermanentID: draft.objectPermanentID,
                                                             textBody: textBody,
                                                             mentions: Set(mentions))
            .postOnDispatchQueue()
    }

}

@available(iOS 15.0, *)
extension NewComposeMessageView: ObvAudioRecorderDelegate {

    func recordingHasFailed() {
        self.microButton.tintColor = nil
    }

}


// MARK: - Updating this view when states change

@available(iOS 15.0, *)
extension NewComposeMessageView {
    
    enum State: CaseIterable {
        case initial
        case multipleButtonsWithText
        case multipleButtonsWithoutText
        case typing
        case recording
        
        var debugDescription: String {
            switch self {
            case .initial: return "initial"
            case .multipleButtonsWithText: return "multipleButtonsWithText"
            case .multipleButtonsWithoutText: return "multipleButtonsWithoutText"
            case .typing: return "typing"
            case .recording: return "recording"
            }
        }
        
    }
        
    enum AttachmentsState: CaseIterable {
        case noAttachment
        case hasAttachments

        var debugDescription: String {
            switch self {
            case .noAttachment: return "noAttachment"
            case .hasAttachments: return "hasAttachments"
            }
        }

    }

    private enum SendButtonType {
        case emoji
        case paperplane
        
        var debugDescription: String {
            switch self {
            case .emoji: return "emoji"
            case .paperplane: return "paperplane"
            }
        }

    }

    
    /// Call this method to switch to another type of button holder type, for example, when tapping the text field we want to hide all the unecessary buttons and thus switch to the `.singleButton`
    /// type.
    ///
    /// This method can be called with animation values. When this is the case, the transition is animated using these values. When calling this method from within a keyboard notification callback,
    /// we use the animation values found within the user infos of the keyboard notifications so as to animate the button holder type transition alongside the keyboard. When tapping, e.g.,
    /// the chevron button, we cannot use the keyboard values (it just doesn't work) and we use "default" values for the animation.
    ///
    /// Although the `newAttachmentsState` could be computed locally, we keep it in the arguments to make it clear that the `AttachmentsState` is part of this view state.
    private func switchToState(newState: State, newAttachmentsState: AttachmentsState, animationValues: (duration: Double, options: UIView.AnimationOptions)?, completionForSendButton: (() -> Void)?) {

        guard newState != .initial else { return }
        
        let animationDebugId = String(UUID().uuidString.prefix(5))
        
        debugPrint("🎹 [\(animationDebugId)] Call to switchToState: (\(currentState.debugDescription), \(currentAttachmentsState.debugDescription)) to (\(newState.debugDescription), \(newAttachmentsState.debugDescription))")
        
        // We want successive calls to be executed in order.
        // We asynchronously dispatch the call to the DispatchGroup to prevent a deadlock

        queueForCoordinatingStateSwitches.async { [weak self] in
            guard let _self = self else { return }
            
            _self.dispatchGroupForCoordinatingStateSwitches.wait()
            _self.dispatchGroupForCoordinatingStateSwitches.enter()
            
            guard _self.currentState != newState || _self.currentAttachmentsState != newAttachmentsState else {
                debugPrint("🎹 [\(animationDebugId)] No need to animate")
                // We still need to perform an atomic switch (since newState and newAttachmentsState do not capture the full state of the UI, yes, this is a bad design).
                DispatchQueue.main.async {
                    _self.atomicSwitchToState(newState: newState, newAttachmentsState: newAttachmentsState, completionForSendButton: completionForSendButton)
                    _self.dispatchGroupForCoordinatingStateSwitches.leave()
                }
                return
            }
            
            DispatchQueue.main.async {
                if let animationValues = animationValues {
                    
                    debugPrint("🎹 [\(animationDebugId)] Animated switch: (\(_self.currentState.debugDescription), \(_self.currentAttachmentsState.debugDescription)) to (\(newState.debugDescription), \(newAttachmentsState.debugDescription)) ")
                    _self.animatedSwitchToState(newState: newState, newAttachmentsState: newAttachmentsState, completionForSendButton: completionForSendButton, animationDebugId: animationDebugId, animationValues: animationValues) { [weak self] in
                        self?.dispatchGroupForCoordinatingStateSwitches.leave()
                    }

                } else {
                    
                    debugPrint("🎹 [\(animationDebugId)] Atomic switch: (\(_self.currentState.debugDescription), \(_self.currentAttachmentsState.debugDescription)) to (\(newState.debugDescription), \(newAttachmentsState.debugDescription)) ")
                    _self.atomicSwitchToState(newState: newState, newAttachmentsState: newAttachmentsState, completionForSendButton: completionForSendButton)
                    _self.dispatchGroupForCoordinatingStateSwitches.leave()

                }
            }

        }
    }
    
    
    private func animatedSwitchToState(newState: State, newAttachmentsState: AttachmentsState, completionForSendButton: (() -> Void)?, animationDebugId: String, animationValues: (duration: Double, options: UIView.AnimationOptions), completion: @escaping () -> Void) {
        
        assert(Thread.isMainThread)
        
        debugPrint("🎹 [\(animationDebugId)] Step 1")

        let animatedLayoutIsNeeded = adjustConstraintsForState(newState: newState, newAttachmentsState: newAttachmentsState)
        unhideViewsForState(newState: newState)

        textViewForTyping.setNeedsLayout() // this is needed due to height issues, see comment within ``NewComposeMessageView.atomicSwitchToState(newState:newAttachmentsState:completionForSendButton:)``

        textViewForTyping.layoutIfNeeded()

        let finalAnimationOptions: UIView.AnimationOptions = {
            var _value = animationValues.options

            _value.insert(.beginFromCurrentState)

            _value.insert(.layoutSubviews)

            return _value
        }()

        UIView.animate(withDuration: animationValues.duration, delay: 0.0, options: finalAnimationOptions) { [weak self] in
            
            self?.configureViewsContentAndStyleForState(newState: newState)
            self?.textViewForTyping.layoutIfNeeded()
            if animatedLayoutIsNeeded {
                self?.layoutIfNeeded()
            }
            self?.adjustAlphasForState(newState: newState)
            
            debugPrint("🎹 [\(animationDebugId)] Step 2")

        } completion: { [weak self] _ in
            
            self?.hideViewsForState(newState: newState)
            self?.unhideViewsForAttachmentsState(newAttachmentsState: newAttachmentsState)
            
            debugPrint("🎹 [\(animationDebugId)] Step 3")

            UIView.animate(withDuration: animationValues.duration, delay: 0.0) { [weak self] in
                
                self?.adjustAlphasForAttachmentsState(newAttachmentsState: newAttachmentsState)
                
                debugPrint("🎹 [\(animationDebugId)] Step 4")

            } completion: { [weak self] _ in
                
                self?.hideViewsForAttachmentsState(newAttachmentsState: newAttachmentsState)
                self?.currentState = newState
                self?.currentAttachmentsState = newAttachmentsState

                self?.atomicSwitchToState(newState: newState, newAttachmentsState: newAttachmentsState, completionForSendButton: completionForSendButton)

                debugPrint("🎹 [\(animationDebugId)] Step 5")
                
                completion()
                
            }
        }

    }
    
    
    private func atomicSwitchToState(newState: State, newAttachmentsState: AttachmentsState, completionForSendButton: (() -> Void)?) {
        assert(Thread.isMainThread)
        _ = adjustConstraintsForState(newState: newState, newAttachmentsState: newAttachmentsState)
        configureViewsContentAndStyleForState(newState: newState)
        unhideViewsForState(newState: newState)
        adjustAlphasForState(newState: newState)
        hideViewsForState(newState: newState)
        unhideViewsForAttachmentsState(newAttachmentsState: newAttachmentsState)
        adjustAlphasForAttachmentsState(newAttachmentsState: newAttachmentsState)
        hideViewsForAttachmentsState(newAttachmentsState: newAttachmentsState)
        currentState = newState
        currentAttachmentsState = newAttachmentsState
        switchToAppropriateSendButton(animate: true, completion: completionForSendButton)
        textViewForTyping.setNeedsLayout() //the call to dirty `textViewForTyping`'s layout is required despite teh call below to `layoutIfNeeded()` due to height issues with the actual textview's content 🤷
        textViewForTyping.layoutIfNeeded()
    }


    /// The completion handler makes it possible to unfreeze the send button *after* it has changed state
    private func switchToAppropriateSendButton(animate: Bool, completion: (() -> Void)?) {

        assert(Thread.isMainThread)
                
        let hasContentToSend = (textViewForTyping.hasText && !textViewForTyping.text.trimmingWhitespacesAndNewlines().isEmpty) || numberOfAttachments > 0 || ObvAudioRecorder.shared.isRecording
        let type: SendButtonType = hasContentToSend ? .paperplane : .emoji
        
        guard currentSendButtonType != type else { completion?(); return }
        currentSendButtonType = type

        if animate {

            sendButtonAnimator.pauseAnimation()
            sendButtonAnimator.addAnimations { [weak self] in
                guard let _self = self else { return }
                switch type {
                case .paperplane:
                    _self.emojiButton.alpha = 0.0
                    _self.paperplaneButton.alpha = 1.0
                    _self.emojiButton.transform = .init(scaleX: 0, y: 0)
                    _self.paperplaneButton.transform = .init(scaleX: 1, y: 1)
                case .emoji:
                    _self.emojiButton.alpha = 1.0
                    _self.paperplaneButton.alpha = 0.0
                    _self.emojiButton.transform = .init(scaleX: 1, y: 1)
                    _self.paperplaneButton.transform = .init(scaleX: 0, y: 0)
                }
            }
            sendButtonAnimator.addCompletion({ _ in completion?()})
            sendButtonAnimator.startAnimation()

        } else {

            switch type {
            case .paperplane:
                emojiButton.alpha = 0.0
                paperplaneButton.alpha = 1.0
            case .emoji:
                emojiButton.alpha = 1.0
                paperplaneButton.alpha = 0.0
            }

            completion?()
        }
        
    }

    
    /// This method should only be called from the `switchToState` method
    private func configureViewsContentAndStyleForState(newState: State) {
        switch newState {
        case .multipleButtonsWithoutText, .initial:
            textPlaceholder.textColor = .secondaryLabel
            textPlaceholder.text = "Aa"
            textFieldBubble.backgroundColor = .systemFill
        case .multipleButtonsWithText:
            textPlaceholder.textColor = .label
            textPlaceholder.attributedText = textViewForTyping.textStorage
            textFieldBubble.backgroundColor = .systemFill
        case .typing:
            textFieldBubble.backgroundColor = .systemFill
        case .recording:
            textFieldBubble.backgroundColor = AppTheme.shared.colorScheme.olvidLight
        }
        flameFillButton.tintColor = draft.hasSomeExpiration ? .red : .systemBlue
    }
    
    
    /// This method should only be called from the `switchToState` method
    private func adjustAlphasForState(newState: State) {
        State.allCases.forEach {
            viewsToShowForState[$0]?.filter({ !viewsToShowForState[newState]!.contains($0) }).forEach { $0.alpha = 0.0 }
        }
        viewsToShowForState[newState]?.forEach { $0.alpha = 1.0 }
    }

    
    /// This method should only be called from the `switchToState` method
    private func adjustAlphasForAttachmentsState(newAttachmentsState: AttachmentsState) {
        AttachmentsState.allCases.forEach {
            viewsToShowForAttachmentsState[$0]?.filter({ !viewsToShowForAttachmentsState[newAttachmentsState]!.contains($0) }).forEach { $0.alpha = 0.0 }
        }
        viewsToShowForAttachmentsState[newAttachmentsState]?.forEach { $0.alpha = 1.0 }
    }

    
    /// This method should only be called from the `switchToState` method
    private func hideViewsForState(newState: State) {
        // We hide all the views that are not part of the `viewsToShowForState` of the `newState`
        State.allCases.filter({ $0 != newState }).forEach {
            viewsToShowForState[$0]?.forEach {
                if !viewsToShowForState[newState]!.contains($0) {
                    $0.isHidden = true
                }
            }
        }
    }

    
    /// This method should only be called from the `switchToState` method
    private func hideViewsForAttachmentsState(newAttachmentsState: AttachmentsState) {
        // We hide all the views that are not part of the `viewsToShowForState` of the `newState`
        AttachmentsState.allCases.filter({ $0 != newAttachmentsState }).forEach {
            viewsToShowForAttachmentsState[$0]?.forEach {
                if !viewsToShowForAttachmentsState[newAttachmentsState]!.contains($0) {
                    $0.isHidden = true
                }
            }
        }
    }

    
    /// This method should only be called from the `switchToState` method
    private func unhideViewsForState(newState: State) {
        guard let viewsToUnhide = viewsToShowForState[newState]?.filter({ $0.isHidden }) else { assertionFailure(); return }
        viewsToUnhide.forEach {
            $0.isHidden = false
            $0.alpha = 0.0 // Otherwise the previous line sets it back to 1.0 and messes with the animation
        }
    }

    
    private func unhideViewsForAttachmentsState(newAttachmentsState: AttachmentsState) {
        guard let viewsToUnhide = viewsToShowForAttachmentsState[newAttachmentsState]?.filter({ $0.isHidden }) else { assertionFailure(); return }
        viewsToUnhide.forEach {
            $0.isHidden = false
            $0.alpha = 0.0 // Otherwise the previous line sets it back to 1.0 and messes with the animation
        }
    }

    
    /// This method should only be called from the `switchToState` method. It returns `true` iff at least one constraint was activated/deactivated.
    private func adjustConstraintsForState(newState: State, newAttachmentsState: AttachmentsState) -> Bool {

        var constraintsToActivate = Set<NSLayoutConstraint>()
        var constraintsToDeactivate = Set<NSLayoutConstraint>()

        // Process the constraints to deactivate given the new State
        
        let constraintsForStateToDeactivate = State.allCases
            .filter({ $0 != newState })
            .compactMap({ constraintsForState[$0] })
            .flatMap({ $0 })
            .filter({ $0.isActive })

        constraintsToDeactivate.formUnion(constraintsForStateToDeactivate)
        
        // Process the constraints to activate given the new State

        let constraintsForStateToActivate = (constraintsForState[newState] ?? [])
            .filter({ !$0.isActive })
        
        constraintsToActivate.formUnion(constraintsForStateToActivate)
        
        // Process the constraints to deactivate given the new AttachmentsState

        let constraintsForAttachmentsStateToDeactivate = AttachmentsState.allCases
            .filter({ $0 != newAttachmentsState })
            .compactMap({ constraintsForAttachmentsState[$0] })
            .flatMap({ $0 })
            .filter({ $0.isActive })

        constraintsToDeactivate.formUnion(constraintsForAttachmentsStateToDeactivate)

        // Process the constraints to activate given the new AttachmentsState

        let constraintsForAttachmentsStateToActivate = (constraintsForAttachmentsState[newAttachmentsState] ?? [])
            .filter({ !$0.isActive })
        
        constraintsToActivate.formUnion(constraintsForAttachmentsStateToActivate)

        // Activate/Deactivate constraints
        
        NSLayoutConstraint.deactivate(Array(constraintsToDeactivate))
        NSLayoutConstraint.activate(Array(constraintsToActivate))

        return !constraintsToDeactivate.isEmpty || !constraintsToActivate.isEmpty

    }
    
    
    /// When the keyboard shows, we switch to the `.singleButton` button holder type using the animation found in the user info
    /// dictionary of the keyboard notification. Note that this notification is also received when the keyboard is dismissed. This can be
    /// filtered out by checking whether the duration of the animation is equal to 0 or not.
    @objc func keyboardWillShow(_ notification: Notification) {
        
        guard textFieldBubbleWasJustTapped else {
            return
        }
        textFieldBubbleWasJustTapped = false
        
        // Rermark: keyboardWillShow is also called when the keyboard is dismissed but with a zero duration
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as! Double
        guard duration > 0 else { return }
        
        let curveInt = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as! UInt
        let curve = UIView.AnimationOptions(rawValue: curveInt)
        let animationValues = (duration, curve)

        switchToState(newState: .typing, newAttachmentsState: evaluateNewAttachmentState(), animationValues: animationValues, completionForSendButton: nil)
        
    }
    
    
    /// When the keyboard shows, we switch to the `.multipleButtons` button holder type using the animation found in the user info
    /// dictionary of the keyboard notification.
    @objc func keyboardWillHide(_ notification: Notification) {
        
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as! Double
        
        let curveInt = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as! UInt
        let curve = UIView.AnimationOptions(rawValue: curveInt)
        let animationValues = (duration, curve)
                
        let newState: State
        if currentState == .recording {
            newState = .recording
        } else {
            newState = textViewForTyping.hasText ? .multipleButtonsWithText : .multipleButtonsWithoutText
        }
        switchToState(newState: newState, newAttachmentsState: evaluateNewAttachmentState(), animationValues: animationValues, completionForSendButton: nil)

        shortcutsView.configure(with: [], animated: true)
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()

        guard superview != nil else {
            return
        }

        if !hasDoneInitialSetupOfShortcutsView {
            _insertShortcutsViewIntoHierachy()

            hasDoneInitialSetupOfShortcutsView = true
        }
    }
}




// MARK: - UITextViewDelegate

@available(iOS 15.0, *)
extension NewComposeMessageView {

    func textViewDidBeginEditing(_ textView: UITextView) {
        switchToState(newState: .typing, newAttachmentsState: evaluateNewAttachmentState(), animationValues: buttonsAnimationValues, completionForSendButton: nil)
    }
    
    
    func textViewDidChange(_ textView: UITextView) {
        if textView.hasText {
            switchToState(newState: .typing, newAttachmentsState: evaluateNewAttachmentState(), animationValues: buttonsAnimationValues, completionForSendButton: nil)
        }
        let attributedText = textView.attributedText!
        let mentions = Self.extractMentionsFromAttributedText(attributedText)
        textSubject.send(DraftBodyWithId(body: attributedText.string, id: currentDraftId))
        mentionsSubject.send(mentions)
    }
    
    
    private static func extractMentionsFromAttributedText(_ attributedText: NSAttributedString) -> Set<MessageJSON.UserMention> {
        
        var userMentions = Set<MessageJSON.UserMention>()
        
        let attributedTextString = attributedText.string

        let range = NSRange(location: 0, length: attributedText.length)
                
        attributedText.enumerateAttribute(.mentionableIdentity, in: range) { value, effectiveRange, _ in
            guard let value else {
                return
            }

            guard effectiveRange.location != NSNotFound else {
                assert(false, "effective range is invalid")
                return
            }

            guard let value = value as? MentionableIdentity else {
                assert(false, "expected \(value) to be of kind MentionableIdentity")
                return
            }
            
            guard let mentionedCryptoId = value.mentionnedCryptoId else {
                assert(false, "unexpected nil mentionnedCryptoId within the MentionableIdentity")
                return
            }

            guard let convertedRange = Range<String.Index>(effectiveRange, in: attributedTextString) else {
                assert(false, "unable to convert range \(effectiveRange) into \(attributedTextString)")
                return
            }

            let userMention = MessageJSON.UserMention(mentionedCryptoId: mentionedCryptoId, range: convertedRange)
            
            userMentions.insert(userMention)
            
        }

        return userMentions
        
    }

    
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        guard currentState != .recording else { return false }
        return currentFreezeId == nil
    }
    
    func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
        return !preventTextViewFromEditing
    }
}


// MARK: - AutoGrowingTextViewDelegate

@available(iOS 15.0, *)
extension NewComposeMessageView: AutoGrowingTextViewDelegate {
    
    func userPastedItemProviders(in autoGrowingTextView: AutoGrowingTextView, itemProviders: [NSItemProvider]) {
        guard autoGrowingTextView == self.textViewForTyping else { assertionFailure(); return }
        addAttachments(from: itemProviders)
    }

    func autoGrowingTextView(_ textView: AutoGrowingTextView, perform action: AutoGrowingTextViewTypes.DelegateTypes.Action) {
        switch action {
        case .keyboardPerformReturn:
            // Make sure that we actually have text to submit, since we're creating a temp draft
            guard textView.hasText else {
                return
            }

            paperplaneButtonTapped()
        }
    }

    func autogrowingTextViewUserClearedShortcut(_ textView: AutoGrowingTextView) {
        shortcutsView.configure(with: [], animated: true)
    }

    func autogrowingTextView(_ textView: AutoGrowingTextView, userEnteredShortcut shortcut: AutoGrowingTextViewTypes.TextShortcut, result: String, within range: NSRange) {
        guard let datasource else {
            return
        }

        let shortcuts = datasource
            .newComposeMessageView(self,
                                   itemsForTextShortcut: .init(shortcut),
                                   text: result)
            .map { shortcut -> TextInputShortcutsResultView.TextShortcutItem in
                return .init(title: shortcut.title,
                             subtitle: shortcut.subtitle,
                             accessory: .init(shortcut.accessory),
                             value: shortcut.value,
                             range: range)
            }

        shortcutsView.configure(with: shortcuts, animated: true)
    }
}


// MARK: - Handling the display of the attachments

@available(iOS 15.0, *)
extension NewComposeMessageView {
    
    private func observeDraftBodyChanges() {
        // This makes sure the shown send button is appropriate
        kvo.append(draft.observe(\.body) { [weak self] _, _ in
            assert(Thread.isMainThread)
            self?.switchToAppropriateSendButton(animate: true, completion: nil)
        })
    }
                
    private func observeAttachmentsChanges() {
        cancellables.append(attachmentsCollectionViewController.$numberOfAttachments.sink { [weak self] numberOfAttachments in
            guard let _self = self else { return }
            // If the view is currently frozen (which happens when we are sending a message), we do not take the updated number of attachments into account.
            // Indeed, if the number changes while the view is frozen, it is certainly because the discussion coordinator is processing an attachment for the draft just before sending it.
            // Thus there is no need to switch to a new state, the draft will soon be reset anyway.
            guard _self.currentFreezeId == nil else { return }
            let newAttachmentsState = _self.evaluateNewAttachmentState()
            guard _self.currentAttachmentsState != newAttachmentsState else { return }
            _self.switchToState(newState: _self.currentState, newAttachmentsState: newAttachmentsState, animationValues: _self.buttonsAnimationValues, completionForSendButton: nil)
        })
    }

    private func observeDiscussionLocalConfigurationHasBeenUpdatedNotifications() {
        let token = ObvMessengerCoreDataNotification.observeDiscussionLocalConfigurationHasBeenUpdated { [weak self] value, objectId in
            DispatchQueue.main.async {
                guard case .defaultEmoji = value else { return }
                self?.configureEmojiButton()
            }
        }
        self.notificationTokens.append(token)
    }
    
    private func observeDefaultEmojiInAppSettings() {
        ObvMessengerSettingsObservableObject.shared.$defaultEmojiButton
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                assert(Thread.isMainThread)
                self?.configureEmojiButton()
            }
            .store(in: &cancellables)
    }



    private func evaluateNewAttachmentState() -> AttachmentsState {
        assert(Thread.isMainThread)
        self.numberOfAttachments = draft.fyleJoins.count
        return self.numberOfAttachments == 0 ? .noAttachment : .hasAttachments
    }

}



// MARK: - Managing the reply to view

@available(iOS 15.0, *)
extension NewComposeMessageView {
    
    private func observeMessageChanges() {
        cancellables.append(draft.publisher(for: \.replyTo).sink { [weak self] _ in
            guard let _self = self else { return }
            if let replyToMessage = _self.draft.replyTo {
                self?.replyToView.configureWithMessage(replyToMessage)
                self?.showReplyToView()
            } else {
                self?.hideReplyToView()
            }
        })
    }

    private func showReplyToView() {
        NSLayoutConstraint.deactivate(constraintsWhenHidingReplyTo)
        NSLayoutConstraint.activate(constraintsWhenShowingReplyTo)
        replyToView.isHidden = false
        if !textViewForTyping.isFirstResponder {
            textViewForTyping.becomeFirstResponder()
        }
    }

    private func hideReplyToView() {
        NSLayoutConstraint.deactivate(constraintsWhenShowingReplyTo)
        NSLayoutConstraint.activate(constraintsWhenHidingReplyTo)
        replyToView.isHidden = true
    }

}


@available(iOS 15.0, *)
extension NewComposeMessageView: PHPickerViewControllerDelegate {
    
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard !results.isEmpty else { return }
        do { try CompositionViewFreezeManager.shared.freeze(self) } catch { assertionFailure() }
        let draftPermanentID = draft.objectPermanentID
        delegateViewController?.showHUD(type: .spinner)
        let itemProviders = results.map { $0.itemProvider }
        NewSingleDiscussionNotification.userWantsToAddAttachmentsToDraft(draftPermanentID: draftPermanentID, itemProviders: itemProviders) { success in
            do { try CompositionViewFreezeManager.shared.unfreeze(draftPermanentID, success: success) } catch { assertionFailure() }
        }
        .postOnDispatchQueue()
    }
    
}



// MARK: - UIDocumentPickerDelegate

@available(iOS 15.0, *)
extension NewComposeMessageView: UIDocumentPickerDelegate {
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        addAttachments(from: urls)
    }
    
}

// MARK: - Append attachments
@available(iOS 15.0, *)
extension NewComposeMessageView {
    /// Appends an array of [file] `URL`s to the current draft
    /// - Parameters:
    ///   - fileURLs: An array of attachments to append
    func addAttachments(from fileURLs: [URL]) {
        do { try CompositionViewFreezeManager.shared.freeze(self) } catch { assertionFailure() }
        delegateViewController?.showHUD(type: .spinner)
        let draftPermanentID = draft.objectPermanentID
        NewSingleDiscussionNotification.userWantsToAddAttachmentsToDraftFromURLs(draftPermanentID: draftPermanentID, urls: fileURLs) { success in
            do { try CompositionViewFreezeManager.shared.unfreeze(draftPermanentID, success: success) } catch { assertionFailure() }
        }
        .postOnDispatchQueue()
    }

    /// Appends an array of `NSItemProvider`s to the current draft, either as text pasted in the text view, or as attachments.
    /// - Parameters:
    ///   - itemProviders: An array of item providers to append
    func addAttachments(from itemProviders: [NSItemProvider]) {

        let draftPermanentID = draft.objectPermanentID

        // Split the received itemProviders in two lists:
        // - One for the items we want to paste as text in the text view
        // - One for the items we want to add as attachments
        
        let itemProvidersToPaste = itemProviders.filter({ $0.registeredTypeIdentifiers.contains(where: { $0.utiConformsTo(kUTTypeText) } ) })
        let itemProvidersToAttach = itemProviders.filter({ !itemProvidersToPaste.contains($0) })

        // Process the item providers that we want to paste as text (i.e. Strings and URLs)
        
        itemProvidersToPaste.forEach { itemProviderToPaste in
            let textViewForTyping = self.textViewForTyping
            itemProviderToPaste.loadItem(forTypeIdentifier: String(kUTTypeText)) { item, error in
                if let error {
                    assertionFailure(error.localizedDescription)
                    return
                }
                if let text = item as? String {
                    DispatchQueue.main.async {
                        if let selectedTextRange = textViewForTyping.selectedTextRange {
                            textViewForTyping.replace(selectedTextRange, withText: text)
                        } else {
                            textViewForTyping.text.append(contentsOf: text)
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        textViewForTyping.paste(itemProviders: [itemProviderToPaste])
                    }
                }
            }
        }
        
        // Process the item providers we want to add as attachments
  
        guard !itemProvidersToAttach.isEmpty else { return }
        
        delegateViewController?.showHUD(type: .spinner)
        do { try CompositionViewFreezeManager.shared.freeze(self) } catch { assertionFailure() }
        NewSingleDiscussionNotification.userWantsToAddAttachmentsToDraft(draftPermanentID: draftPermanentID, itemProviders: itemProvidersToAttach) { success in
            do { try CompositionViewFreezeManager.shared.unfreeze(draftPermanentID, success: success) } catch { assertionFailure() }
        }
        .postOnDispatchQueue(self.internalQueue)
        
    }
}

// MARK: - AirDrop files


@available(iOS 15.0, *)
extension NewComposeMessageView {

    func addAttachmentFromAirDropFile(at fileURL: URL) {
        addAttachments(from: [fileURL])
    }
    
}



// MARK: - UIImagePickerControllerDelegate (For the Camera, not used for photos coming from the library)

@available(iOS 15.0, *)
extension NewComposeMessageView: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        
        picker.dismiss(animated: true)
        delegateViewController?.showHUD(type: .progress(progress: nil))
        do { try CompositionViewFreezeManager.shared.freeze(self) } catch { assertionFailure() }
        let draftPermanentID = draft.objectPermanentID

        let dateFormatter = self.dateFormatter
        let log = self.log
        

        DispatchQueue(label: "Queue for processing the UIImagePickerController result").async {
            
            // Fow now, we only authorize images and videos
            
            guard let chosenMediaType = info[.mediaType] as? String else {
                do { try CompositionViewFreezeManager.shared.unfreeze(draftPermanentID, success: false) } catch { assertionFailure() }
                return
            }
            guard ([kUTTypeImage, kUTTypeMovie] as [String]).contains(chosenMediaType) else {
                do { try CompositionViewFreezeManager.shared.unfreeze(draftPermanentID, success: false) } catch { assertionFailure() }
                return
            }
            
            let pickerURL: URL?
            if let imageURL = info[.imageURL] as? URL {
                pickerURL = imageURL
            } else if let mediaURL = info[.mediaURL] as? URL {
                pickerURL = mediaURL
            } else {
                // This should only happen when shooting a photo
                pickerURL = nil
            }
            
            if let url = pickerURL {
                // Copy the file to a temporary location. This does not seems to be required the pickerURL comes from an info[.imageURL], but this seems to be required when it comes from a info[.mediaURL]. Nevertheless, we do it for both, since the filename provided by the picker is terrible in both cases.
                let fileExtension = url.pathExtension.lowercased()
                let filename = ["Media @ \(dateFormatter.string(from: Date()))", fileExtension].joined(separator: ".")
                let localURL = ObvUICoreDataConstants.ContainerURL.forTempFiles.appendingPathComponent(filename)
                do {
                    try FileManager.default.copyItem(at: url, to: localURL)
                } catch {
                    os_log("Could not copy file provided by the Photo picker to a local URL: %{public}@", log: log, type: .fault, error.localizedDescription)
                    assertionFailure()
                    do { try CompositionViewFreezeManager.shared.unfreeze(draftPermanentID, success: false) } catch { assertionFailure() }
                    return
                }
                assert(!localURL.path.contains("PluginKitPlugin")) // This is a particular case, but we know the loading won't work in that case
                NewSingleDiscussionNotification.userWantsToAddAttachmentsToDraftFromURLs(draftPermanentID: draftPermanentID, urls: [localURL]) { success in
                    do { try CompositionViewFreezeManager.shared.unfreeze(draftPermanentID, success: success) } catch { assertionFailure() }
                }
                .postOnDispatchQueue()
            } else if let originalImage = info[.originalImage] as? UIImage {
                let uti = String(kUTTypeJPEG)
                guard let fileExtention = ObvUTIUtils.preferredTagWithClass(inUTI: uti, inTagClass: .FilenameExtension) else {
                    do { try CompositionViewFreezeManager.shared.unfreeze(draftPermanentID, success: false) } catch { assertionFailure() }
                    return
                }
                let name = "Photo @ \(dateFormatter.string(from: Date()))"
                let tempFileName = [name, fileExtention].joined(separator: ".")
                let url = ObvUICoreDataConstants.ContainerURL.forTempFiles.appendingPathComponent(tempFileName)
                guard let pickedImageJpegData = originalImage.jpegData(compressionQuality: 1.0) else {
                    do { try CompositionViewFreezeManager.shared.unfreeze(draftPermanentID, success: false) } catch { assertionFailure() }
                    return
                }
                do {
                    try pickedImageJpegData.write(to: url)
                } catch let error {
                    os_log("Could not save file to temp location: %@", log: log, type: .error, error.localizedDescription)
                    do { try CompositionViewFreezeManager.shared.unfreeze(draftPermanentID, success: false) } catch { assertionFailure() }
                    return
                }
                NewSingleDiscussionNotification.userWantsToAddAttachmentsToDraftFromURLs(draftPermanentID: draftPermanentID, urls: [url]) { success in
                    do { try CompositionViewFreezeManager.shared.unfreeze(draftPermanentID, success: success) } catch { assertionFailure() }
                }
                .postOnDispatchQueue()
            } else {
                do { try CompositionViewFreezeManager.shared.unfreeze(draftPermanentID, success: false) } catch { assertionFailure() }
                assertionFailure()
            }
            
        }
        
    }
    
}



// MARK: - VNDocumentCameraViewControllerDelegate

@available(iOS 15.0, *)
extension NewComposeMessageView: VNDocumentCameraViewControllerDelegate {
    
    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {

        controller.dismiss(animated: true)

        guard scan.pageCount > 0 else { return }
        
        self.delegateViewController?.showHUD(type: .spinner)

        let dateFormatter = self.dateFormatter
        
        let draftPermanentID = draft.objectPermanentID
        
        delegateViewController?.showHUD(type: .spinner)
        do { try CompositionViewFreezeManager.shared.freeze(self) } catch { assertionFailure() }

        DispatchQueue(label: "Queue for creating a pdf from scanned document").async {
            
            let pdfDocument = PDFDocument()
            for pageNumber in 0..<scan.pageCount {
                let image = scan.imageOfPage(at: pageNumber)
                guard let pdfPage = PDFPage(image: image) else {
                    do { try CompositionViewFreezeManager.shared.unfreeze(draftPermanentID, success: false) } catch { assertionFailure() }
                    return
                }
                pdfDocument.insert(pdfPage, at: pageNumber)
            }
            
            // Write the pdf to a temporary location
            let name = "Scan @ \(dateFormatter.string(from: Date()))"
            let tempFileName = [name, String(kUTTypePDF)].joined(separator: ".")
            let url = ObvUICoreDataConstants.ContainerURL.forTempFiles.appendingPathComponent(tempFileName)
            guard pdfDocument.write(to: url) else {
                do { try CompositionViewFreezeManager.shared.unfreeze(draftPermanentID, success: false) } catch { assertionFailure() }
                return
            }

            NewSingleDiscussionNotification.userWantsToAddAttachmentsToDraftFromURLs(draftPermanentID: draftPermanentID, urls: [url]) { success in
                do { try CompositionViewFreezeManager.shared.unfreeze(draftPermanentID, success: success) } catch { assertionFailure() }
            }
            .postOnDispatchQueue()

        }
        
    }

    
    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        controller.dismiss(animated: true)
    }

    
    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
        controller.dismiss(animated: true)
    }
}


// MARK: - ViewShowingHardLinks

@available(iOS 15.0, *)
extension NewComposeMessageView {
    
    func getAllShownHardLink() -> [(hardlink: HardLinkToFyle, viewShowingHardLink: UIView)] {
        attachmentsCollectionViewController.getAllShownHardLink()
    }

}


@available(iOS 15.0, *)
extension NewComposeMessageView: TextInputShortcutsResultViewDelegate {
    func textInputShortcutsResultView(_ view: TextInputShortcutsResultView, didSelect item: TextInputShortcutsResultView.TextShortcutItem) {
        textViewForTyping.apply(item)

        view.configure(with: [], animated: true)
    }
}

extension NewComposeMessageViewTypes.TextShortcut {
    init(_ value: AutoGrowingTextViewTypes.TextShortcut) {
        switch value {
        case .mention:
            self = .mention
        }
    }
}

@available(iOSApplicationExtension 14, *)
extension TextInputShortcutsResultView.TextShortcutItem.Accessory {
    init(_ accessory: NewComposeMessageViewTypes.TextShortcutItem.Accessory) {
        switch accessory {
        case .circledInitialsView(configuration: let configuration):
            self = .circledInitialsView(configuration: configuration)
        }
    }
}

@available(iOSApplicationExtension 14, *)
extension Optional where Wrapped == TextInputShortcutsResultView.TextShortcutItem.Accessory {
    init(_ accessory: NewComposeMessageViewTypes.TextShortcutItem.Accessory?) {
        if let accessory {
            self = .some(.init(accessory))
        } else {
            self = .none
        }
    }
}


fileprivate extension String {
    func utiConformsTo(_ otherUTI: CFString) -> Bool {
        UTTypeConformsTo(self as CFString, otherUTI)
    }
}
