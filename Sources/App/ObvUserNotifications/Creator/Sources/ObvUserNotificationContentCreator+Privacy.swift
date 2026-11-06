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

import Foundation
import UserNotifications
import ObvSettings
import ObvUserNotificationsContent
import ObvUserNotificationsTypes
@preconcurrency import ObvUICoreDataStructs


// MARK: - Hiding the content of notifications

/// The user may hide the content of notifications (``ObvMessengerSettings/Privacy/hideNotificationContent``). No builder reads that
/// setting: it asks this file, in one of two ways.
///
/// - ``concealedContent(about:startingFrom:soundOf:)``, before writing anything revealing. The builder returns what it gets when it gets something.
/// - ``mayRevealContent``, for a builder that has nothing to show unless it can reveal it, and so returns a silent notification instead.
///
/// Every notification then passes through ``ensuringPrivacy(of:)`` just before it is shown, which replaces anything showing more than the setting
/// allows. This is what catches a builder that forgot to ask.
///
/// Neither can see the sender and avatar that `ObvCommunicationInteractor.update` attaches to a content, which is why that method refuses to run
/// unless the user hides nothing.
extension ObvUserNotificationContentCreator {

    /// What a notification may say about itself when its content is hidden.
    enum ConcealableSubject: CaseIterable {
        case message
        case reaction
        case invitation
        /// An introduction by a mediator, as the notification extension receives it. The app replaces it once the invitation exists.
        case introduction
        case missedCall
        /// The explanation is about the device's settings, not about the call, so it survives a partially hidden content. It is `nil` when
        /// the permission was granted since the call was rejected.
        case callRejectedForLackOfMicrophonePermission(MicrophonePermissionExplanation?)

        /// Every value, each with its own wording. One left out here makes ``ensuringPrivacy(of:)`` replace that notification by the minimal one.
        static var allCases: [ConcealableSubject] {
            [.message, .reaction, .invitation, .introduction, .missedCall, .callRejectedForLackOfMicrophonePermission(nil)]
            + MicrophonePermissionExplanation.allCases.map { .callRejectedForLackOfMicrophonePermission($0) }
        }

        /// Shown when the content is partially hidden: the nature of the notification, never who or what.
        fileprivate var partiallyHidden: VisibleText {
            switch self {
            case .message:
                return .init(title: String(localized: "New message"), body: String(localized: "Tap to see the message"))
            case .reaction:
                return .init(title: String(localized: "New reaction"), body: String(localized: "Tap to see the reaction"))
            case .invitation, .introduction:
                return .init(title: String(localized: "New invitation"), body: String(localized: "Tap to see the invitation"))
            case .missedCall:
                return .init(title: String(localized: "Missed call"), body: String(localized: "Tap to see the call"))
            case .callRejectedForLackOfMicrophonePermission(let explanation):
                return .init(title: String(localized: "Missed call"), body: explanation?.body ?? String(localized: "Tap to see the call"))
            }
        }

        /// A category whose actions say nothing the hidden notification does not, and which a tap still takes to where the content is.
        fileprivate var categoryWhenHidden: ObvUserNotificationCategoryIdentifier {
            switch self {
            case .message: return .newMessageWithHiddenContent
            case .reaction: return .newReactionWithHiddenContent
            case .invitation: return .invitationWithNoAction
            case .introduction: return .protocolMessage
            case .missedCall: return .missedCallWithHiddenContent
            case .callRejectedForLackOfMicrophonePermission: return .rejectedIncomingCallBecauseOfDeniedRecordPermission
            }
        }
    }


    /// Why an incoming call was rejected, told to the user so that they can fix it.
    enum MicrophonePermissionExplanation: CaseIterable {
        case denied
        case undetermined

        var body: String {
            switch self {
            case .denied:
                return String(localized: "REJECTED_INCOMING_CALL_BECAUSE_RECORD_PERMISSION_IS_DENIED_NOTIFICATION_BODY")
            case .undetermined:
                return String(localized: "REJECTED_INCOMING_CALL_BECAUSE_RECORD_PERMISSION_IS_UNDETERMINED_NOTIFICATION_BODY")
            }
        }
    }


    struct ConcealedContent {
        let content: UNNotificationContent
        let category: ObvUserNotificationCategoryIdentifier
    }


    /// Returns what to show when the user hides the content of notifications, or `nil` when it may be revealed.
    ///
    /// `content` keeps what the user cannot see (identifiers, badge), so that a hidden notification is replaced and removed like any other. It plays
    /// the sound chosen for `discussionKind`, which the user may remove, with a note picked from the text shown rather than from the one hidden.
    static func concealedContent(about subject: ConcealableSubject, startingFrom content: UNMutableNotificationContent, soundOf discussionKind: PersistedDiscussionAbstractStructure.StructureKind?) -> ConcealedContent? {

        let visibleText: VisibleText
        switch ObvMessengerSettings.Privacy.hideNotificationContent {
        case .no:
            return nil
        case .completely:
            visibleText = .minimal
        case .partially:
            visibleText = subject.partiallyHidden
        }

        content.title = visibleText.title
        content.subtitle = visibleText.subtitle
        content.body = visibleText.body
        content.attachments = []
        content.threadIdentifier = ObvUserNotificationThread.minimal.threadIdentifier
        content.setObvCategoryIdentifier(to: subject.categoryWhenHidden)
        applySound(of: discussionKind, to: content)

        return ConcealedContent(content: content, category: subject.categoryWhenHidden)

    }


    /// `false` when the user hides the content of notifications, for a builder that has nothing to show unless it can reveal it.
    static var mayRevealContent: Bool {
        ObvMessengerSettings.Privacy.hideNotificationContent == .no
    }


    /// Called on every notification just before it is shown. Returns `content` unchanged, unless it shows more than the user allows,
    /// in which case the minimal content is returned instead.
    ///
    /// The replacement is built afresh rather than copied: a copy would keep the sender and avatar of a communication notification. It keeps the
    /// hidden counterpart of the category, so that a tap still takes the user to the content.
    public static func ensuringPrivacy(of content: UNNotificationContent) -> UNNotificationContent {

        let hideNotificationContent = ObvMessengerSettings.Privacy.hideNotificationContent

        if showsOnlyWhatIsAllowed(content, when: hideNotificationContent) {
            
            return content

        } else {

            let category = content.categoryIdentifier
            logger.fault("A notification of category \(category, privacy: .public) shows more than the user allows: we show the minimal notification instead")
            // Also reached, legitimately, when the user changes the setting while a notification is being built. That race is rare, and
            // accepted rather than read the setting once for every builder.
            assertionFailure("The builder of this notification must return the content of concealedContent(about:startingFrom:soundOf:) when it is not nil")

            // In that race, the row the notification extension saved for a message keeps its category, so Siri may still read that one
            // message out. Accepted for the same reason.
            let replacement = createMinimalNotificationContent(badge: .unchanged).mutableContent
            replacement.badge = content.badge
            replacement.userInfo = content.userInfo
            if let hiddenCategory = content.obvCategoryIdentifier?.whenContentIsHidden {
                replacement.setObvCategoryIdentifier(to: hiddenCategory)
            }
            return replacement
            
        }
        
    }


    /// Compares what the user can see, rather than trusting a marker: a hidden content that is edited later would still carry the marker.
    static func showsOnlyWhatIsAllowed(_ content: UNNotificationContent, when hideNotificationContent: ObvMessengerSettings.Privacy.HideNotificationContentType) -> Bool {

        switch hideNotificationContent {
        case .no:
            return true
        case .completely:
            let shown = VisibleText(content)
            return content.attachments.isEmpty && shown.isAllowedWhateverTheSetting
        case .partially:
            let shown = VisibleText(content)
            return content.attachments.isEmpty && (shown.isAllowedWhateverTheSetting || ConcealableSubject.allCases.contains(where: { $0.partiallyHidden == shown }))
        }

    }

}


// MARK: - What the user sees

extension ObvUserNotificationContentCreator {

    fileprivate struct VisibleText: Equatable {

        let title: String
        let subtitle: String
        let body: String

        init(title: String, subtitle: String = "", body: String) {
            self.title = title
            self.subtitle = subtitle
            self.body = body
        }

        init(_ content: UNNotificationContent) {
            self.init(title: content.title, subtitle: content.subtitle, body: content.body)
        }

        /// What a content posted only to remove other notifications shows.
        static let nothing = VisibleText(title: "", body: "")

        static var minimal: VisibleText {
            VisibleText(ObvUserNotificationContentCreator.createMinimalNotificationContent(badge: .unchanged).content)
        }

        var isAllowedWhateverTheSetting: Bool {
            self == .nothing || self == .minimal || Self.revealingNothing.contains(self)
        }

        /// Notifications that tell nothing about a message, a contact or an invitation, and are therefore shown whatever the setting.
        /// A notification that reveals nothing and is missing here is replaced by the minimal one whenever content is hidden.
        static var revealingNothing: [VisibleText] {
            var texts = [VisibleText(ObvUserNotificationContentCreator.historyTransferRequestContent())]
            if let content = try? ObvUserNotificationContentCreator.createNotificationContentWhenAnotherCallParticipantStartedCamera() {
                texts.append(VisibleText(content))
            }
            return texts
        }

    }

}


// MARK: - Other private extensions

fileprivate extension ObvUserNotificationCategoryIdentifier {

    /// The category a notification of this category takes when its content is hidden: no action reveals anything, and a tap goes to the same place.
    var whenContentIsHidden: ObvUserNotificationCategoryIdentifier {
        switch self {
        case .newMessage, .newMessageWithLimitedVisibility, .newMessageWithHiddenContent:
            return .newMessageWithHiddenContent
        case .newReaction, .newReactionWithHiddenContent, .pollVote:
            return .newReactionWithHiddenContent
        case .missedCall, .missedCallWithHiddenContent:
            return .missedCallWithHiddenContent
        case .acceptInvite, .invitationWithNoAction:
            return .invitationWithNoAction
        case .minimal, .protocolMessage, .rejectedIncomingCallBecauseOfDeniedRecordPermission, .postUserNotificationAsAnotherCallParticipantStartedCamera:
            return self
        }
    }

}

fileprivate extension String {

    init(localized keyAndValue: String.LocalizationValue) {
        self.init(localized: keyAndValue, bundle: ObvUserNotificationsCreatorResources.bundle)
    }

}
