/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import CoreData
import ObvEngine
import Intents
import os.log
import MobileCoreServices
import ObvTypes
import ObvUICoreData
import ObvSettings


struct UserNotificationKeys {
    static let id = "id"
    static let deepLinkDescription = "deepLinkDescription"
    static let persistedDiscussionPermanentIDDescription = "persistedDiscussionPermanentIDDescription"
    static let persistedContactPermanentIDDescription = "persistedContactPermanentIDDescription"
    static let reactionTimestamp = "reactionTimestamp"
    static let callUUID = "callUUID"
    static let messageIdentifierForNotification = "messageIdentifierForNotification"
    static let persistedInvitationUUID = "persistedInvitationUUID"
    static let messageIdentifierFromEngine = "messageIdentifierFromEngine"
    static let reactionIdentifierForNotification = "reactionIdentifierForNotification"
    static let ownedIdentityAsHexString = "ownedIdentityAsHexString"
}

struct UserNotificationCreator {

    private static let thumbnailPhotoSide = CGFloat(300)
    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: UserNotificationCreator.self))

    struct MissedCallNotificationInfos {
        let ownedCryptoId: ObvCryptoId
        let discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>
        let contactCustomOrFullDisplayName: String
        let receivedMessageIntentInfos: ReceivedMessageIntentInfos
        let discussionNotificationSound: NotificationSound?
        
        init(contact: PersistedObvContactIdentity.Structure, discussionKind: PersistedDiscussion.StructureKind, urlForStoringPNGThumbnail: URL?) {
            self.ownedCryptoId = contact.ownedIdentity.cryptoId
            self.discussionPermanentID = discussionKind.discussionPermanentID
            self.contactCustomOrFullDisplayName = contact.customOrFullDisplayName
            receivedMessageIntentInfos = ReceivedMessageIntentInfos.init(contact: contact, discussionKind: discussionKind, urlForStoringPNGThumbnail: urlForStoringPNGThumbnail)
            discussionNotificationSound = discussionKind.localConfiguration.notificationSound
        }
        
    }

    static func createMissedCallNotification(callUUID: UUID,
                                             infos: MissedCallNotificationInfos,
                                             badge: NSNumber? = nil) ->
    (notificationId: ObvUserNotificationIdentifier, notificationContent: UNNotificationContent) {

        let hideNotificationContent = ObvMessengerSettings.Privacy.hideNotificationContent

        // Configure the notification content
        
        let notificationContent = UNMutableNotificationContent()
        notificationContent.badge = badge
        notificationContent.sound = UNNotificationSound.default

        let notificationId = ObvUserNotificationIdentifier.missedCall(callUUID: callUUID)

        var sendMessageIntent: INSendMessageIntent?

        switch hideNotificationContent {

        case .no:
            
            notificationContent.title = infos.contactCustomOrFullDisplayName
            notificationContent.body = Strings.MissedCall.title

            let deepLink = ObvDeepLink.singleDiscussion(ownedCryptoId: infos.ownedCryptoId, objectPermanentID: infos.discussionPermanentID)
            notificationContent.userInfo[UserNotificationKeys.deepLinkDescription] = deepLink.description
            notificationContent.userInfo[UserNotificationKeys.persistedDiscussionPermanentIDDescription] = infos.discussionPermanentID.description
            notificationContent.userInfo[UserNotificationKeys.callUUID] = callUUID.uuidString

            sendMessageIntent = IntentManager.getSendMessageIntentForMessageReceived(infos: infos.receivedMessageIntentInfos, showGroupName: true)

            setNotificationSound(discussionNotificationSound: infos.discussionNotificationSound, notificationContent: notificationContent)
            
        case .partially:

            notificationContent.body = Strings.MissedCall.title
            let deepLink = ObvDeepLink.singleDiscussion(ownedCryptoId: infos.ownedCryptoId, objectPermanentID: infos.discussionPermanentID)
            notificationContent.userInfo[UserNotificationKeys.deepLinkDescription] = deepLink.description
            notificationContent.userInfo[UserNotificationKeys.persistedDiscussionPermanentIDDescription] = infos.discussionPermanentID.description
            notificationContent.userInfo[UserNotificationKeys.callUUID] = callUUID.uuidString

        case .completely:

            notificationContent.title = Strings.NewPersistedMessageReceivedMinimal.title
            notificationContent.subtitle = ""
            notificationContent.body = Strings.NewPersistedMessageReceivedMinimal.body
            
            let deepLink = ObvDeepLink.latestDiscussions(ownedCryptoId: infos.ownedCryptoId)
            notificationContent.userInfo[UserNotificationKeys.deepLinkDescription] = deepLink.description
        }

        setThreadAndCategory(notificationId: notificationId, notificationContent: notificationContent)

        if let sendMessageIntent = sendMessageIntent,
           let updatedNotificationContent = try? notificationContent.updating(from: sendMessageIntent) {
            return (notificationId, updatedNotificationContent)
        } else {
            return (notificationId, notificationContent)
        }
    }

    
    /// This static method is used as a best effort to deliver a notification. For example, it is used when, after an app upgrade, we receive a user notification before the app has been launched and thus, before database migration.
    /// In that situation, the engine initialisation fails within this extension (since this extension is not allowed to perform database migrations). Still, we want users to be notified. We create a minimal notification to do so.
    /// This method is also used at the very beginning of ``createNewMessageNotification``, to create a notification content that we then augment if possible.
    static func createMinimalNotification(badge: NSNumber? = nil) -> (notificationId: ObvUserNotificationIdentifier, notificationContent: UNMutableNotificationContent) {
        
        // Configure the notification content
        let notificationContent = UNMutableNotificationContent()
        notificationContent.badge = badge
        notificationContent.sound = UNNotificationSound.default

        let notificationId = ObvUserNotificationIdentifier.staticIdentifier
        
        notificationContent.title = Strings.NewPersistedMessageReceivedMinimal.title
        notificationContent.subtitle = ""
        notificationContent.body = Strings.NewPersistedMessageReceivedMinimal.body
        
        let deepLink = ObvDeepLink.latestDiscussions(ownedCryptoId: nil) // We cannot determine the appropriate owned identity at this point
        notificationContent.userInfo[UserNotificationKeys.deepLinkDescription] = deepLink.description

        setThreadAndCategory(notificationId: notificationId, notificationContent: notificationContent)

        return (notificationId, notificationContent)

    }

    // Location of file used by UNNotificationAttachement
    enum NotificationAttachmentLocation {
        // The location will be the the identifier of the notificationID
        case notificationID
        // Custom identifier (e.g the notification service uses an UUID and not notificationID)
        case custom(_: String)

        func getLocation(_ notificationId: ObvUserNotificationIdentifier) -> String {
            switch self {
            case .notificationID:
                return notificationId.getIdentifier()
            case .custom(let identifier):
                return identifier
            }
        }
    }


    struct NewMessageNotificationInfos {
        
        let ownedCryptoId: ObvCryptoId
        let body: String
        let messageIdentifierFromEngine: Data
        let contactPermanentID: ObvManagedObjectPermanentID<PersistedObvContactIdentity>
        let discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>
        let contactCustomOrFullDisplayName: String
        let groupDiscussionTitle: String?
        let discussionNotificationSound: NotificationSound?
        public let isEphemeralMessageWithUserAction: Bool
        let receivedMessageIntentInfos: ReceivedMessageIntentInfos
        let attachmentLocation: NotificationAttachmentLocation
        let attachmentsCount: Int
        let attachementImages: [NotificationAttachmentImage]?

        init(messageReceived: PersistedMessageReceived.Structure,
             attachmentLocation: NotificationAttachmentLocation,
             urlForStoringPNGThumbnail: URL?) {
            self.ownedCryptoId = messageReceived.contact.ownedIdentity.cryptoId
            self.body = messageReceived.textBody ?? ""
            self.messageIdentifierFromEngine = messageReceived.messageIdentifierFromEngine
            self.contactPermanentID = messageReceived.contact.objectPermanentID
            self.discussionPermanentID = messageReceived.discussionKind.discussionPermanentID
            self.contactCustomOrFullDisplayName = messageReceived.contact.customOrFullDisplayName
            switch messageReceived.discussionKind {
            case .groupDiscussion(structure: let structure):
                self.groupDiscussionTitle = structure.title
            case .groupV2Discussion(structure: let structure):
                self.groupDiscussionTitle = structure.title
            case .oneToOneDiscussion:
                self.groupDiscussionTitle = nil
            }
            self.discussionNotificationSound = messageReceived.discussionKind.localConfiguration.notificationSound
            self.isEphemeralMessageWithUserAction = messageReceived.isReplyToAnotherMessage
            self.receivedMessageIntentInfos = ReceivedMessageIntentInfos(messageReceived: messageReceived, urlForStoringPNGThumbnail: urlForStoringPNGThumbnail)
            self.attachmentLocation = attachmentLocation
            self.attachmentsCount = messageReceived.attachmentsCount
            self.attachementImages = messageReceived.attachementImages
        }
        
        init(body: String,
             messageIdentifierFromEngine: Data,
             contact: PersistedObvContactIdentity.Structure,
             discussionKind: PersistedDiscussion.StructureKind,
             isEphemeralMessageWithUserAction: Bool,
             attachmentsCount: Int,
             attachementImages: [NotificationAttachmentImage]?,
             attachmentLocation: NotificationAttachmentLocation,
             urlForStoringPNGThumbnail: URL?) async {
            self.ownedCryptoId = contact.ownedIdentity.cryptoId
            self.body = body
            self.messageIdentifierFromEngine = messageIdentifierFromEngine
            self.contactPermanentID = contact.objectPermanentID
            self.discussionPermanentID = discussionKind.discussionPermanentID
            self.contactCustomOrFullDisplayName = contact.customOrFullDisplayName
            switch discussionKind {
            case .groupDiscussion(structure: let structure):
                self.groupDiscussionTitle = structure.title
            case .groupV2Discussion(structure: let structure):
                self.groupDiscussionTitle = structure.title
            case .oneToOneDiscussion:
                self.groupDiscussionTitle = nil
            }
            self.discussionNotificationSound = discussionKind.localConfiguration.notificationSound
            self.isEphemeralMessageWithUserAction = isEphemeralMessageWithUserAction
            self.receivedMessageIntentInfos = ReceivedMessageIntentInfos(contact: contact, discussionKind: discussionKind, urlForStoringPNGThumbnail: urlForStoringPNGThumbnail)
            self.attachmentLocation = attachmentLocation
            self.attachmentsCount = attachmentsCount
            self.attachementImages = attachementImages
        }

    }

    /// This static method creates a new message notification.
    static func createNewMessageNotification(infos: NewMessageNotificationInfos,
                                             badge: NSNumber? = nil,
                                             addNotificationSilently: Bool) ->
    (notificationId: ObvUserNotificationIdentifier, notificationContent: UNNotificationContent) {
                
        let hideNotificationContent = ObvMessengerSettings.Privacy.hideNotificationContent

        // Configure the minimal notification content
        var (notificationId, notificationContent) = createMinimalNotification(badge: badge)

        if addNotificationSilently,
           #available(iOS 15, *) {
            notificationContent.interruptionLevel = .passive
        }

        var incomingMessageIntent: INSendMessageIntent?

        switch hideNotificationContent {
            
        case .no:

            if infos.isEphemeralMessageWithUserAction {
                notificationId = .newMessageNotificationWithHiddenContent
            } else {
                notificationId = .newMessage(messageIdentifierFromEngine: infos.messageIdentifierFromEngine)
            }

            notificationContent.title = infos.contactCustomOrFullDisplayName
            if let groupDiscussionTitle = infos.groupDiscussionTitle {
                notificationContent.subtitle = groupDiscussionTitle
            }
            if infos.body.isEmpty {
                if infos.attachmentsCount == 0 {
                    notificationContent.body = UserNotificationCreator.Strings.NewPersistedMessageReceivedMinimal.body
                } else {
                    notificationContent.body = Strings.NewPersistedMessageReceived.body(infos.attachmentsCount)
                }
            } else {
                if infos.attachmentsCount == 0 {
                    notificationContent.body = infos.body
                } else {
                    notificationContent.body = [infos.body, Strings.NewPersistedMessageReceived.body(infos.attachmentsCount)].joined(separator: "\n")
                }
            }

            let deepLink = ObvDeepLink.singleDiscussion(ownedCryptoId: infos.ownedCryptoId, objectPermanentID: infos.discussionPermanentID)
            notificationContent.userInfo[UserNotificationKeys.deepLinkDescription] = deepLink.description
            notificationContent.userInfo[UserNotificationKeys.persistedDiscussionPermanentIDDescription] = infos.discussionPermanentID.description
            notificationContent.userInfo[UserNotificationKeys.messageIdentifierForNotification] = notificationId.getIdentifier()
            notificationContent.userInfo[UserNotificationKeys.persistedContactPermanentIDDescription] = infos.contactPermanentID.description
            notificationContent.userInfo[UserNotificationKeys.messageIdentifierFromEngine] = infos.messageIdentifierFromEngine.hexString()

            incomingMessageIntent = IntentManager.getSendMessageIntentForMessageReceived(infos: infos.receivedMessageIntentInfos, showGroupName: true)

            setNotificationSound(discussionNotificationSound: infos.discussionNotificationSound, notificationContent: notificationContent)

            let location = infos.attachmentLocation.getLocation(notificationId)
            setNotificationAttachments(location: location,
                                       attachementImages: infos.attachementImages,
                                       notificationContent: notificationContent)

        case .partially:

            notificationId = ObvUserNotificationIdentifier.newMessageNotificationWithHiddenContent
            
            notificationContent.title = Strings.NewPersistedMessageReceivedHiddenContent.title
            notificationContent.subtitle = ""
            notificationContent.body = Strings.NewPersistedMessageReceivedHiddenContent.body

            let deepLink = ObvDeepLink.singleDiscussion(ownedCryptoId: infos.ownedCryptoId, objectPermanentID: infos.discussionPermanentID)
            notificationContent.userInfo[UserNotificationKeys.deepLinkDescription] = deepLink.description
            notificationContent.userInfo[UserNotificationKeys.persistedDiscussionPermanentIDDescription] = infos.discussionPermanentID.description
            notificationContent.userInfo[UserNotificationKeys.messageIdentifierForNotification] = notificationId.getIdentifier()

        case .completely:
            
            // In that case, we keep the "minimal" notification content created earlier.
            break
            
        }
        
        setThreadAndCategory(notificationId: notificationId, notificationContent: notificationContent)

        if let incomingMessageIntent = incomingMessageIntent,
           let updatedNotificationContent = try? notificationContent.updating(from: incomingMessageIntent) {
            return (notificationId, updatedNotificationContent)
        } else {
            return (notificationId, notificationContent)
        }
    }


    static func createInvitationNotification(obvDialog: ObvDialog, persistedInvitationUUID: UUID) -> (notificationId: ObvUserNotificationIdentifier, notificationContent: UNMutableNotificationContent)? {
        
        let hideNotificationContent = ObvMessengerSettings.Privacy.hideNotificationContent
        
        // Configure the notification content
        let notificationContent = UNMutableNotificationContent()
        notificationContent.sound = UNNotificationSound.default
        
        // We first configure the notication title, subtile and body
        
        switch hideNotificationContent {

        case .no:
            
            switch obvDialog.category {
            case .acceptInvite(contactIdentity: let contactIdentity):
                let contactDisplayName = contactIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full)
                notificationContent.title = Strings.AcceptInvite.title
                notificationContent.body = Strings.AcceptInvite.body(contactDisplayName)
            case .sasExchange(contactIdentity: let contactIdentity, sasToDisplay: _, numberOfBadEnteredSas: let numberOfBadEnteredSas):
                guard numberOfBadEnteredSas == 0 else { return nil } // Do not show any notification when the user enters a bad SAS
                let contactDisplayName = contactIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full)
                notificationContent.title = Strings.SasExchange.title
                notificationContent.body = Strings.SasExchange.body(contactDisplayName)
            case .mutualTrustConfirmed(contactIdentity: let contactIdentity):
                let contactDisplayName = contactIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full)
                notificationContent.title = Strings.MutualTrustConfirmed.title
                notificationContent.body = Strings.MutualTrustConfirmed.body(contactDisplayName)
            case .acceptMediatorInvite(contactIdentity: let contactIdentity, mediatorIdentity: let mediatorIdentity):
                let contactDisplayName = contactIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full)
                let mediatorDisplayName = mediatorIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full)
                notificationContent.title = Strings.AcceptMediatorInvite.title
                notificationContent.body = Strings.AcceptMediatorInvite.body(mediatorDisplayName, contactDisplayName)
            case .acceptGroupInvite(groupMembers: _, groupOwner: let contactIdentity):
                let contactDisplayName = contactIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full)
                notificationContent.title = Strings.AcceptGroupInvite.title
                notificationContent.body = Strings.AcceptGroupInvite.body(contactDisplayName)
            case .oneToOneInvitationReceived(contactIdentity: let contactIdentity):
                let contactDisplayName = contactIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full)
                notificationContent.title = Strings.AcceptOneToOneInvite.title
                notificationContent.body = Strings.AcceptOneToOneInvite.body(contactDisplayName)
            case .acceptGroupV2Invite(inviter: let inviter, group: _):
                ObvStack.shared.performBackgroundTaskAndWait { context in
                    guard let inviterContact = try? PersistedObvContactIdentity.get(contactCryptoId: inviter, ownedIdentityCryptoId: obvDialog.ownedCryptoId, whereOneToOneStatusIs: .any, within: context) else {
                        assertionFailure()
                        return
                    }
                    let inviterDisplayName = inviterContact.customOrNormalDisplayName
                    notificationContent.title = Strings.AcceptGroupInvite.title
                    notificationContent.body = Strings.AcceptGroupInvite.body(inviterDisplayName)
                }
                
            case .inviteSent,
                 .invitationAccepted,
                 .sasConfirmed,
                 .mediatorInviteAccepted,
                 .oneToOneInvitationSent,
                 .syncRequestReceivedFromOtherOwnedDevice,
                 .freezeGroupV2Invite:
                // For now, we do not notify when receiving these dialogs
                return nil
            }

            
        case .partially:
            
            notificationContent.title = Strings.NewInvitationReceivedHiddenContent.title
            notificationContent.subtitle = ""
            notificationContent.body = Strings.NewInvitationReceivedHiddenContent.body
            
        case .completely:
            
            notificationContent.title = Strings.NewPersistedMessageReceivedMinimal.title
            notificationContent.subtitle = ""
            notificationContent.body = Strings.NewPersistedMessageReceivedMinimal.body

        }
        
        // We have configured the title, subtitle, and body. We now configure the identifier and deeplink
        
        let notificationId: ObvUserNotificationIdentifier
        
        switch hideNotificationContent {
            
        case .no, .partially:
            
            // Whatever the exact category, we want to add a deep link to the invitations
            let deepLink = ObvDeepLink.invitations(ownedCryptoId: obvDialog.ownedCryptoId)
            notificationContent.userInfo[UserNotificationKeys.deepLinkDescription] = deepLink.description
            
            // Whatever the exact category, we add the concerned owned identity
            notificationContent.userInfo[UserNotificationKeys.ownedIdentityAsHexString] = obvDialog.ownedCryptoId.getIdentity().hexString()

            switch obvDialog.category {
            case .acceptInvite:
                notificationId = ObvUserNotificationIdentifier.acceptInvite(persistedInvitationUUID: persistedInvitationUUID)
                notificationContent.userInfo[UserNotificationKeys.persistedInvitationUUID] = persistedInvitationUUID.uuidString
            case .sasExchange(contactIdentity: _, sasToDisplay: _, numberOfBadEnteredSas: let numberOfBadEnteredSas):
                guard numberOfBadEnteredSas == 0 else { return nil } // Do not show any notification when the user enters a bad SAS
                notificationId = ObvUserNotificationIdentifier.sasExchange(persistedInvitationUUID: persistedInvitationUUID)
            case .mutualTrustConfirmed:
                notificationId = ObvUserNotificationIdentifier.mutualTrustConfirmed(persistedInvitationUUID: persistedInvitationUUID)
            case .acceptMediatorInvite:
                notificationId = ObvUserNotificationIdentifier.acceptMediatorInvite(persistedInvitationUUID: persistedInvitationUUID)
                notificationContent.userInfo[UserNotificationKeys.persistedInvitationUUID] = persistedInvitationUUID.uuidString
            case .acceptGroupInvite:
                notificationId = ObvUserNotificationIdentifier.acceptGroupInvite(persistedInvitationUUID: persistedInvitationUUID)
                notificationContent.userInfo[UserNotificationKeys.persistedInvitationUUID] = persistedInvitationUUID.uuidString
            case .oneToOneInvitationReceived:
                notificationId = ObvUserNotificationIdentifier.oneToOneInvitationReceived(persistedInvitationUUID: persistedInvitationUUID)
                notificationContent.userInfo[UserNotificationKeys.persistedInvitationUUID] = persistedInvitationUUID.uuidString
            case .acceptGroupV2Invite:
                notificationId = ObvUserNotificationIdentifier.acceptGroupInvite(persistedInvitationUUID: persistedInvitationUUID)
                notificationContent.userInfo[UserNotificationKeys.persistedInvitationUUID] = persistedInvitationUUID.uuidString
            case .inviteSent,
                 .invitationAccepted,
                 .sasConfirmed,
                 .mediatorInviteAccepted,
                 .oneToOneInvitationSent,
                 .syncRequestReceivedFromOtherOwnedDevice,
                 .freezeGroupV2Invite:
                // For now, we do not notify when receiving these dialogs
                return nil
            }
            
        case .completely:
            
            notificationId = ObvUserNotificationIdentifier.staticIdentifier
            
            // Even for an invitation, we navigate to the list of latest discussions
            let deepLink = ObvDeepLink.latestDiscussions(ownedCryptoId: obvDialog.ownedCryptoId)
            notificationContent.userInfo[UserNotificationKeys.deepLinkDescription] = deepLink.description

        }

        setThreadAndCategory(notificationId: notificationId, notificationContent: notificationContent)

        return (notificationId, notificationContent)

    }

    static func createRequestRecordPermissionNotification() -> (notificationId: ObvUserNotificationIdentifier, notificationContent: UNNotificationContent) {

        let notificationContent = UNMutableNotificationContent()
        notificationContent.sound = UNNotificationSound.default

        notificationContent.title = NSLocalizedString("REJECTED_INCOMING_CALL", comment: "")
        notificationContent.body = NSLocalizedString("REJECTED_INCOMING_CALL_BECAUSE_RECORD_PERMISSION_IS_UNDETERMINED_NOTIFICATION_BODY", comment: "")

        let deepLink = ObvDeepLink.requestRecordPermission

        notificationContent.userInfo[UserNotificationKeys.deepLinkDescription] = deepLink.description
        let notificationId = ObvUserNotificationIdentifier.shouldGrantRecordPermissionToReceiveIncomingCalls

        setThreadAndCategory(notificationId: notificationId, notificationContent: notificationContent)

        return (notificationId, notificationContent)
    }

    static func createDeniedRecordPermissionNotification() -> (notificationId: ObvUserNotificationIdentifier, notificationContent: UNNotificationContent) {

        let notificationContent = UNMutableNotificationContent()
        notificationContent.sound = UNNotificationSound.default

        notificationContent.title = NSLocalizedString("REJECTED_INCOMING_CALL", comment: "")
        notificationContent.body = NSLocalizedString("REJECTED_INCOMING_CALL_BECAUSE_RECORD_PERMISSION_IS_DENIED_NOTIFICATION_BODY", comment: "")

        let deepLink = ObvDeepLink.requestRecordPermission
        notificationContent.userInfo[UserNotificationKeys.deepLinkDescription] = deepLink.description

        let notificationId = ObvUserNotificationIdentifier.shouldGrantRecordPermissionToReceiveIncomingCalls

        setThreadAndCategory(notificationId: notificationId, notificationContent: notificationContent)

        return (notificationId, notificationContent)
    }


    struct ReactionNotificationInfos {
        
        let ownedCryptoId: ObvCryptoId
        let messagePermanentID: ObvManagedObjectPermanentID<PersistedMessageSent>
        let discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>
        let contactPermanentID: ObvManagedObjectPermanentID<PersistedObvContactIdentity>
        let contactCustomOrFullDisplayName: String
        let discussionNotificationSound: NotificationSound?
        let isEphemeralPersistedMessageSentWithLimitedVisibility: Bool
        let messageTextBody: String?
        let receivedMessageIntentInfos: ReceivedMessageIntentInfos

        init(messageSent: PersistedMessageSent.Structure, contact: PersistedObvContactIdentity.Structure, urlForStoringPNGThumbnail: URL?) {
            let discussionKind = messageSent.discussionKind
            self.ownedCryptoId = discussionKind.ownedCryptoId
            self.messagePermanentID = messageSent.objectPermanentID
            self.discussionPermanentID = discussionKind.discussionPermanentID
            self.contactPermanentID = contact.objectPermanentID
            self.contactCustomOrFullDisplayName = contact.customOrFullDisplayName
            self.discussionNotificationSound = discussionKind.localConfiguration.notificationSound
            self.isEphemeralPersistedMessageSentWithLimitedVisibility = messageSent.isEphemeralMessageWithLimitedVisibility
            self.messageTextBody = messageSent.textBody
            self.receivedMessageIntentInfos = ReceivedMessageIntentInfos(contact: contact, discussionKind: discussionKind, urlForStoringPNGThumbnail: urlForStoringPNGThumbnail)
        }
        
    }
    
    static func createReactionNotification(infos: ReactionNotificationInfos,
                                           emoji: String,
                                           reactionTimestamp: Date) ->
    (notificationId: ObvUserNotificationIdentifier, notificationContent: UNNotificationContent) {

        let hideNotificationContent = ObvMessengerSettings.Privacy.hideNotificationContent

        // Configure the minimal notification content
        var (notificationId, notificationContent) = createMinimalNotification(badge: nil)

        var sendMessageIntent: INSendMessageIntent?

        switch hideNotificationContent {
        case .no:

            if infos.isEphemeralPersistedMessageSentWithLimitedVisibility {
                notificationId = .newReactionNotificationWithHiddenContent
                notificationContent.body = String.localizedStringWithFormat(NSLocalizedString("MESSAGE_REACTION_NOTIFICATION_%@", comment: ""), emoji)
            } else if let textBody = infos.messageTextBody {
                notificationId = .newReaction(messagePermanentID: infos.messagePermanentID, contactPermanentId: infos.contactPermanentID)
                notificationContent.body = String.localizedStringWithFormat(NSLocalizedString("MESSAGE_REACTION_NOTIFICATION_%@_%@", comment: ""), emoji, textBody)
            } else {
                notificationId = .newReactionNotificationWithHiddenContent
                notificationContent.body = String.localizedStringWithFormat(NSLocalizedString("MESSAGE_REACTION_NOTIFICATION_%@", comment: ""), emoji)
            }

            sendMessageIntent = IntentManager.getSendMessageIntentForMessageReceived(infos: infos.receivedMessageIntentInfos, showGroupName: false)

            let deepLink = ObvDeepLink.message(ownedCryptoId: infos.ownedCryptoId, objectPermanentID: infos.messagePermanentID.downcast)
            notificationContent.userInfo[UserNotificationKeys.deepLinkDescription] = deepLink.description
            notificationContent.userInfo[UserNotificationKeys.reactionTimestamp] = reactionTimestamp
            notificationContent.userInfo[UserNotificationKeys.reactionIdentifierForNotification] = notificationId.getIdentifier()
            notificationContent.userInfo[UserNotificationKeys.persistedDiscussionPermanentIDDescription] = infos.discussionPermanentID.description

            setNotificationSound(discussionNotificationSound: infos.discussionNotificationSound, notificationContent: notificationContent)

        case .partially:
            notificationId = .newReactionNotificationWithHiddenContent

            notificationContent.title = Strings.NewPersistedReactionReceivedHiddenContent.title
            notificationContent.subtitle = ""
            notificationContent.body = Strings.NewPersistedReactionReceivedHiddenContent.body

            let deepLink = ObvDeepLink.message(ownedCryptoId: infos.ownedCryptoId, objectPermanentID: infos.messagePermanentID.downcast)
            notificationContent.userInfo[UserNotificationKeys.deepLinkDescription] = deepLink.description
            notificationContent.userInfo[UserNotificationKeys.reactionIdentifierForNotification] = notificationId.getIdentifier()

        case .completely:

            // In that case, we keep the "minimal" notification content created earlier.
            break
        }

        setThreadAndCategory(notificationId: notificationId, notificationContent: notificationContent)

        if let sendMessageIntent = sendMessageIntent,
           let updatedNotificationContent = try? notificationContent.updating(from: sendMessageIntent) {
            return (notificationId, updatedNotificationContent)
        } else {
            return (notificationId, notificationContent)
        }
    }
    
    private static func setThreadAndCategory(notificationId: ObvUserNotificationIdentifier, notificationContent: UNMutableNotificationContent) {
        let hideNotificationContent = ObvMessengerSettings.Privacy.hideNotificationContent

        notificationContent.threadIdentifier = notificationId.getThreadIdentifier()
        // We only set a category if the user does not hide the notification content:
        // Since we use categories to provide interaction within the notification (like accepting or rejectecting an invitation), it would make no sense if the notification does not display any content.
        if let category = notificationId.getCategory(), hideNotificationContent == .no {
            notificationContent.categoryIdentifier = category.identifier
        }
        notificationContent.userInfo[UserNotificationKeys.id] = notificationId.id.rawValue
    }

    
    private static func setNotificationSound(discussionNotificationSound: NotificationSound?, notificationContent: UNMutableNotificationContent) {
        if let notificationSound = discussionNotificationSound ?? ObvMessengerSettings.Discussions.notificationSound {
            switch notificationSound {
            case .none:
                notificationContent.sound = nil
            case .system:
                break
            default:
                guard let filename = notificationSound.filename else {
                    assertionFailure(); break
                }
                if notificationSound.isPolyphonic {
                    let note = Note.generateNote(from: notificationContent.body)
                    notificationContent.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: filename + note.index + ".caf"))
                } else {
                    notificationContent.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: filename))
                }
            }
        }
    }

    
    private static func setNotificationAttachments(location: String, attachementImages: [NotificationAttachmentImage]?, notificationContent: UNMutableNotificationContent) {
        
        guard let attachementImages = attachementImages else { return }
        var notificationAttachments = [UNNotificationAttachment]()
        for attachementImage in attachementImages {
            let url = getNotificationAttachmentURL(location: location,
                                                   quality: attachementImage.quality,
                                                   attachmentNumber: attachementImage.attachmentNumber)
            guard let dataOrURL = attachementImage.dataOrURL else {
                os_log("Cannot compute downsized image data or url", log: Self.log, type: .fault)
                assertionFailure(); continue
            }
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
                guard !FileManager.default.fileExists(atPath: url.path) else {
                    continue
                }
                switch dataOrURL {
                case .data(let data):
                    try data.write(to: url)
                case .url(let fyleUrl):
                    let data = try Data(contentsOf: fyleUrl)
                    guard let image = UIImage(data: data) else {
                        os_log("Cannot compute downsized image data or url", log: Self.log, type: .fault)
                        assertionFailure(); continue
                    }
                    let resizedImage = image.resize(with: max(UIScreen.main.bounds.size.height, UIScreen.main.bounds.size.width))
                    guard let newData = resizedImage?.jpegData(compressionQuality: 0.75) else {
                        os_log("Cannot compute downsized image data or url", log: Self.log, type: .fault)
                        assertionFailure(); continue
                    }
                    try newData.write(to: url)
                }
                notificationAttachments += [try UNNotificationAttachment(identifier: "", url: url)]
            } catch(let error) {
                os_log("Cannot build notification attachments: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                assertionFailure(); continue
            }
        }
        notificationContent.attachments = notificationAttachments

    }

    
    private static func getNotificationAttachmentURL(location: String, quality: String, attachmentNumber: Int) -> URL {
        var url = ObvUICoreDataConstants.ContainerURL.forNotificationAttachments.url
        url.appendPathComponent(location)
        url.appendPathComponent(quality)
        url.appendPathComponent(String(attachmentNumber))
        url.appendPathExtension(for: .jpeg)
        return url
    }

}
