/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import AVFAudio
import OSLog
@preconcurrency import ObvUICoreData
import ObvSettings
import ObvCommunicationInteractor
import ObvTypes
@preconcurrency import ObvUICoreDataStructs
import ObvCoreDataStack
import ObvAppDatabase
import ObvAppCoreConstants
import ObvUserNotificationsTypes
@preconcurrency import ObvAppTypes
import OlvidUtils


public struct ObvUserNotificationContentCreator {
        
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: ObvUserNotificationContentCreator.self))
    
    
    /// Called from the main app only, when a new protocol dialog is inserted or updated.
    ///
    /// To the contrary of ``static determineNotificationToShow(obvMessage:obvStackShared:)``, we don't need to query the app database to construct the notification content.
    /// Since this notification is scheduled by the app (and never by the notification extension), we already have all the information we need in the `PersistedInvitationStructure`.
    ///
    /// The `ObvUserNotificationContentTypeForInvitation` full case also contains an optional `ObvProtocolMessage`.
    /// This is typically used for the notification of a mediator invite: the notification extension publishes a notification by decrypting
    /// a protocol message, obtaining an `ObvProtocolMessage` used to determine the notification content. When the app is launched, the protocol is executed, the app is notified, creates a
    /// `PersistedInvitation`, which eventually triggers a call to this method that returns a notification content for the same mediator invite (but that has the advantage of providing accept and reject actions).
    /// To avoid having two notifications for the same mediator invite, this method returns the `ObvProtocolMessage` that should correspond to the notification published by the notification extension, making
    /// it possible for the caller (in practice, the `UserNotificationsCoordinator`) to search a remove the notification posted by the notification extension.
    public static func determineNotificationToShow(invitation: PersistedInvitationStructure) async -> ObvUserNotificationContentTypeForInvitation {
        
        // Certain notifications should always return a silent notification
        
        guard !invitation.obvDialog.category.shouldShowSilentNotification else {
            return .silent
        }
        
        guard !invitation.ownedIdentity.isHidden else {
            return .silent
        }
        
        // Start with a minimal notification
        
        let content = Self.createMinimalNotificationContent(badge: .unchanged).mutableContent

        // We enrich the content with the obvDialog. This is used when the user interacts with the notification,
        // like when she accepts or rejects an invitation from the actions made available in the user notification.
        
        do {
            try content.setObvDialog(to: invitation.obvDialog)
        } catch {
            Self.logger.fault("Failed to set ObvDialog on a local user notification: \(error.localizedDescription)")
            assertionFailure()
        }

        // The notification content depends on the 'hideNotificationContent' user setting

        switch ObvMessengerSettings.Privacy.hideNotificationContent {
            
        case .completely:
               
            // We keep the minimal notifications
            return .full(content: content, toRemove: nil)

        case .partially:
            
            // Simply describe the nature of the notification
            content.title = String(localized: "New invitation")
            content.body = String(localized: "Tap to see the invitation")
            return .full(content: content, toRemove: nil)

        case .no:
            
            switch invitation.obvDialog.category {
                
            case .acceptInvite(contactIdentity: let contactIdentity):
                let contactDisplayName = contactIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full)
                content.title = String(localized: "New Invitation!")
                content.body = String(localized: "You receive a new invitation from \(contactDisplayName). You can accept or silently discard it.")
                content.setObvCategoryIdentifier(to: .acceptInvite)
                return .full(content: content, toRemove: nil)

            case .sasExchange(contactIdentity: let contactIdentity, sasToDisplay: _, numberOfBadEnteredSas: let numberOfBadEnteredSas):
                guard numberOfBadEnteredSas == 0 else { return .silent } // Do not show any notification when the user enters a bad SAS
                let contactDisplayName = contactIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full)
                content.title = String(localized: "ONE_MORE_STEP")
                content.body = String(localized: "EXCHANGE_YOUR_CODES_WITH_\(contactDisplayName)")
                content.setObvCategoryIdentifier(to: .invitationWithNoAction)
                return .full(content: content, toRemove: nil)

            case .mutualTrustConfirmed(contactIdentity: let contactIdentity):
                let contactDisplayName = contactIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full)
                content.title = String(localized: "Mutual trust confirmed!")
                content.body = String(localized: "You now appear in \(contactDisplayName)'s contacts list. A secure channel is being established. When this is done, you will be able to exchange confidential messages and more!")
                content.setObvCategoryIdentifier(to: .invitationWithNoAction)
                return .full(content: content, toRemove: nil)

            case .acceptMediatorInvite(contactIdentity: let contactIdentity, mediatorIdentity: _):
                
                // We create a notification that must look identical to the one created in
                // `static createNotificationContentForReceivedProtocolMessage(obvProtocolMessage:contact:oneToOneDiscussion:)`
                // when receiving a mutualIntroduction protocol message (that can only be posted by the notification extension,
                // while the invitation we are posting can only be posted by the app).
                
                guard let mediator = invitation.inviterOrMediator else {
                    assertionFailure("The mediator should have been set when creating the structure")
                    return .silent
                }
                
                content.title = mediator.customOrFullDisplayName
                content.body = String(localized: "I would like to introduce you to \(contactIdentity.getDisplayNameWithStyle(.firstNameThenLastName))")
                
                content.setObvCategoryIdentifier(to: .acceptInvite)
                
                // We want to remove any "identical" ObvProtocolMessage notification posted by the notification extension
                
                let toRemove: ObvProtocolMessage = .mutualIntroduction(mediator: mediator.contactIdentifier,
                                                                       introducedIdentity: contactIdentity.cryptoId,
                                                                       introducedIdentityCoreDetails: contactIdentity.currentIdentityDetails.coreDetails)

                if let discussion = invitation.oneToOneDiscussionWithInviterOrMediator {
                    content.threadIdentifier = ObvUserNotificationThread.discussion(discussion.identifier).threadIdentifier
                    let discussionKind = PersistedDiscussionAbstractStructure.StructureKind.oneToOneDiscussion(structure: discussion)
                    let communicationType = ObvCommunicationType.incomingMessage(contact: mediator, discussionKind: discussionKind, messageRepliedTo: nil, mentions: [])
                    do {
                        let updatedContent = try await ObvCommunicationInteractor.update(notificationContent: content, communicationType: communicationType)
                        return .full(content: updatedContent, toRemove: toRemove)
                    } catch {
                        return .full(content: content, toRemove: toRemove)
                    }
                } else {
                    return .full(content: content, toRemove: toRemove)
                }
                
            case .acceptGroupInvite(groupMembers: _, groupOwner: let contactIdentity):
                let contactDisplayName = contactIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full)
                content.title = String(localized: "Invitation to join a group")
                content.body = String(localized: "You are invited to join a group created by \(contactDisplayName).")
                content.setObvCategoryIdentifier(to: .acceptInvite)
                return .full(content: content, toRemove: nil)

            case .oneToOneInvitationReceived(contactIdentity: let contactIdentity):
                let contactDisplayName = contactIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full)
                content.title = String(localized: "New Invitation!")
                content.body = String(localized: "\(contactDisplayName)_INVITES_YOU_TO_ONE_TO_ONE_DISCUSSION")
                content.setObvCategoryIdentifier(to: .acceptInvite)
                return .full(content: content, toRemove: nil)

            case .acceptGroupV2Invite(inviter: _, group: _):
                guard let inviter = invitation.inviterOrMediator else {
                    assertionFailure("The inviter should have been set when creating the structure")
                    return .silent
                }
                let inviterDisplayName = inviter.customOrNormalDisplayName
                content.title = String(localized: "Invitation to join a group")
                content.body = String(localized: "You are invited to join a group created by \(inviterDisplayName).")
                content.setObvCategoryIdentifier(to: .acceptInvite)
                return .full(content: content, toRemove: nil)

            case .inviteSent,
                    .invitationAccepted,
                    .sasConfirmed,
                    .mediatorInviteAccepted,
                    .oneToOneInvitationSent,
                    .syncRequestReceivedFromOtherOwnedDevice,
                    .freezeGroupV2Invite:
                assert(invitation.obvDialog.category.shouldShowSilentNotification)
                return .silent
                
            }
            
        }
                
    }

    
    
    public static func determineNotificationToShow(obvOwnedMessage: ObvOwnedMessage, obvStackShared: CoreDataStack<ObvMessengerPersistentContainer>) async throws -> ObvUserNotificationContentTypeForObvOwnedMessage {
        
        let infosForCreatingContent = try await determineInfosForCreatingContent(obvOwnedMessage: obvOwnedMessage, obvStackShared: obvStackShared)

        switch infosForCreatingContent {
        case .silent:

            return .silent

            
        case .removeAllNotificationsOfDiscussion(discussionIdentifier: let discussionIdentifier, lastReadMessageServerTimestamp: let lastReadMessageServerTimestamp):

            return .removePreviousNotificationsBasedOnObvDiscussionIdentifier(
                content: UNNotificationContent(),
                obvDiscussionIdentifier: discussionIdentifier,
                lastReadMessageServerTimestamp: lastReadMessageServerTimestamp)
            
        case .removeReceivedMessages(messageAppIdentifiers: let messageAppIdentifiers):
            
            return .removePreviousNotificationsBasedOnObvMessageAppIdentifiers(content: UNNotificationContent(), messageAppIdentifiers: messageAppIdentifiers)

        case .minimal, .message, .reaction, .messageEdition:
            
            Self.logger.fault("Unexpected infos for an ObvOwnedMessage")
            assertionFailure()
            return .silent
            
        }
        
    }
    
    
    /// Called from the notification extension only, when a new protocol message is received
    public static func determineNotificationToShow(obvProtocolMessage: ObvProtocolMessage, obvStackShared: CoreDataStack<ObvMessengerPersistentContainer>) async throws -> ObvUserNotificationContentTypeForObvProtocolMessage {
        
        let infosForCreatingContent = try await determineInfosForCreatingContent(obvProtocolMessage: obvProtocolMessage, obvStackShared: obvStackShared)
        
        switch infosForCreatingContent {

        case .silent:
            
            return .silent
            
        case .minimal:

            let content = ObvUserNotificationContentCreator.createMinimalNotificationContent(badge: .unchanged).content
            return .minimal(content: content)
            
        case .message(contact: let contact, oneToOneDiscussion: let oneToOneDiscussion):
            
            let content = await ObvUserNotificationContentCreator.createNotificationContentForReceivedProtocolMessage(obvProtocolMessage: obvProtocolMessage, contact: contact, oneToOneDiscussion: oneToOneDiscussion)
            
            return content
            
        }
        
    }
    

    /// Called both by the notification extension and by the main app when receivng an 'ObvMessage'. Depending on the JSON found in the payload, this method will return the notification
    /// that can be published by the caller (who will make sure that it's in charge of posting the notification).
    public static func determineNotificationToShow(obvMessage: ObvMessage, obvStackShared: CoreDataStack<ObvMessengerPersistentContainer>) async throws -> ObvUserNotificationContentTypeForObvMessage {
        
        // Parse the (decrypted) ObvMessage to make sure it corresponds to a message or to a reaction.
        
        let infosForCreatingContent = try await determineInfosForCreatingContent(obvMessage: obvMessage, obvStackShared: obvStackShared)
        
        switch infosForCreatingContent {
            
        case .silent:
            
            return .silent
            
        case .minimal:
            
            return ObvUserNotificationContentCreator.createMinimalNotificationContent(badge: .unchanged)
            
        case .message(messageJSON: let messageJSON, contact: let contact, discussionKind: let discussionKind, messageRepliedTo: let messageRepliedTo):
            
            let content = await ObvUserNotificationContentCreator.createNotificationContentForReceivedMessage(
                message: messageJSON,
                expectedAttachmentsCount: obvMessage.expectedAttachmentsCount,
                contact: contact,
                discussionKind: discussionKind,
                messageRepliedTo: messageRepliedTo,
                uploadTimestampFromServer: obvMessage.messageUploadTimestampFromServer)
            
            return content
            
        case .messageEdition(updateMessageJSON: let updateMessageJSON, contact: let contact, discussionKind: let discussionKind, messageRepliedTo: let messageRepliedTo):
            
            let content = try await ObvUserNotificationContentCreator.createNotificationContentForReceivedMessageEdition(
                updateMessageJSON: updateMessageJSON,
                expectedAttachmentsCount: obvMessage.expectedAttachmentsCount,
                contact: contact,
                discussionKind: discussionKind,
                messageRepliedTo: messageRepliedTo)
            
            return content

        case .reaction(reactionJSON: let reactionJSON, reactor: let reactor, sentMessageReactedTo: let sentMessageReactedTo, uploadTimestampFromServer: let uploadTimestampFromServer):
            
            let content = await ObvUserNotificationContentCreator.createNotificationContentForReceivedReaction(
                reactionJSON: reactionJSON,
                reactor: reactor,
                sentMessageReactedTo: sentMessageReactedTo,
                uploadTimestampFromServer: uploadTimestampFromServer)
            
            return content
            
        case .removeReceivedMessages(messageAppIdentifiers: let messageAppIdentifiers):
            
            return .removeReceivedMessages(content: UNNotificationContent(), messageAppIdentifiers: messageAppIdentifiers)
            
        case .removeAllNotificationsOfDiscussion(discussionIdentifier: let discussionIdentifier, lastReadMessageServerTimestamp: let lastReadMessageServerTimestamp):
            
            assert(lastReadMessageServerTimestamp == nil)
            
            return .removePreviousNotificationsBasedOnObvDiscussionIdentifier(content: UNNotificationContent(), obvDiscussionIdentifier: discussionIdentifier)

        }
        
    }
    
    
    

    /// This static method is used as a best effort to deliver a notification. For example, it is used when, after an app upgrade, we receive a user notification before the app has been launched and thus, before database migration.
    /// In that situation, the engine initialisation fails within this extension (since this extension is not allowed to perform database migrations). Still, we want users to be notified. We create a minimal notification to do so.
    /// This method is also used at the very beginning of ``createNewMessageNotification``, to create a notification content that we then augment if possible.
    public static func createMinimalNotificationContent(badge: BadgeValue) -> ObvUserNotificationContentTypeForObvMessage {
        
        let content = UNMutableNotificationContent()
        
        //
        // Providing the primary content
        //
        
        content.title = "Olvid"
        content.subtitle = ""
        content.body = String(localized: "Olvid requires your attention")
        
        //
        // Providing supplementary content
        //
        
        content.attachments = []
        content.userInfo = [:]

        //
        // Configuring app behavior
        //

        content.badge = badge.badge
        
        //
        // Integrating with the system
        //
        
        content.sound = UNNotificationSound.default
        content.interruptionLevel = .active
        
        //
        // Grouping notifications
        //
        
        content.threadIdentifier = ObvUserNotificationThread.minimal.threadIdentifier
        content.setObvCategoryIdentifier(to: .minimal)

        return .minimal(content: content)

    }
    
    // Creating notification content for call events
    
    
    public static func createNotificationContentWhenAnotherCallParticipantStartedCamera() throws -> UNNotificationContent {
        
        // Start with a minimal notification

        let content = Self.createMinimalNotificationContent(badge: .unchanged).mutableContent

        content.title = String(localized: "A_PARTICIPANT_STARTED_THEIR_CAMERA")
        content.subtitle = ""
        content.body = String(localized: "TAP_HERE_TO_SEE_THE_PARTICIPANT_VIDEO")

        content.setObvCategoryIdentifier(to: .postUserNotificationAsAnotherCallParticipantStartedCamera)

        return content
        
    }
    
    
    /// Called by the app when receiving a call report indicating that a call was missed.
    public static func createNotificationContentForCallLog(callLog: PersistedCallLogItemStructure) async throws -> UNNotificationContent {
     
        enum ExpectedCallReportKind {
            case missedIncomingCall
            case filteredIncomingCall
            case rejectedIncomingCallBecauseOfDeniedRecordPermission
        }
        
        let callReportKind: ExpectedCallReportKind
        
        switch callLog.callReportKind {
        case .rejectedOutgoingCall, .acceptedOutgoingCall, .uncompletedOutgoingCall, .acceptedIncomingCall, .rejectedIncomingCall:
            // We shouldn't have been call for this report kind as it should only generate a suggested intent via the intent manager, and no local user notification
            assertionFailure()
            throw ObvError.unexpectedCallLogReportKind
        case .missedIncomingCall:
            callReportKind = .missedIncomingCall
        case .filteredIncomingCall:
            callReportKind = .filteredIncomingCall
        case .rejectedIncomingCallBecauseOfDeniedRecordPermission:
            callReportKind = .rejectedIncomingCallBecauseOfDeniedRecordPermission
        }
        
        // Start with a minimal notification

        let content = Self.createMinimalNotificationContent(badge: .unchanged).mutableContent

        //
        // Providing the primary content
        //
        
        guard let caller = callLog.otherParticipants.first(where: { $0.isCaller }) else {
            assertionFailure()
            throw ObvError.couldNotFindCaller
        }
        content.title = caller.contactIdentity.customOrNormalDisplayName

        switch callLog.discussionKind {
        case .oneToOneDiscussion:
            // Keep the subtitle as in the minimal notification content
            break
        case .groupDiscussion(structure: let structure):
            content.subtitle = structure.title
        case .groupV2Discussion(structure: let structure):
            content.subtitle = structure.title
        }

        switch callReportKind {
        case .missedIncomingCall:
            content.body = String(localized: "MISSED_CALLED_WITH_\(callLog.initialOtherParticipantsCount-1)_OTHER_PARTICIPANTS")
        case .filteredIncomingCall:
            content.body = String(localized: "MISSED_CALL_WHILE_IN_DO_NOT_DISTURB_MODE")
        case .rejectedIncomingCallBecauseOfDeniedRecordPermission:
            switch AVAudioSession.sharedInstance().recordPermission {
            case .undetermined:
                content.body = String(localized: "REJECTED_INCOMING_CALL_BECAUSE_RECORD_PERMISSION_IS_UNDETERMINED_NOTIFICATION_BODY")
            case .denied:
                content.body = String(localized: "REJECTED_INCOMING_CALL_BECAUSE_RECORD_PERMISSION_IS_DENIED_NOTIFICATION_BODY")
            case .granted:
                assertionFailure()
                break
            @unknown default:
                break
            }
        }
        

        // Providing supplementary content
        // For now, we don't deal with attachments and don't use the userInfo dictionary.

        //
        // Configuring app behavior
        //

        content.badge = NSNumber(integerLiteral: callLog.discussionKind.ownedIdentity.badgeCount+1)
        
        // Integrating with the system
        
        if let notificationSound = callLog.discussionKind.localConfiguration.notificationSound ?? ObvMessengerSettings.Discussions.notificationSound {
            switch notificationSound {
            case .none:
                content.sound = nil
            case .system:
                // Keep the sound as it is in the minimal notification content
                break
            default:
                if let sound = notificationSound.unNotificationSound(for: content.body) {
                    content.sound = sound
                } else {
                    // Keep the sound as it is in the minimal notification content
                }
            }
        } else {
            // Keep the sound as it is in the minimal notification content
        }

        // For now, we keep the interruptionLevel of the minimal notification

        //
        // Specify the appropriate category, allowing the notification to give access to the appropriate actions
        //
        
        switch callReportKind {
        case .missedIncomingCall, .filteredIncomingCall:
            let userNotificationCategory = ObvUserNotificationCategoryIdentifier.missedCall
            content.setObvCategoryIdentifier(to: userNotificationCategory)
        case .rejectedIncomingCallBecauseOfDeniedRecordPermission:
            let userNotificationCategory = ObvUserNotificationCategoryIdentifier.rejectedIncomingCallBecauseOfDeniedRecordPermission
            content.setObvCategoryIdentifier(to: userNotificationCategory)
        }

        //
        // No specific thread identifier
        //
        
        // Setting the ObvDiscussionIdentifier on the notification, to make it easier to remove the notification automatically
        
        content.setObvDiscussionIdentifier(to: callLog.discussionKind.discussionIdentifier)
        content.setObvContactIdentifier(to: caller.contactIdentity.contactIdentifier)
        
        // Enrich the notification with communication information and return the content

        do {
            let communicationType = ObvCommunicationType.callLog(callLog: callLog)
            let updatedContent = try await ObvCommunicationInteractor.update(notificationContent: content, communicationType: communicationType)
            return updatedContent
        } catch {
            assertionFailure()
            return content
        }

    }
    
}


// MARK: - Errors

extension ObvUserNotificationContentCreator {
    
    public enum ObvError: Error {
        case couldNotFindContact
        case couldNotFindOwnedIdentity
        case couldNotFindGroupV2Discussion
        case couldNotFindCaller
        case unexpectedCallLogReportKind
    }
    
}


// MARK: - Private helpers

extension ObvUserNotificationContentCreator {
    
    private static func createNotificationContentForReceivedReaction(reactionJSON: ReactionJSON, reactor: PersistedObvContactIdentityStructure, sentMessageReactedTo: PersistedMessageSentStructure, uploadTimestampFromServer: Date) async -> ObvUserNotificationContentTypeForObvMessage {
        
        let userNotificationContentType = await createNotificationContentForReceivedReaction(
            emoji: reactionJSON.emoji,
            reactor: reactor,
            sentMessageReactedTo: sentMessageReactedTo,
            uploadTimestampFromServer: uploadTimestampFromServer)
                
        return userNotificationContentType

    }
    
    
    private static func createNotificationContentForReceivedMessage(message: MessageJSON, expectedAttachmentsCount: Int, contact: PersistedObvContactIdentityStructure, discussionKind: PersistedDiscussionAbstractStructure.StructureKind, messageRepliedTo: RepliedToMessageStructure?, uploadTimestampFromServer: Date) async -> ObvUserNotificationContentTypeForObvMessage {
        
        let isEphemeralMessageWithUserAction: Bool
        if let expiration = message.expiration, expiration.visibilityDuration != nil || expiration.readOnce {
            isEphemeralMessageWithUserAction = true
        } else {
            isEphemeralMessageWithUserAction = false
        }
        
        let messageAppIdentifier = ObvMessageAppIdentifier.received(
            discussionIdentifier: discussionKind.discussionIdentifier,
            senderIdentifier: contact.cryptoId.getIdentity(),
            senderThreadIdentifier: message.senderThreadIdentifier,
            senderSequenceNumber: message.senderSequenceNumber)
        
        let locationInfo: LocationInfo? = {
            if let location = message.location {
                return LocationInfo(type: location.type,
                                    address: location.address)
            } else {
                return nil
            }
        }()
        
        let receivedMessage = ReceivedMessage(
            messageAppIdentifier: messageAppIdentifier,
            mentionedCryptoIds: message.userMentions.map(\.mentionedCryptoId),
            isEphemeralMessageWithUserAction: isEphemeralMessageWithUserAction,
            body: message.body,
            badgeCount: discussionKind.ownedIdentity.badgeCount,
            locationInfo: locationInfo)

        let userNotificationContentType = await Self.createNotificationContentForReceivedMessage(
            receivedMessage: receivedMessage,
            expectedAttachmentsCount: expectedAttachmentsCount,
            contact: contact,
            discussionKind: discussionKind,
            messageRepliedTo: messageRepliedTo,
            uploadTimestampFromServer: uploadTimestampFromServer)
        
        return userNotificationContentType
        
    }
    
    
    private static func createNotificationContentForReceivedMessageEdition(updateMessageJSON: UpdateMessageJSON, expectedAttachmentsCount: Int, contact: PersistedObvContactIdentityStructure, discussionKind: PersistedDiscussionAbstractStructure.StructureKind, messageRepliedTo: RepliedToMessageStructure?) async throws -> ObvUserNotificationContentTypeForObvMessage {

        let messageAppIdentifier = ObvMessageAppIdentifier.received(
            discussionIdentifier: discussionKind.discussionIdentifier,
            senderIdentifier: updateMessageJSON.messageToEdit.senderIdentifier,
            senderThreadIdentifier: updateMessageJSON.messageToEdit.senderThreadIdentifier,
            senderSequenceNumber: updateMessageJSON.messageToEdit.senderSequenceNumber)

        let locationInfo: LocationInfo? = {
            if let location = updateMessageJSON.locationJSON {
                return LocationInfo(type: location.type,
                                    address: location.address)
            } else {
                return nil
            }
        }()
        
        let receivedMessageEdition = ReceivedMessageEdition(
            messageAppIdentifier: messageAppIdentifier,
            newBody: updateMessageJSON.newTextBody,
            locationInfo: locationInfo)
                
        let userNotificationContentType = try await Self.createNotificationContentForReceivedMessageEdition(receivedMessageEdition: receivedMessageEdition)
        
        return userNotificationContentType

        
    }
    
    private static func createNotificationContentForReceivedMessage(message: PersistedMessageReceivedStructure, uploadTimestampFromServer: Date) async -> ObvUserNotificationContentTypeForObvMessage {
        
        let isEphemeralMessageWithUserAction: Bool = message.visibilityDuration != nil || message.readOnce
        
        let locationInfo: LocationInfo? = {
            if let location = message.location {
                return LocationInfo(type: LocationJSON.LocationSharingType(rawValue: location.type) ?? .SEND,
                                    address: location.address)
            } else {
                return nil
            }
        }()
        
        let receivedMessage = ReceivedMessage (
            messageAppIdentifier: message.messageAppIdentifier,
            mentionedCryptoIds: message.mentions.map(\.mentionedCryptoId),
            isEphemeralMessageWithUserAction: isEphemeralMessageWithUserAction,
            body: message.textBody,
            badgeCount: message.discussionKind.ownedIdentity.badgeCount,
            locationInfo: locationInfo)
        
        let expectedAttachmentsCount = message.attachmentsCount

        let userNotificationContentType = await Self.createNotificationContentForReceivedMessage(
            receivedMessage: receivedMessage,
            expectedAttachmentsCount: expectedAttachmentsCount,
            contact: message.contact,
            discussionKind: message.discussionKind,
            messageRepliedTo: message.repliedToMessage,
            uploadTimestampFromServer: uploadTimestampFromServer)
        
        return userNotificationContentType

    }
    
    
    /// Exclusively used when receiving an `ObvProtocolMessage` in the user notification extension.
    private static func determineInfosForCreatingContent(obvProtocolMessage: ObvProtocolMessage, obvStackShared: CoreDataStack<ObvMessengerPersistentContainer>) async throws -> InfosForCreatingProtocolContent {

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<InfosForCreatingProtocolContent, any Error>) in
            
            obvStackShared.performBackgroundTask { context in
                do {

                    switch obvProtocolMessage {
                        
                    case .mutualIntroduction(mediator: let mediator, introducedIdentity: _, introducedIdentityCoreDetails: _):
                        
                        guard let persistedMediator = try PersistedObvContactIdentity.get(persisted: mediator, whereOneToOneStatusIs: .oneToOne, within: context) else {
                            assertionFailure()
                            return continuation.resume(returning: .silent)
                        }
                        
                        let mediatorStruct = try persistedMediator.toStructure()
                        
                        guard let persistedOneToOneDiscussion = persistedMediator.oneToOneDiscussion else {
                            assertionFailure()
                            return continuation.resume(returning: .silent)
                        }
                        
                        let oneToOneDiscussion = try persistedOneToOneDiscussion.toStructure()
                        
                        return continuation.resume(returning: .message(contact: mediatorStruct, oneToOneDiscussion: oneToOneDiscussion))

                    }
                    
                } catch {
                    assertionFailure()
                    Self.logger.fault("Core data error: \(error.localizedDescription)")
                    return continuation.resume(throwing: error)
                }
            }
            
        }
        
    }
    
    private static func determineInfosForCreatingContent(obvOwnedMessage: ObvOwnedMessage, obvStackShared: CoreDataStack<ObvMessengerPersistentContainer>) async throws -> InfosForCreatingContent {
        
        let persistedItemJSON = try PersistedItemJSON.jsonDecode(obvOwnedMessage.messagePayload)
        
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<InfosForCreatingContent, any Error>) in
            
            obvStackShared.performBackgroundTask { context in
                do {
                    
                    // Determine the appropriate discussion
                                        
                    let discussionId: DiscussionIdentifier
                    
                    if let discussionReadJSON = persistedItemJSON.discussionRead {
                        discussionId = try discussionReadJSON.getDiscussionId(ownedCryptoId: obvOwnedMessage.ownedCryptoId)
                    } else if let deleteMessagesJSON = persistedItemJSON.deleteMessagesJSON {
                        discussionId = try deleteMessagesJSON.getDiscussionId(ownedCryptoId: obvOwnedMessage.ownedCryptoId)
                    } else if let deleteDiscussionJSON = persistedItemJSON.deleteDiscussionJSON {
                        discussionId = try deleteDiscussionJSON.getDiscussionId(ownedCryptoId: obvOwnedMessage.ownedCryptoId)
                    } else {
                        Self.logger.error("For now, we dont deal with that kind of JSON item.")
                        return continuation.resume(returning: .silent)
                    }
                    
                    guard let persistedDiscussion = try PersistedDiscussion.getPersistedDiscussion(ownedCryptoId: obvOwnedMessage.ownedCryptoId, discussionId: discussionId, within: context) else {
                        Self.logger.fault("Could not find discussion in database")
                        assertionFailure()
                        return continuation.resume(returning: .silent)
                    }
                    
                    let discussionIdentifier = try persistedDiscussion.toStructureKind().discussionIdentifier
                    
                    // Depending on the item received, return the appropriate notification content
                    
                    if let discussionReadJSON = persistedItemJSON.discussionRead {
                        
                        let lastReadMessageServerTimestamp = discussionReadJSON.lastReadMessageServerTimestamp
                        
                        return continuation.resume(returning: .removeAllNotificationsOfDiscussion(
                            discussionIdentifier: discussionIdentifier,
                            lastReadMessageServerTimestamp: lastReadMessageServerTimestamp))
                                                
                    } else if let deleteMessagesJSON = persistedItemJSON.deleteMessagesJSON {
                        
                        let messageAppIdentifiers = deleteMessagesJSON.messagesToDelete.map { messageReferenceJSON in
                            ObvMessageAppIdentifier.received(
                                discussionIdentifier: discussionIdentifier,
                                senderIdentifier: messageReferenceJSON.senderIdentifier,
                                senderThreadIdentifier: messageReferenceJSON.senderThreadIdentifier,
                                senderSequenceNumber: messageReferenceJSON.senderSequenceNumber)
                        }
                        
                        return continuation.resume(returning: .removeReceivedMessages(messageAppIdentifiers: messageAppIdentifiers))
                                                
                    } else if persistedItemJSON.deleteDiscussionJSON != nil {

                        return continuation.resume(returning: .removeAllNotificationsOfDiscussion(
                            discussionIdentifier: discussionIdentifier,
                            lastReadMessageServerTimestamp: nil))

                    } else {
                        
                        Self.logger.error("For now, we dont deal with that kind of JSON item.")
                        return continuation.resume(returning: .silent)
                        
                    }


                } catch {
                    assertionFailure()
                    Self.logger.fault("Core data error: \(error.localizedDescription)")
                    return continuation.resume(throwing: error)
                }
                
            }
        }
        
    }


    private static func determineInfosForCreatingContent(obvMessage: ObvMessage, obvStackShared: CoreDataStack<ObvMessengerPersistentContainer>) async throws -> InfosForCreatingContent {
        
        let persistedItemJSON = try PersistedItemJSON.jsonDecode(obvMessage.messagePayload)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<InfosForCreatingContent, any Error>) in
            
            obvStackShared.performBackgroundTask { context in
                do {
                    
                    // Determine the owned identity
                    
                    guard let persistedObvOwnedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: obvMessage.fromContactIdentity.ownedCryptoId, within: context) else {
                        Self.logger.fault("Could not find the owned identity in database")
                        throw ObvError.couldNotFindOwnedIdentity
                    }
                    
                    // Determine the contact
                    
                    guard let persistedContactIdentity = try PersistedObvContactIdentity.get(persisted: obvMessage.fromContactIdentity, whereOneToOneStatusIs: .any, within: context) else {
                        Self.logger.fault("Could not find the contact in database")
                        throw ObvError.couldNotFindContact
                    }
                    let contact = try persistedContactIdentity.toStructure()
                                        
                    // Determine the discussion kind
                    
                    let groupV1Identifier: GroupV1Identifier?
                    let groupV2Identifier: GroupV2Identifier?
                    if let messageJSON = persistedItemJSON.message {
                        groupV1Identifier = messageJSON.groupV1Identifier
                        groupV2Identifier = messageJSON.groupV2Identifier
                    } else if let reactionJSON = persistedItemJSON.reactionJSON {
                        groupV1Identifier = reactionJSON.groupV1Identifier
                        groupV2Identifier = reactionJSON.groupV2Identifier
                    } else if let deleteMessagesJSON = persistedItemJSON.deleteMessagesJSON {
                        groupV1Identifier = deleteMessagesJSON.groupV1Identifier
                        groupV2Identifier = deleteMessagesJSON.groupV2Identifier
                    } else if let deleteDiscussionJSON = persistedItemJSON.deleteDiscussionJSON {
                        groupV1Identifier = deleteDiscussionJSON.groupV1Identifier
                        groupV2Identifier = deleteDiscussionJSON.groupV2Identifier
                    } else if let updateMessageJSON = persistedItemJSON.updateMessageJSON {
                        groupV1Identifier = updateMessageJSON.groupV1Identifier
                        groupV2Identifier = updateMessageJSON.groupV2Identifier
                    } else {
                        Self.logger.error("For now, we don't deal with this JSON item")
                        return continuation.resume(returning: .silent)
                    }
                    
                    let persistedDiscussion: PersistedDiscussion
                    
                    if let groupV1Identifier = groupV1Identifier {
                        guard let ownedIdentity = persistedContactIdentity.ownedIdentity else {
                            Self.logger.error("Could not find owned identity. This is ok if it was just deleted.")
                            return continuation.resume(throwing: ObvError.couldNotFindOwnedIdentity)
                        }
                        guard let contactGroup = try PersistedContactGroup.getContactGroup(groupIdentifier: groupV1Identifier, ownedIdentity: ownedIdentity) else {
                            Self.logger.error("Could not find contact group. We display a minimal notification.")
                            return continuation.resume(returning: .minimal)
                        }
                        persistedDiscussion = contactGroup.discussion
                    } else if let groupV2Identifier = groupV2Identifier {
                        guard let ownedIdentity = persistedContactIdentity.ownedIdentity else {
                            Self.logger.error("Could not find owned identity. This is ok if it was just deleted.")
                            return continuation.resume(throwing: ObvError.couldNotFindOwnedIdentity)
                        }
                        guard let group = try PersistedGroupV2.get(ownIdentity: ownedIdentity.cryptoId, appGroupIdentifier: groupV2Identifier, within: context) else {
                            // We are receiving a message from a known contact, within a group we don't know. It is likely that we accepted this group invitation from another
                            // owned device (otherwise, we would be a pending member and the contact would not have sent this message). Yet, we don't display the message,
                            // and only show a minimal notification. The may incite the local user to launch the app, which will create the group and receive the message.
                            Self.logger.error("Could not find group v2. We display a minimal notification.")
                            return continuation.resume(returning: .minimal)
                        }
                        guard let _discussion = group.discussion else {
                            Self.logger.fault("Could not find the discussion associated to the group v2")
                            return continuation.resume(throwing: ObvError.couldNotFindGroupV2Discussion)
                        }
                        persistedDiscussion = _discussion
                    } else if let oneToOneDiscussion = persistedContactIdentity.oneToOneDiscussion {
                        persistedDiscussion = oneToOneDiscussion
                    } else {
                        Self.logger.fault("Could not find an appropriate discussion where the received message could go.")
                        // We are in a situation where we can decide that no user notification should be shown
                        return continuation.resume(returning: .minimal)
                    }
                    
                    // If we reach this point, we found an appropriate discussion where the message can go
                    
                    let discussionKind = try persistedDiscussion.toStructureKind()
                                                                                
                    // If we reach this point, we leverage the ObvUserNotificationContentCreator to compute the content of the displayed remote user notification
                    
                    if let messageJSON = persistedItemJSON.message {
                        
                        // Check that the notification sender is allowed to send this message by simulating a message insertion (note that we shall **NOT** save the context)
                        // Note that we indicate .engine (and not .userNotification) as a source. The objective is not to introduce the message in database, just to check
                        // whether the sender is allowed to sends this message. So we simulate a proper message insertion.

                        let contactIsAllowedToPostMessage: Bool
                        do {
                            _ = try persistedObvOwnedIdentity.createOrOverridePersistedMessageReceived(
                                obvMessage: obvMessage,
                                messageJSON: messageJSON,
                                returnReceiptJSON: persistedItemJSON.returnReceipt,
                                source: .engine)
                            contactIsAllowedToPostMessage = true
                        } catch {
                            contactIsAllowedToPostMessage = false
                        }
                        
                        guard contactIsAllowedToPostMessage else {
                            assertionFailure()
                            return continuation.resume(returning: .silent)
                        }

                        context.rollback()

                        Self.logger.info("We received a notification for a message")
                        
                        // Try to determine the repliedToMessage
                        
                        let messageRepliedTo: RepliedToMessageStructure?
                        if let replyTo = persistedItemJSON.message?.replyTo,
                           let persistedMessageRepliedTo = try PersistedMessage.findMessageFrom(reference: replyTo, within: persistedDiscussion) {
                            messageRepliedTo = try persistedMessageRepliedTo.toRepliedToMessageStructure()
                            // Note that we *know* the discussion corresponding to this messageRepliedToStructure corresponds to the discussionKind above
                        } else {
                            messageRepliedTo = nil
                        }
                        
                        let infosForCreatingContent = InfosForCreatingContent.message(
                            messageJSON: messageJSON,
                            contact: contact,
                            discussionKind: discussionKind,
                            messageRepliedTo: messageRepliedTo)
                        
                        return continuation.resume(returning: infosForCreatingContent)

                    } else if let reactionJSON = persistedItemJSON.reactionJSON {
                        
                        // Check that the notification sender is allowed to react by simulating a database call (note that we shall **NOT** save the context)

                        let contactIsAllowedToSetOrUpdateReaction: Bool
                        do {
                            _ = try persistedContactIdentity.processSetOrUpdateReactionOnMessageRequestFromThisContact(
                                reactionJSON: reactionJSON,
                                messageUploadTimestampFromServer: obvMessage.messageUploadTimestampFromServer,
                                overrideExistingReaction: true)
                            contactIsAllowedToSetOrUpdateReaction = true
                        } catch {
                            contactIsAllowedToSetOrUpdateReaction = false
                        }
                        
                        context.rollback()

                        guard contactIsAllowedToSetOrUpdateReaction else {
                            assertionFailure()
                            return continuation.resume(returning: .silent)
                        }

                        Self.logger.info("We received a notification for a reaction")
                        
                        // Determine the sent message replied to
                        
                        guard let sentMessageReactedTo = try PersistedMessageSent.findMessageFrom(reference: reactionJSON.messageReference, within: persistedDiscussion) as? PersistedMessageSent else {
                            // The reaction does not concern one of our sent messages, we don't notify the user
                            return continuation.resume(returning: .silent)
                        }
                        
                        let messageReactedTo = try sentMessageReactedTo.toStructure()
                        
                        let infosForCreatingContent = InfosForCreatingContent.reaction(
                            reactionJSON: reactionJSON,
                            reactor: contact,
                            sentMessageReactedTo: messageReactedTo,
                            uploadTimestampFromServer: obvMessage.messageUploadTimestampFromServer)
                        
                        return continuation.resume(returning: infosForCreatingContent)
                        
                    } else if let deleteMessagesJSON = persistedItemJSON.deleteMessagesJSON {
                        
                        Self.logger.info("We received a notification for deleting a message")
                        
                        // Check that the notification sender is allowed to delete the message (and thus, the notification) by simulating a deletion (note that we shall **NOT** save the context)
                        // Note that we cannot rely on the infos returned by the following call: if we are executing from the notification extension, we might be in the situation where the
                        // received message is not yet persisted within the app.

                        let contactIsAllowedToDelete: Bool
                        do {
                            _ = try persistedContactIdentity.processWipeMessageRequestFromThisContact(deleteMessagesJSON: deleteMessagesJSON, messageUploadTimestampFromServer: obvMessage.messageUploadTimestampFromServer)
                            contactIsAllowedToDelete = true
                        } catch {
                            contactIsAllowedToDelete = false
                        }
                        
                        context.rollback()

                        guard contactIsAllowedToDelete else {
                            assertionFailure()
                            return continuation.resume(returning: .silent)
                        }

                        let discussionIdentifier = discussionKind.discussionIdentifier
                        
                        let messageAppIdentifiers = deleteMessagesJSON.messagesToDelete.map { messageReferenceJSON in
                            ObvMessageAppIdentifier.received(
                                discussionIdentifier: discussionIdentifier,
                                senderIdentifier: messageReferenceJSON.senderIdentifier,
                                senderThreadIdentifier: messageReferenceJSON.senderThreadIdentifier,
                                senderSequenceNumber: messageReferenceJSON.senderSequenceNumber)
                        }

                        if messageAppIdentifiers.isEmpty {
                            return continuation.resume(returning: .silent)
                        } else {
                            return continuation.resume(returning: .removeReceivedMessages(messageAppIdentifiers: messageAppIdentifiers))
                        }
                        
                    } else if let deleteDiscussionJSON = persistedItemJSON.deleteDiscussionJSON {
                        
                        Self.logger.info("We received a notification for deleting a discussion")
                        
                        // Check that the notification sender is allowed to delete the discussion (and thus, the notification) by simulating a deletion (note that we shall **NOT** save the context)
                        
                        let contactIsAllowedToDelete: Bool
                        do {
                            _ = try persistedContactIdentity.processThisContactRemoteRequestToWipeAllMessagesWithinDiscussion(deleteDiscussionJSON: deleteDiscussionJSON, messageUploadTimestampFromServer: obvMessage.messageUploadTimestampFromServer)
                            contactIsAllowedToDelete = true
                        } catch {
                            contactIsAllowedToDelete = false
                        }
                        
                        context.rollback()
                        
                        guard contactIsAllowedToDelete else {
                            assertionFailure()
                            return continuation.resume(returning: .silent)
                        }
                        
                        let discussionIdentifier = discussionKind.discussionIdentifier
                        
                        return continuation.resume(returning: .removeAllNotificationsOfDiscussion(
                            discussionIdentifier: discussionIdentifier,
                            lastReadMessageServerTimestamp: nil))
                        
                    } else if let updateMessageJSON = persistedItemJSON.updateMessageJSON {
                        
                        // If the updateMessageJSON concerns the update of a continously shared location, we don't display any notification
                        
                        if let locationJSON = updateMessageJSON.locationJSON, locationJSON.type == .SHARING {
                            return continuation.resume(returning: .silent)
                        }

                        // Check that the notification sender is allowed to update a message by simulating a database call (note that we shall **NOT** save the context)
                        
                        let isAllowedToUpdateMessage: Bool
                        do {
                            _ = try persistedContactIdentity.processUpdateMessageRequestFromThisContact(updateMessageJSON: updateMessageJSON,
                                                                                                        messageUploadTimestampFromServer: obvMessage.messageUploadTimestampFromServer)
                            isAllowedToUpdateMessage = true
                        } catch {
                            isAllowedToUpdateMessage = false
                        }

                        guard isAllowedToUpdateMessage else {
                            assertionFailure()
                            return continuation.resume(returning: .silent)
                        }
                        
                        Self.logger.info("We received a notification for updating a received message")
                        
                        // Try to determine if the repliedToMessage
                        
                        let messageRepliedTo: RepliedToMessageStructure?
                        if let replyTo = persistedItemJSON.message?.replyTo,
                           let persistedMessageRepliedTo = try PersistedMessage.findMessageFrom(reference: replyTo, within: persistedDiscussion) {
                            messageRepliedTo = try persistedMessageRepliedTo.toRepliedToMessageStructure()
                            // Note that we *know* the discussion corresponding to this messageRepliedToStructure corresponds to the discussionKind above
                        } else {
                            messageRepliedTo = nil
                        }
                        
                        let infosForCreatingContent = InfosForCreatingContent.messageEdition(
                            updateMessageJSON: updateMessageJSON,
                            contact: contact,
                            discussionKind: discussionKind,
                            messageRepliedTo: messageRepliedTo)
                        
                        return continuation.resume(returning: infosForCreatingContent)

                    } else {
                        
                        Self.logger.info("We received a notification for an item that does not contain a valid message nor a valid reaction. We don't display any user notification.")
                        return continuation.resume(returning: .silent)

                    }
                    
                    
                } catch {
                    assertionFailure()
                    Self.logger.fault("Core data error: \(error.localizedDescription)")
                    return continuation.resume(throwing: error)
                }
                
            }
            
        }

        
    }
    
    
    /// Private helper allowing to determine if we should return a silent notification.
    ///
    /// - For a hidden profile, we always send a silent notification.
    /// - When the discussion is muted, we almost always send a slient notification. The only exception: when the user configured Olvid so as to be notified when she is mentionned in the message concerned by the notification.
    private static func shouldReturnSilentNotificationContent(contact: PersistedObvContactIdentityStructure, discussionKind: PersistedDiscussionAbstractStructure.StructureKind, repliedToOrReactedTo: RepliedToOrReactedTo) -> Bool {
        
        if contact.ownedIdentity.isHidden {
            return true
        }

        let discussionLocalConfiguration = discussionKind.localConfiguration
        
        guard discussionLocalConfiguration.hasValidMuteNotificationsEndDate else {
            return false
        }
        
        let globalDiscussionNotificationOptions = ObvMessengerSettings.Discussions.notificationOptions

        switch discussionLocalConfiguration.mentionNotificationMode {

        case .alwaysNotifyWhenMentionned,
                .globalDefault where globalDiscussionNotificationOptions.contains(.alwaysNotifyWhenMentionnedEvenInMutedDiscussion):

            let ownedCryptoId = discussionKind.ownedCryptoId
            
            switch repliedToOrReactedTo {

            case .messageRepliedTo(mentionedCryptoIds: let mentionedCryptoIds, messageRepliedTo: let messageRepliedTo):
                
                // We are evaluating whether we should silence a user notification concerning a received message
                
                let messageMentionsContainOwnedIdentity = mentionedCryptoIds.contains(ownedCryptoId)
                let messageDoesReplyToMessageThatMentionsOwnedIdentity = messageRepliedTo?.doesMentionOwnedIdentity ?? false
                let messageDoesReplyToSentMessage = messageRepliedTo?.isPersistedMessageSent ?? false

                let doesMentionOwnedIdentityValue = PersistedMessageAbstractStructure.computeDoesMentionOwnedIdentityValue(
                    messageMentionsContainOwnedIdentity: messageMentionsContainOwnedIdentity,
                    messageDoesReplyToMessageThatMentionsOwnedIdentity: messageDoesReplyToMessageThatMentionsOwnedIdentity,
                    messageDoesReplyToSentMessage: messageDoesReplyToSentMessage)
                
                return !doesMentionOwnedIdentityValue
                
            case .sentMessageReactedTo:

                // We are evaluating whether we should silence a user notification concerning a reaction to one of our sent messages

                return false

            }
            
            
        case .globalDefault,
                .neverNotifyWhenDiscussionIsMuted:
            
            return true

        }
        
    }
    
    
    private static func createNotificationContentForReceivedReaction(emoji: String?, reactor: PersistedObvContactIdentityStructure, sentMessageReactedTo: PersistedMessageSentStructure, uploadTimestampFromServer: Date) async -> ObvUserNotificationContentTypeForObvMessage {
        
        let discussionKind = sentMessageReactedTo.discussionKind
        
        // In certain cases, we want to silent the notification
        
        guard !shouldReturnSilentNotificationContent(contact: reactor, discussionKind: discussionKind, repliedToOrReactedTo: .sentMessageReactedTo) else {
            return .silent
        }
        
        // A nil emoji means that the sender wants to remove her reaction
        
        guard let emoji else {
            return .removeReactionOnSentMessage(content: UNNotificationContent(),
                                                sentMessageReactedTo: sentMessageReactedTo.messageAppIdentifier,
                                                reactor: reactor.contactIdentifier)
        }
        
        guard emoji.count == 1 else {
            assertionFailure()
            return .silent
        }

        // If we reach this point, we don't silent the notification. We start from a "minimal" content that we enrich.
        
        let content = Self.createMinimalNotificationContent(badge: .unchanged).mutableContent

        //
        // Providing the primary content
        //
        
        content.title = reactor.customOrFullDisplayName
        
        switch discussionKind {
        case .oneToOneDiscussion:
            // Keep the subtitle as in the minimal notification content
            break
        case .groupDiscussion(structure: let structure):
            content.subtitle = structure.title
        case .groupV2Discussion(structure: let structure):
            content.subtitle = structure.title
        }
        
        if let messageReactedToBody = sentMessageReactedTo.textBody, !messageReactedToBody.isEmpty {
            content.body = String(localized: "REACTED_WITH_\(emoji)_TO_SENT_MESSAGE_\(messageReactedToBody)")
        } else {
            content.body = String(localized: "REACTED_WITH_\(emoji)_TO_ONE_OF_YOUR_SENT_MESSAGE")
        }

        // Providing supplementary content
        // For now, we don't deal with attachments and don't use the userInfo dictionary.

        //
        // Configuring app behavior
        //

        // We don't modify the badge
        
        // Integrating with the system
        
        if let notificationSound = discussionKind.localConfiguration.notificationSound ?? ObvMessengerSettings.Discussions.notificationSound {
            switch notificationSound {
            case .none:
                content.sound = nil
            case .system:
                // Keep the sound as it is in the minimal notification content
                break
            default:
                if let sound = notificationSound.unNotificationSound(for: content.body) {
                    content.sound = sound
                } else {
                    // Keep the sound as it is in the minimal notification content
                }
            }
        } else {
            // Keep the sound as it is in the minimal notification content
        }

        // For now, we keep the interruptionLevel of the minimal notification

        //
        // Specify the appropriate category, allowing the notification to give access to the appropriate actions
        //
        
        let userNotificationCategory = ObvUserNotificationCategoryIdentifier.newReaction
        content.setObvCategoryIdentifier(to: userNotificationCategory)

        //
        // Specify the threadIdentifier, so as to group received message notification by discussion
        //
        
        content.threadIdentifier = ObvUserNotificationThread.discussion(discussionKind.discussionIdentifier).threadIdentifier

        //
        // Set the messageAppIdentifier of the content.
        // Used when deciding what to do with the notification while the app is in the foreground
        //
        
        content.setObvDiscussionIdentifier(to: discussionKind.discussionIdentifier)
        content.setSentMessageReactedTo(to: sentMessageReactedTo.messageAppIdentifier)
        content.setReactor(to: reactor.contactIdentifier)
        content.setUploadTimestampFromServer(to: uploadTimestampFromServer)

        // Enrich the notification with communication information and return the content

        do {
            let communicationType = ObvCommunicationType.incomingReaction(reactor: reactor, sentMessageReactedTo: sentMessageReactedTo)
            let updatedContent = try await ObvCommunicationInteractor.update(notificationContent: content, communicationType: communicationType)
            return .addReactionOnSentMessage(content: updatedContent, sentMessageReactedTo: sentMessageReactedTo.messageAppIdentifier, reactor: reactor.contactIdentifier, userNotificationCategory: userNotificationCategory)
        } catch {
            assertionFailure()
            return .addReactionOnSentMessage(content: content, sentMessageReactedTo: sentMessageReactedTo.messageAppIdentifier, reactor: reactor.contactIdentifier, userNotificationCategory: userNotificationCategory)
        }

    }
    
    
    private static func createNotificationContentForReceivedMessageEdition(receivedMessageEdition: ReceivedMessageEdition) async throws -> ObvUserNotificationContentTypeForObvMessage {
     
        // This scenario presents a challenge since scheduled user notifications cannot be edited directly.
        // To address this, we remove the corresponding user notification and schedule a new one. However,
        // this approach disrupts the order of notifications within the discussion thread.
        // As a consequence, we employ a strategy where we only remove the old notification and post a new one if:
        // - There exists an old, already shown, notification;
        // - The old notification is the most recent one displayed in the discussion thread, there is nothing left to do.
        // - Otherwise, we indicate the fact that the notification was updated in the body of the notification.

        // Make sure the last shown "received message" notification corresponds to the one we wish to update. If not, don't do anything
        
        let deliveredNotifications = await UNUserNotificationCenter.current().deliveredNotifications()
            .filter({ $0.request.content.messageAppIdentifier != nil }) // Restrict to "received message" notifications
            .filter({ $0.request.content.threadIdentifier == ObvUserNotificationThread.discussion(receivedMessageEdition.messageAppIdentifier.discussionIdentifier).threadIdentifier }) // Restrict to the appropriate user notification thread (for the discussion)
            .sorted(by: { $0.date < $1.date }) // Sort the notification
        
        guard let oldNotification = deliveredNotifications.first(where: { $0.request.content.messageAppIdentifier == receivedMessageEdition.messageAppIdentifier }) else {
            return .silent
        }
        
        let isMostRecentNotification = oldNotification.request.identifier == deliveredNotifications.last?.request.identifier
        let oldNotificationShowsEditIndication = oldNotification.request.content.showsEditIndication ?? false
        let showEditIndication = !isMostRecentNotification || oldNotificationShowsEditIndication
        
        // Recover metadata about the old notification
        
        guard let messageAppIdentifier = oldNotification.request.content.messageAppIdentifier,
              let isEphemeralMessageWithUserAction = oldNotification.request.content.isEphemeralMessageWithUserAction,
              let expectedAttachmentsCount = oldNotification.request.content.expectedAttachmentsCount else {
            assertionFailure()
            return .silent
        }
                
        // If we reach this point, there exist a shown notification with the "old" version of the body.
        // We create a new notification content, identical to the one showed, except for the body

        let contentToUpdate = oldNotification.request.content.mutableCopy() as! UNMutableNotificationContent
        contentToUpdate.body = contentBody(isEphemeralMessageWithUserAction: isEphemeralMessageWithUserAction,
                                           receivedMessageBody: receivedMessageEdition.newBody,
                                           expectedAttachmentsCount: expectedAttachmentsCount,
                                           showEditIndication: showEditIndication,
                                           locationInfo: receivedMessageEdition.locationInfo)
        contentToUpdate.interruptionLevel = .passive
        contentToUpdate.setShowsEditIndication(to: showEditIndication)
        
        return .updateReceivedMessage(content: contentToUpdate, messageAppIdentifier: messageAppIdentifier)
        
    }
    
    
    private func getRequestIdentifiersOfShownUserNotificationsOperation() async {
        
    }

    
    private static func createNotificationContentForReceivedProtocolMessage(obvProtocolMessage: ObvProtocolMessage, contact: PersistedObvContactIdentityStructure, oneToOneDiscussion: PersistedOneToOneDiscussionStructure) async -> ObvUserNotificationContentTypeForObvProtocolMessage {
        
        // In certain cases, we want to silent the notification (note that we consider that a protocol message "mentions" the owned identity, which allows to break throught silent discussions)

        let repliedToOrReactedTo: RepliedToOrReactedTo = .messageRepliedTo(mentionedCryptoIds: [obvProtocolMessage.ownedCryptoId], messageRepliedTo: nil)
        let discussionKind = PersistedDiscussionAbstractStructure.StructureKind.oneToOneDiscussion(structure: oneToOneDiscussion)
        guard !shouldReturnSilentNotificationContent(contact: contact, discussionKind: discussionKind, repliedToOrReactedTo: repliedToOrReactedTo) else {
            return .silent
        }
        
        // If we reach this point, we don't silent the notification. We start from a "minimal" content that we enrich.
        
        let content = Self.createMinimalNotificationContent(badge: .unchanged).mutableContent

        //
        // Enrich the content, depending on the hideNotificationContent setting
        //

        switch ObvMessengerSettings.Privacy.hideNotificationContent {
            
        case .completely:

            // We keep the minimal notifications
            return .addProtocolMessage(content: content)

        case .partially:

            // Simply describe the nature of the notification
            content.title = String(localized: "New invitation")
            content.body = String(localized: "Tap to see the invitation")
            return .addProtocolMessage(content: content)

        case .no:
            
            //
            // Providing the primary content
            //
            
            content.title = contact.customOrFullDisplayName
            
            switch discussionKind {
            case .oneToOneDiscussion:
                // Keep the subtitle as in the minimal notification content
                break
            case .groupDiscussion(structure: let structure):
                content.subtitle = structure.title
            case .groupV2Discussion(structure: let structure):
                content.subtitle = structure.title
            }

            switch obvProtocolMessage {
            case .mutualIntroduction(mediator: _, introducedIdentity: _, introducedIdentityCoreDetails: let introducedIdentityCoreDetails):
                content.body = String(localized: "I would like to introduce you to \(introducedIdentityCoreDetails.getDisplayNameWithStyle(.firstNameThenLastName))")
            }
                        
            // Providing supplementary content
            // For now, we don't deal with attachments and don't use the userInfo dictionary.
            
            //
            // Configuring app behavior
            //
            
            content.badge = BadgeValue.unchanged.badge
            
            // Integrating with the system
            
            if let notificationSound = discussionKind.localConfiguration.notificationSound ?? ObvMessengerSettings.Discussions.notificationSound {
                switch notificationSound {
                case .none:
                    content.sound = nil
                case .system:
                    // Keep the sound as it is in the minimal notification content
                    break
                default:
                    if let sound = notificationSound.unNotificationSound(for: content.body) {
                        content.sound = sound
                    } else {
                        // Keep the sound as it is in the minimal notification content
                    }
                }
            } else {
                // Keep the sound as it is in the minimal notification content
            }
            
            // For now, we keep the interruptionLevel of the minimal notification
            
            //
            // Specify the appropriate category, allowing the notification to give access to the appropriate actions
            //

            content.setObvCategoryIdentifier(to: .protocolMessage)
            
            //
            // Specify the threadIdentifier, so as to group received message notification by discussion
            //
            
            content.threadIdentifier = ObvUserNotificationThread.discussion(discussionKind.discussionIdentifier).threadIdentifier
            
            // Setting the contact identifier on the notification, to make it easier to navigate to the appropriate invitations tab when the user
            // taps the notification.

            content.setObvContactIdentifier(to: contact.contactIdentifier)
            do {
                try content.setObvProtocolMessage(to: obvProtocolMessage)
            } catch {
                Self.logger.fault("Failed to set ObvProtocolMessage on a local user notification: \(error.localizedDescription)")
                assertionFailure()
            }
            
            // Enrich the notification with communication information and return the content
            
            do {
                let communicationType = ObvCommunicationType.incomingMessage(contact: contact, discussionKind: discussionKind, messageRepliedTo: nil, mentions: [])
                let updatedContent = try await ObvCommunicationInteractor.update(notificationContent: content, communicationType: communicationType)
                return .addProtocolMessage(content: updatedContent)
            } catch {
                assertionFailure()
                return .addProtocolMessage(content: content)
            }

        }

    }
    

    private static func createNotificationContentForReceivedMessage(receivedMessage: ReceivedMessage, expectedAttachmentsCount: Int, contact: PersistedObvContactIdentityStructure, discussionKind: PersistedDiscussionAbstractStructure.StructureKind, messageRepliedTo: RepliedToMessageStructure?, uploadTimestampFromServer: Date) async -> ObvUserNotificationContentTypeForObvMessage {
        
        // In certain cases, we want to silent the notification
        
        let repliedToOrReactedTo: RepliedToOrReactedTo = .messageRepliedTo(mentionedCryptoIds: receivedMessage.mentionedCryptoIds, messageRepliedTo: messageRepliedTo)
        guard !shouldReturnSilentNotificationContent(contact: contact, discussionKind: discussionKind, repliedToOrReactedTo: repliedToOrReactedTo) else {
            return .silent
        }
        
        // If we reach this point, we don't silent the notification. We start from a "minimal" content that we enrich.
        
        let content = Self.createMinimalNotificationContent(badge: .unchanged).mutableContent

        //
        // Set the messageAppIdentifier of the content. This makes useful when receiving a update for the message
        //
        
        content.setObvMessageAppIdentifier(to: receivedMessage.messageAppIdentifier)
        content.setExpectedAttachmentsCount(to: expectedAttachmentsCount)
        content.setObvDiscussionIdentifier(to: discussionKind.discussionIdentifier)
        content.setUploadTimestampFromServer(to: uploadTimestampFromServer)
        
        let isEphemeralMessageWithUserAction = receivedMessage.isEphemeralMessageWithUserAction
        content.setIsEphemeralMessageWithUserAction(to: isEphemeralMessageWithUserAction)

        
        //
        // Enrich the content, depending on the hideNotificationContent setting
        //

        switch ObvMessengerSettings.Privacy.hideNotificationContent {
            
        case .completely:

            //
            // Specify the appropriate category, allowing the notification to give access to the appropriate actions
            //
            
            let userNotificationCategory: ObvUserNotificationCategoryIdentifier = .newMessageWithHiddenContent
            content.setObvCategoryIdentifier(to: userNotificationCategory)

            // We keep the minimal notifications
            return .addReceivedMessage(content: content, messageAppIdentifier: receivedMessage.messageAppIdentifier, userNotificationCategory: userNotificationCategory, contactDeviceUIDs: contact.contactDeviceUIDs)

        case .partially:
            
            let userNotificationCategory: ObvUserNotificationCategoryIdentifier = .newMessageWithHiddenContent
            content.setObvCategoryIdentifier(to: userNotificationCategory)

            // Simply describe the nature of the notification
            content.title = String(localized: "New message")
            content.body = String(localized: "Tap to see the message")
            return .addReceivedMessage(content: content, messageAppIdentifier: receivedMessage.messageAppIdentifier, userNotificationCategory: userNotificationCategory, contactDeviceUIDs: contact.contactDeviceUIDs)

        case .no:
            
            //
            // Providing the primary content
            //
            
            content.title = contact.customOrFullDisplayName
            
            switch discussionKind {
            case .oneToOneDiscussion:
                // Keep the subtitle as in the minimal notification content
                break
            case .groupDiscussion(structure: let structure):
                content.subtitle = structure.title
            case .groupV2Discussion(structure: let structure):
                content.subtitle = structure.title
            }

            content.body = contentBody(isEphemeralMessageWithUserAction: isEphemeralMessageWithUserAction, receivedMessageBody: receivedMessage.body, expectedAttachmentsCount: expectedAttachmentsCount, showEditIndication: false, locationInfo: receivedMessage.locationInfo)
            
            // Providing supplementary content
            // For now, we don't deal with attachments and don't use the userInfo dictionary.
            
            //
            // Configuring app behavior
            //
            
            content.badge = NSNumber(integerLiteral: receivedMessage.badgeCount+1)
            
            // Integrating with the system
            
            if let notificationSound = discussionKind.localConfiguration.notificationSound ?? ObvMessengerSettings.Discussions.notificationSound {
                switch notificationSound {
                case .none:
                    content.sound = nil
                case .system:
                    // Keep the sound as it is in the minimal notification content
                    break
                default:
                    if let sound = notificationSound.unNotificationSound(for: content.body) {
                        content.sound = sound
                    } else {
                        // Keep the sound as it is in the minimal notification content
                    }
                }
            } else {
                // Keep the sound as it is in the minimal notification content
            }
            
            // For now, we keep the interruptionLevel of the minimal notification
            
            //
            // Specify the appropriate category, allowing the notification to give access to the appropriate actions
            //
            
            let userNotificationCategory: ObvUserNotificationCategoryIdentifier
            if isEphemeralMessageWithUserAction {
                userNotificationCategory = ObvUserNotificationCategoryIdentifier.newMessageWithLimitedVisibility
            } else {
                userNotificationCategory = ObvUserNotificationCategoryIdentifier.newMessage
            }
            content.setObvCategoryIdentifier(to: userNotificationCategory)
            
            //
            // Specify the threadIdentifier, so as to group received message notification by discussion
            //
            
            content.threadIdentifier = ObvUserNotificationThread.discussion(discussionKind.discussionIdentifier).threadIdentifier
            
            // Enrich the notification with communication information and return the content
            
            do {
                let communicationType = ObvCommunicationType.incomingMessage(contact: contact, discussionKind: discussionKind, messageRepliedTo: messageRepliedTo, mentions: [])
                let updatedContent = try await ObvCommunicationInteractor.update(notificationContent: content, communicationType: communicationType)
                return .addReceivedMessage(content: updatedContent, messageAppIdentifier: receivedMessage.messageAppIdentifier, userNotificationCategory: userNotificationCategory, contactDeviceUIDs: contact.contactDeviceUIDs)
            } catch {
                assertionFailure()
                return .addReceivedMessage(content: content, messageAppIdentifier: receivedMessage.messageAppIdentifier, userNotificationCategory: userNotificationCategory, contactDeviceUIDs: contact.contactDeviceUIDs)
            }
            
        }
        
    }

    
    /// Helper used to compute the `content.body` for a received message notification.
    private static func contentBody(isEphemeralMessageWithUserAction: Bool, receivedMessageBody: String?, expectedAttachmentsCount: Int, showEditIndication: Bool, locationInfo: LocationInfo?) -> String {
        let contentBody: String
        if isEphemeralMessageWithUserAction {
            contentBody = String(localized: "EPHEMERAL_MESSAGE")
        } else if let locationInfo {
            switch locationInfo.type {
            case .SEND:
                if let address = locationInfo.address {
                    contentBody = String(localized: "SHARED_A_PLACE") + ": \(address)"
                } else {
                    contentBody = String(localized: "SHARED_A_PLACE")
                }
            case .SHARING:
                contentBody = String(localized: "STARTED_SHARING_LOCATION")
            case .END_SHARING:
                contentBody = String(localized: "STOPPED_SHARING_LOCATION")
            }
        } else if let body = receivedMessageBody, !body.isEmpty {
            if expectedAttachmentsCount == 0 {
                if showEditIndication {
                    contentBody = "[" + String(localized: "EDITED") + "] " + body
                } else {
                    contentBody = body
                }
            } else {
                contentBody = [
                    body,
                    String(localized: "\(expectedAttachmentsCount)_ATTACHMENTS")
                ].joined(separator: "\n")
            }
        } else {
            if expectedAttachmentsCount == 0 {
                // Keep the body as it is in the minimal notification content
                contentBody = String(localized: "Olvid requires your attention")
            } else {
                contentBody = String(localized: "\(expectedAttachmentsCount)_ATTACHMENTS")
            }
        }
        return contentBody
    }

    
}


// MARK: - Helper types

extension ObvUserNotificationContentCreator {
    
    private enum InfosForCreatingContent: Sendable {
        
        case silent
        case minimal

        case message(messageJSON: MessageJSON, contact: PersistedObvContactIdentityStructure, discussionKind: PersistedDiscussionAbstractStructure.StructureKind, messageRepliedTo: RepliedToMessageStructure?)
        
        case messageEdition(updateMessageJSON: UpdateMessageJSON, contact: PersistedObvContactIdentityStructure, discussionKind: PersistedDiscussionAbstractStructure.StructureKind, messageRepliedTo: RepliedToMessageStructure?)
        
        case reaction(reactionJSON: ReactionJSON, reactor: PersistedObvContactIdentityStructure, sentMessageReactedTo: PersistedMessageSentStructure, uploadTimestampFromServer: Date)

        case removeReceivedMessages(messageAppIdentifiers: [ObvMessageAppIdentifier])

        case removeAllNotificationsOfDiscussion(discussionIdentifier: ObvDiscussionIdentifier, lastReadMessageServerTimestamp: Date?)
        
    }
    
    
    private enum InfosForCreatingProtocolContent: Sendable {
        
        case silent
        case minimal

        case message(contact: PersistedObvContactIdentityStructure, oneToOneDiscussion: PersistedOneToOneDiscussionStructure)
        
    }

    
    private enum RepliedToOrReactedTo {
        case messageRepliedTo(mentionedCryptoIds: [ObvCryptoId], messageRepliedTo: RepliedToMessageStructure?)
        case sentMessageReactedTo
    }
        
    
    /// Simple structure containing the essential information about a received message, allowing to construct a user notification.
    fileprivate struct ReceivedMessage {
        let messageAppIdentifier: ObvMessageAppIdentifier
        let mentionedCryptoIds: [ObvCryptoId]
        let isEphemeralMessageWithUserAction: Bool
        let body: String?
        let badgeCount: Int
        let locationInfo: LocationInfo?
    }
    
    fileprivate struct LocationInfo {
        let type: LocationJSON.LocationSharingType
        let address: String?
    }
    
    fileprivate struct ReceivedMessageEdition {
        let messageAppIdentifier: ObvMessageAppIdentifier
        let newBody: String?
        let locationInfo: LocationInfo?
    }

    
    public enum BadgeValue {
        case unchanged
        case removed
        case new(value: NSNumber) // Where value is expected to be > 0
        fileprivate var badge: NSNumber? {
            switch self {
            case .unchanged: return nil
            case .removed: return 0
            case .new(let value): return value
            }
        }
    }
    
}


// MARK: - Other private extensions


fileprivate extension String {
    
    init(localized keyAndValue: String.LocalizationValue) {
        self.init(localized: keyAndValue, bundle: ObvUserNotificationsCreatorResources.bundle)
    }
    
}


fileprivate extension ObvDialog.Category {
    
    var shouldShowSilentNotification: Bool {
        switch self {
        case .inviteSent,
                .invitationAccepted,
                .sasConfirmed,
                .mediatorInviteAccepted,
                .oneToOneInvitationSent,
                .syncRequestReceivedFromOtherOwnedDevice,
                .freezeGroupV2Invite:
            return true
        case .acceptInvite,
                .sasExchange,
                .mutualTrustConfirmed,
                .acceptMediatorInvite,
                .acceptGroupInvite,
                .oneToOneInvitationReceived,
                .acceptGroupV2Invite:
            return false
        }
    }
}
