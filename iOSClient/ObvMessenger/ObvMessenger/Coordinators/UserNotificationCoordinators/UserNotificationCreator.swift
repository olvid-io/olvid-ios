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

import Foundation
import UserNotifications
import CoreData
import ObvEngine
import Intents
import os.log

struct UserNotificationCreator {

    private static let thumbnailPhotoSide = CGFloat(300)
    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: UserNotificationCreator.self))


    static func createMissedCallNotification(callUUID: UUID, contact: PersistedObvContactIdentity, discussion: PersistedDiscussion, urlForStoringPNGThumbnail: URL?, badge: NSNumber? = nil) -> (notificationId: ObvUserNotificationIdentifier, notificationContent: UNNotificationContent) {

        let hideNotificationContent = ObvMessengerSettings.Privacy.hideNotificationContent

        // Configure the notification content
        
        let notificationContent = UNMutableNotificationContent()
        notificationContent.badge = badge
        notificationContent.sound = UNNotificationSound.default

        let notificationId = ObvUserNotificationIdentifier.missedCall(callUUID: callUUID)

        var incomingMessageIntent: INSendMessageIntent?

        switch hideNotificationContent {

        case .no:
            
            notificationContent.title = contact.customOrFullDisplayName
            notificationContent.body = Strings.MissedCall.title

            let deepLink = ObvDeepLink.singleDiscussion(discussionObjectURI: discussion.objectID.uriRepresentation())
            notificationContent.userInfo["deepLink"] = deepLink.url.absoluteString
            notificationContent.userInfo["persistedDiscussionObjectURI"] = discussion.objectID.uriRepresentation().absoluteString
            notificationContent.userInfo["callUUID"] = callUUID.uuidString
            notificationContent.userInfo["messageIdentifierForNotification"] = notificationId.getIdentifier()

            if #available(iOS 15.0, *) {
                incomingMessageIntent = buildSendMessageIntent(notificationContent: notificationContent, contact: contact, discussion: discussion, urlForStoringPNGThumbnail: nil)
            }
            
        case .partially:

            notificationContent.body = Strings.MissedCall.title
            let deepLink = ObvDeepLink.singleDiscussion(discussionObjectURI: discussion.objectID.uriRepresentation())
            notificationContent.userInfo["deepLink"] = deepLink.url.absoluteString
            notificationContent.userInfo["persistedDiscussionObjectURI"] = discussion.objectID.uriRepresentation().absoluteString
            notificationContent.userInfo["callUUID"] = callUUID.uuidString
            notificationContent.userInfo["messageIdentifierForNotification"] = notificationId.getIdentifier()

        case .completely:

            notificationContent.title = Strings.NewPersistedMessageReceivedMinimal.title
            notificationContent.subtitle = ""
            notificationContent.body = Strings.NewPersistedMessageReceivedMinimal.body
            
            let deepLink = ObvDeepLink.latestDiscussions
            notificationContent.userInfo["deepLink"] = deepLink.url.absoluteString
        }
        
        setThreadAndCategory(notificationId: notificationId, notificationContent: notificationContent, hideNotificationContent: hideNotificationContent)

        if #available(iOS 15.0, *),
           let incomingMessageIntent = incomingMessageIntent,
           let updatedNotificationContent = try? notificationContent.updating(from: incomingMessageIntent) {
            return (notificationId, updatedNotificationContent)
        } else {
            return (notificationId, notificationContent)
        }
    }
    
    static func createNewMessageNotification(body: String?,
                                             messageIdentifierFromEngine: Data,
                                             contact: PersistedObvContactIdentity,
                                             attachmentsFileNames: [String],
                                             discussion: PersistedDiscussion,
                                             urlForStoringPNGThumbnail: URL?,
                                             badge: NSNumber? = nil) ->
    (notificationId: ObvUserNotificationIdentifier, notificationContent: UNNotificationContent) {
                
        let hideNotificationContent = ObvMessengerSettings.Privacy.hideNotificationContent

        // Configure the notification content
        let notificationContent = UNMutableNotificationContent()
        notificationContent.badge = badge
        notificationContent.sound = UNNotificationSound.default

        let notificationId: ObvUserNotificationIdentifier

        var incomingMessageIntent: INSendMessageIntent?

        switch hideNotificationContent {
            
        case .no:

            notificationId = ObvUserNotificationIdentifier.newMessage(messageIdentifierFromEngine: messageIdentifierFromEngine)
            
            notificationContent.title = Strings.NewPersistedMessageReceived.title(contact.customOrFullDisplayName)
            if discussion is PersistedGroupDiscussion {
                notificationContent.subtitle = discussion.title
            }
            if body == nil || body!.isEmpty {
                if attachmentsFileNames.count == 1 {
                    notificationContent.body = "\(attachmentsFileNames.first!)"
                } else if attachmentsFileNames.count > 1 {
                    notificationContent.body = Strings.NewPersistedMessageReceived.body(attachmentsFileNames.first!, attachmentsFileNames.count-1)
                }
            } else {
                let body = body!
                if attachmentsFileNames.count == 1 {
                    notificationContent.body = [body, "\(attachmentsFileNames.first!)"].joined(separator: "\n")
                } else if attachmentsFileNames.count > 1 {
                    notificationContent.body = [body, Strings.NewPersistedMessageReceived.body(attachmentsFileNames.first!, attachmentsFileNames.count-1)].joined(separator: "\n")
                } else {
                    notificationContent.body = "\(body)"
                }
            }

            let deepLink = ObvDeepLink.singleDiscussion(discussionObjectURI: discussion.typedObjectID.uriRepresentation().url)
            notificationContent.userInfo["deepLink"] = deepLink.url.absoluteString
            notificationContent.userInfo["persistedDiscussionObjectURI"] = discussion.typedObjectID.uriRepresentation().absoluteString
            notificationContent.userInfo["messageIdentifierForNotification"] = notificationId.getIdentifier()

            if #available(iOS 15.0, *) {
                incomingMessageIntent = buildSendMessageIntent(notificationContent: notificationContent, contact: contact, discussion: discussion, urlForStoringPNGThumbnail: urlForStoringPNGThumbnail)
            }

        case .partially:

            notificationId = ObvUserNotificationIdentifier.newMessageNotificationWithHiddenContent
            
            notificationContent.title = Strings.NewPersistedMessageReceivedHiddenContent.title
            notificationContent.subtitle = ""
            notificationContent.body = Strings.NewPersistedMessageReceivedHiddenContent.body

            let deepLink = ObvDeepLink.singleDiscussion(discussionObjectURI: discussion.typedObjectID.uriRepresentation().url)
            notificationContent.userInfo["deepLink"] = deepLink.url.absoluteString
            notificationContent.userInfo["persistedDiscussionObjectURI"] = discussion.typedObjectID.uriRepresentation().absoluteString
            notificationContent.userInfo["messageIdentifierForNotification"] = notificationId.getIdentifier()

        case .completely:

            notificationId = ObvUserNotificationIdentifier.staticIdentifier
            
            notificationContent.title = Strings.NewPersistedMessageReceivedMinimal.title
            notificationContent.subtitle = ""
            notificationContent.body = Strings.NewPersistedMessageReceivedMinimal.body
            
            let deepLink = ObvDeepLink.latestDiscussions
            notificationContent.userInfo["deepLink"] = deepLink.url.absoluteString

        }
        
        setThreadAndCategory(notificationId: notificationId, notificationContent: notificationContent, hideNotificationContent: hideNotificationContent)

        if #available(iOS 15.0, *),
           let incomingMessageIntent = incomingMessageIntent,
           let updatedNotificationContent = try? notificationContent.updating(from: incomingMessageIntent) {
            return (notificationId, updatedNotificationContent)
        } else {
            return (notificationId, notificationContent)
        }
    }

    @available(iOS 15.0, *)
    static func buildSendMessageIntent(notificationContent: UNNotificationContent,
                                       contact: PersistedObvContactIdentity,
                                       discussion: PersistedDiscussion,
                                       urlForStoringPNGThumbnail: URL?) -> INSendMessageIntent? {
        guard let ownedIdentity = contact.ownedIdentity else { return nil }
        var recipients = [ownedIdentity.createINPerson(storingPNGPhotoThumbnailAtURL: urlForStoringPNGThumbnail, thumbnailSide: thumbnailPhotoSide)]
        var speakableGroupName: INSpeakableString?
        if let groupDiscussion = discussion as? PersistedGroupDiscussion {
            if let contactIdentities = groupDiscussion.contactGroup?.contactIdentities {
                for contact in contactIdentities {
                    recipients += [contact.createINPerson(storingPNGPhotoThumbnailAtURL: urlForStoringPNGThumbnail, thumbnailSide: thumbnailPhotoSide)]
                }
                speakableGroupName = INSpeakableString(spokenPhrase: groupDiscussion.title)
            }
        }

        let person = contact.createINPerson(storingPNGPhotoThumbnailAtURL: urlForStoringPNGThumbnail, thumbnailSide: thumbnailPhotoSide)
        let intent = INSendMessageIntent(
            recipients: recipients,
            outgoingMessageType: .outgoingMessageText,
            content: notificationContent.body,
            speakableGroupName: speakableGroupName,
            conversationIdentifier: discussion.objectID.uriRepresentation().absoluteString,
            serviceName: nil,
            sender: person,
            attachments: nil)
        if let contactGroup = (discussion as? PersistedGroupDiscussion)?.contactGroup {
            intent.setImage(contactGroup.createINImage(storingPNGPhotoThumbnailAtURL: urlForStoringPNGThumbnail, thumbnailSide: thumbnailPhotoSide), forParameterNamed: \.speakableGroupName)
        }
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        interaction.donate { (error) in
            guard let error = error else {
                os_log("Successfully donated interaction", log: Self.log, type: .info)
                return
            }
            os_log("Interaction donation failed: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
        }
        return intent
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
            case .autoconfirmedContactIntroduction(contactIdentity: let contactIdentity, mediatorIdentity: let mediatorIdentity):
                let contactDisplayName = contactIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full)
                let mediatorDisplayName = mediatorIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full)
                notificationContent.title = Strings.AutoconfirmedContactIntroduction.title
                notificationContent.body = Strings.AutoconfirmedContactIntroduction.body(mediatorDisplayName, contactDisplayName)
            case .increaseMediatorTrustLevelRequired(contactIdentity: let contactIdentity, mediatorIdentity: let mediatorIdentity):
                let contactDisplayName = contactIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full)
                let mediatorDisplayName = mediatorIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full)
                notificationContent.title = Strings.IncreaseMediatorTrustLevelRequired.title
                notificationContent.body = Strings.IncreaseMediatorTrustLevelRequired.body(mediatorDisplayName, contactDisplayName)
            case .inviteSent,
                 .invitationAccepted,
                 .sasConfirmed,
                 .mediatorInviteAccepted,
                 .groupJoined,
                 .increaseGroupOwnerTrustLevelRequired:
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
            let deepLink = ObvDeepLink.invitations
            notificationContent.userInfo["deepLink"] = deepLink.url.absoluteString
            
            switch obvDialog.category {
            case .acceptInvite(contactIdentity: _):
                notificationId = ObvUserNotificationIdentifier.acceptInvite(persistedInvitationUUID: persistedInvitationUUID)
                notificationContent.userInfo["persistedInvitationUUID"] = persistedInvitationUUID.uuidString
            case .sasExchange(contactIdentity: _, sasToDisplay: _, numberOfBadEnteredSas: let numberOfBadEnteredSas):
                guard numberOfBadEnteredSas == 0 else { return nil } // Do not show any notification when the user enters a bad SAS
                notificationId = ObvUserNotificationIdentifier.sasExchange(persistedInvitationUUID: persistedInvitationUUID)
            case .mutualTrustConfirmed(contactIdentity: _):
                notificationId = ObvUserNotificationIdentifier.mutualTrustConfirmed(persistedInvitationUUID: persistedInvitationUUID)
            case .acceptMediatorInvite(contactIdentity: _, mediatorIdentity: _):
                notificationId = ObvUserNotificationIdentifier.acceptMediatorInvite(persistedInvitationUUID: persistedInvitationUUID)
                notificationContent.userInfo["persistedInvitationUUID"] = persistedInvitationUUID.uuidString
            case .acceptGroupInvite(groupMembers: _, groupOwner: _):
                notificationId = ObvUserNotificationIdentifier.acceptGroupInvite(persistedInvitationUUID: persistedInvitationUUID)
                notificationContent.userInfo["persistedInvitationUUID"] = persistedInvitationUUID.uuidString
            case .autoconfirmedContactIntroduction(contactIdentity: _, mediatorIdentity: _):
                notificationId = ObvUserNotificationIdentifier.autoconfirmedContactIntroduction(persistedInvitationUUID: persistedInvitationUUID)
            case .increaseMediatorTrustLevelRequired(contactIdentity: _, mediatorIdentity: _):
                notificationId = ObvUserNotificationIdentifier.increaseMediatorTrustLevelRequired(persistedInvitationUUID: persistedInvitationUUID)
            case .inviteSent,
                 .invitationAccepted,
                 .sasConfirmed,
                 .mediatorInviteAccepted,
                 .groupJoined,
                 .increaseGroupOwnerTrustLevelRequired:
                // For now, we do not notify when receiving these dialogs
                return nil
            }
            
        case .completely:
            
            notificationId = ObvUserNotificationIdentifier.staticIdentifier
            
            // Even for an invitation, we navigate to the list of latest discussions
            let deepLink = ObvDeepLink.latestDiscussions
            notificationContent.userInfo["deepLink"] = deepLink.url.absoluteString

        }
        
        setThreadAndCategory(notificationId: notificationId, notificationContent: notificationContent, hideNotificationContent: hideNotificationContent)
        
        return (notificationId, notificationContent)

    }

    static func createRequestRecordPermissionNotification() -> (notificationId: ObvUserNotificationIdentifier, notificationContent: UNNotificationContent) {

        let notificationContent = UNMutableNotificationContent()
        notificationContent.sound = UNNotificationSound.default

        notificationContent.title = NSLocalizedString("REJECTED_INCOMING_CALL", comment: "")
        notificationContent.body = NSLocalizedString("REJECTED_INCOMING_CALL_BECAUSE_RECORD_PERMISSION_IS_UNDETERMINED_NOTIFICATION_BODY", comment: "")

        let deepLink = ObvDeepLink.requestRecordPermission
        notificationContent.userInfo["deepLink"] = deepLink.url.absoluteString

        let notificationId = ObvUserNotificationIdentifier.staticIdentifier

        return (notificationId, notificationContent)
    }

    static func createDeniedRecordPermissionNotification() -> (notificationId: ObvUserNotificationIdentifier, notificationContent: UNNotificationContent) {

        let notificationContent = UNMutableNotificationContent()
        notificationContent.sound = UNNotificationSound.default

        notificationContent.title = NSLocalizedString("REJECTED_INCOMING_CALL", comment: "")
        notificationContent.body = NSLocalizedString("REJECTED_INCOMING_CALL_BECAUSE_RECORD_PERMISSION_IS_DENIED_NOTIFICATION_BODY", comment: "")

        let deepLink = ObvDeepLink.requestRecordPermission
        notificationContent.userInfo["deepLink"] = deepLink.url.absoluteString

        let notificationId = ObvUserNotificationIdentifier.staticIdentifier

        return (notificationId, notificationContent)
    }

    private static func setThreadAndCategory(notificationId: ObvUserNotificationIdentifier, notificationContent: UNMutableNotificationContent, hideNotificationContent: ObvMessengerSettings.Privacy.HideNotificationContentType) {
        notificationContent.threadIdentifier = notificationId.getThreadIdentifier()
        // We only set a category if the user does not hide the notification content:
        // Since we use categories to provide interaction within the notification (like accepting or rejectecting an invitation), it would make no sense if the notification does not display any content.
        if let category = notificationId.getCategory(), hideNotificationContent == .no {
            notificationContent.categoryIdentifier = category.getIdentifier()
        }
    }
    
}
