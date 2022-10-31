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

struct UserNotificationKeys {
    static let id = "id"
    static let deepLink = "deepLink"
    static let persistedDiscussionObjectURI = "persistedDiscussionObjectURI"
    static let persistedContactObjectURI = "persistedContactObjectURI"
    static let reactionTimestamp = "reactionTimestamp"
    static let callUUID = "callUUID"
    static let messageIdentifierForNotification = "messageIdentifierForNotification"
    static let persistedInvitationUUID = "persistedInvitationUUID"
    static let messageIdentifierFromEngine = "messageIdentifierFromEngine"
    static let reactionIdentifierForNotification = "reactionIdentifierForNotification"
}

struct UserNotificationCreator {

    private static let thumbnailPhotoSide = CGFloat(300)
    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: UserNotificationCreator.self))

    struct MissedCallNotificationInfos {
        let contactCustomOrFullDisplayName: String
        let discussionObjectID: NSManagedObjectID
        let sendMessageIntentInfos: SendMessageIntentInfos? // Only used for iOS15+
        let discussionNotificationSound: NotificationSound?
        
        init(contact: PersistedObvContactIdentity.Structure, discussionKind: PersistedDiscussion.StructureKind, urlForStoringPNGThumbnail: URL?) {
            self.contactCustomOrFullDisplayName = contact.customOrFullDisplayName
            self.discussionObjectID = discussionKind.objectID
            if #available(iOS 15.0, *) {
                sendMessageIntentInfos = SendMessageIntentInfos.init(contact: contact, discussionKind: discussionKind, urlForStoringPNGThumbnail: urlForStoringPNGThumbnail)
            } else {
                sendMessageIntentInfos = nil
            }
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

            let deepLink = ObvDeepLink.singleDiscussion(discussionObjectURI: infos.discussionObjectID.uriRepresentation())
            notificationContent.userInfo[UserNotificationKeys.deepLink] = deepLink.url.absoluteString
            notificationContent.userInfo[UserNotificationKeys.persistedDiscussionObjectURI] = infos.discussionObjectID.uriRepresentation().absoluteString
            notificationContent.userInfo[UserNotificationKeys.callUUID] = callUUID.uuidString

            if #available(iOS 15.0, *) {
                if let sendMessageIntentInfos = infos.sendMessageIntentInfos {
                    sendMessageIntent = buildSendMessageIntent(notificationContent: notificationContent,
                                                               infos: sendMessageIntentInfos,
                                                               showGroupName: true)
                }
            }

            setNotificationSound(discussionNotificationSound: infos.discussionNotificationSound, notificationContent: notificationContent)
            
        case .partially:

            notificationContent.body = Strings.MissedCall.title
            let deepLink = ObvDeepLink.singleDiscussion(discussionObjectURI: infos.discussionObjectID.uriRepresentation())
            notificationContent.userInfo[UserNotificationKeys.deepLink] = deepLink.url.absoluteString
            notificationContent.userInfo[UserNotificationKeys.persistedDiscussionObjectURI] = infos.discussionObjectID.uriRepresentation().absoluteString
            notificationContent.userInfo[UserNotificationKeys.callUUID] = callUUID.uuidString

        case .completely:

            notificationContent.title = Strings.NewPersistedMessageReceivedMinimal.title
            notificationContent.subtitle = ""
            notificationContent.body = Strings.NewPersistedMessageReceivedMinimal.body
            
            let deepLink = ObvDeepLink.latestDiscussions
            notificationContent.userInfo[UserNotificationKeys.deepLink] = deepLink.url.absoluteString
        }

        setThreadAndCategory(notificationId: notificationId, notificationContent: notificationContent)

        if #available(iOS 15.0, *),
           let sendMessageIntent = sendMessageIntent,
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
        
        let deepLink = ObvDeepLink.latestDiscussions
        notificationContent.userInfo[UserNotificationKeys.deepLink] = deepLink.url.absoluteString

        setThreadAndCategory(notificationId: notificationId, notificationContent: notificationContent)

        return (notificationId, notificationContent)

    }
    
    
    struct NewMessageNotificationInfos {
        
        let body: String
        let messageIdentifierFromEngine: Data
        let contactObjectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>
        let discussionObjectID: NSManagedObjectID
        let contactCustomOrFullDisplayName: String
        let groupDiscussionTitle: String?
        let discussionNotificationSound: NotificationSound?
        let isEphemeralMessageWithUserAction: Bool
        let sendMessageIntentInfos: SendMessageIntentInfos? // Only used for iOS15+

        init(messageReceived: PersistedMessageReceived.Structure, urlForStoringPNGThumbnail: URL?) {
            self.body = messageReceived.textBody ?? ""
            self.messageIdentifierFromEngine = messageReceived.messageIdentifierFromEngine
            self.contactObjectID = messageReceived.contact.typedObjectID
            self.discussionObjectID = messageReceived.discussionKind.objectID
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
            if #available(iOS 15.0, *) {
                sendMessageIntentInfos = SendMessageIntentInfos(messageReceived: messageReceived, urlForStoringPNGThumbnail: urlForStoringPNGThumbnail)
            } else {
                sendMessageIntentInfos = nil
            }
        }
        
        init(body: String, messageIdentifierFromEngine: Data, contact: PersistedObvContactIdentity.Structure, discussionKind: PersistedDiscussion.StructureKind, isEphemeralMessageWithUserAction: Bool, urlForStoringPNGThumbnail: URL?) async {
            self.body = body
            self.messageIdentifierFromEngine = messageIdentifierFromEngine
            self.contactObjectID = contact.typedObjectID
            self.discussionObjectID = discussionKind.objectID
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
            if #available(iOS 15.0, *) {
                self.sendMessageIntentInfos = SendMessageIntentInfos(contact: contact, discussionKind: discussionKind, urlForStoringPNGThumbnail: urlForStoringPNGThumbnail)
            } else {
                self.sendMessageIntentInfos = nil
            }
        }

    }
    
    
    /// This static method creates a new message notification.
    static func createNewMessageNotification(infos: NewMessageNotificationInfos,
                                             attachmentsFileNames: [String],
                                             badge: NSNumber? = nil) ->
    (notificationId: ObvUserNotificationIdentifier, notificationContent: UNNotificationContent) {
                
        let hideNotificationContent = ObvMessengerSettings.Privacy.hideNotificationContent

        // Configure the minimal notification content
        var (notificationId, notificationContent) = createMinimalNotification(badge: badge)
        
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
                if attachmentsFileNames.count == 1 {
                    notificationContent.body = "\(attachmentsFileNames.first!)"
                } else if attachmentsFileNames.count > 1 {
                    notificationContent.body = Strings.NewPersistedMessageReceived.body(attachmentsFileNames.first!, attachmentsFileNames.count-1)
                }
            } else {
                let body = infos.body
                if attachmentsFileNames.count == 1 {
                    notificationContent.body = [body, "\(attachmentsFileNames.first!)"].joined(separator: "\n")
                } else if attachmentsFileNames.count > 1 {
                    notificationContent.body = [body, Strings.NewPersistedMessageReceived.body(attachmentsFileNames.first!, attachmentsFileNames.count-1)].joined(separator: "\n")
                } else {
                    notificationContent.body = "\(body)"
                }
            }

            let deepLink = ObvDeepLink.singleDiscussion(discussionObjectURI: infos.discussionObjectID.uriRepresentation())
            notificationContent.userInfo[UserNotificationKeys.deepLink] = deepLink.url.absoluteString
            notificationContent.userInfo[UserNotificationKeys.persistedDiscussionObjectURI] = infos.discussionObjectID.uriRepresentation().absoluteString
            notificationContent.userInfo[UserNotificationKeys.messageIdentifierForNotification] = notificationId.getIdentifier()
            notificationContent.userInfo[UserNotificationKeys.persistedContactObjectURI] = infos.contactObjectID.uriRepresentation().absoluteString
            notificationContent.userInfo[UserNotificationKeys.messageIdentifierFromEngine] = infos.messageIdentifierFromEngine.hexString()

            if #available(iOS 15.0, *) {
                if let sendMessageIntentInfos = infos.sendMessageIntentInfos {
                    incomingMessageIntent = buildSendMessageIntent(notificationContent: notificationContent,
                                                                   infos: sendMessageIntentInfos,
                                                                   showGroupName: true)
                }
            }

            setNotificationSound(discussionNotificationSound: infos.discussionNotificationSound, notificationContent: notificationContent)

        case .partially:

            notificationId = ObvUserNotificationIdentifier.newMessageNotificationWithHiddenContent
            
            notificationContent.title = Strings.NewPersistedMessageReceivedHiddenContent.title
            notificationContent.subtitle = ""
            notificationContent.body = Strings.NewPersistedMessageReceivedHiddenContent.body

            let deepLink = ObvDeepLink.singleDiscussion(discussionObjectURI: infos.discussionObjectID.uriRepresentation())
            notificationContent.userInfo[UserNotificationKeys.deepLink] = deepLink.url.absoluteString
            notificationContent.userInfo[UserNotificationKeys.persistedDiscussionObjectURI] = infos.discussionObjectID.uriRepresentation().absoluteString
            notificationContent.userInfo[UserNotificationKeys.messageIdentifierForNotification] = notificationId.getIdentifier()

        case .completely:
            
            // In that case, we keep the "minimal" notification content created earlier.
            break
            
        }
        
        setThreadAndCategory(notificationId: notificationId, notificationContent: notificationContent)

        if #available(iOS 15.0, *),
           let incomingMessageIntent = incomingMessageIntent,
           let updatedNotificationContent = try? notificationContent.updating(from: incomingMessageIntent) {
            return (notificationId, updatedNotificationContent)
        } else {
            return (notificationId, notificationContent)
        }
    }
    
    
    struct SendMessageIntentInfos {
        
        let discussionObjectID: NSManagedObjectID
        let ownedINPerson: INPerson
        let contactINPerson: INPerson
        let groupInfos: GroupInfos? // Only set in the case of a group discussion
        
        @available(iOS 15.0, *)
        init?(messageReceived: PersistedMessageReceived.Structure, urlForStoringPNGThumbnail: URL?) {
            let contact = messageReceived.contact
            let discussionKind = messageReceived.discussionKind
            self.init(contact: contact, discussionKind: discussionKind, urlForStoringPNGThumbnail: urlForStoringPNGThumbnail)
        }
        
        @available(iOS 15.0, *)
        init(contact: PersistedObvContactIdentity.Structure, discussionKind: PersistedDiscussion.StructureKind, urlForStoringPNGThumbnail: URL?) {
            let ownedIdentity = contact.ownedIdentity
            self.discussionObjectID = discussionKind.objectID
            self.ownedINPerson = ownedIdentity.createINPerson(storingPNGPhotoThumbnailAtURL: urlForStoringPNGThumbnail,
                                                                    thumbnailSide: thumbnailPhotoSide)
            self.contactINPerson = contact.createINPerson(storingPNGPhotoThumbnailAtURL: urlForStoringPNGThumbnail,
                                                                thumbnailSide: thumbnailPhotoSide)
            switch discussionKind {
            case .groupDiscussion(structure: let structure):
                self.groupInfos = GroupInfos(groupDiscussion: structure,
                                             urlForStoringPNGThumbnail: urlForStoringPNGThumbnail)
            case .groupV2Discussion(structure: let structure):
                self.groupInfos = GroupInfos(groupDiscussion: structure,
                                             urlForStoringPNGThumbnail: urlForStoringPNGThumbnail)
            case .oneToOneDiscussion:
                self.groupInfos = nil
            }
        }
        
        struct GroupInfos {
            
            let groupRecipients: [INPerson]
            let speakableGroupName: INSpeakableString
            let groupINImage: INImage?
            
            @available(iOS 15.0, *)
            init(groupDiscussion: PersistedGroupDiscussion.Structure, urlForStoringPNGThumbnail: URL?) {
                let contactGroup = groupDiscussion.contactGroup
                let contactIdentities = contactGroup.contactIdentities
                var groupRecipients = [INPerson]()
                for contactIdentity in contactIdentities {
                    let inPerson = contactIdentity.createINPerson(storingPNGPhotoThumbnailAtURL: urlForStoringPNGThumbnail, thumbnailSide: thumbnailPhotoSide)
                    groupRecipients.append(inPerson)
                }
                self.groupRecipients = groupRecipients
                speakableGroupName = INSpeakableString(spokenPhrase: groupDiscussion.title)
                self.groupINImage = contactGroup.createINImage(storingPNGPhotoThumbnailAtURL: urlForStoringPNGThumbnail,
                                                               thumbnailSide: thumbnailPhotoSide)
            }
            
            @available(iOS 15.0, *)
            init(groupDiscussion: PersistedGroupV2Discussion.Structure, urlForStoringPNGThumbnail: URL?) {
                let group = groupDiscussion.group
                let contactIdentities = group.contactIdentities
                var groupRecipients = [INPerson]()
                for contactIdentity in contactIdentities {
                    let inPerson = contactIdentity.createINPerson(storingPNGPhotoThumbnailAtURL: urlForStoringPNGThumbnail, thumbnailSide: thumbnailPhotoSide)
                    groupRecipients.append(inPerson)
                }
                self.groupRecipients = groupRecipients
                speakableGroupName = INSpeakableString(spokenPhrase: groupDiscussion.title)
                self.groupINImage = group.createINImage(storingPNGPhotoThumbnailAtURL: urlForStoringPNGThumbnail,
                                                        thumbnailSide: thumbnailPhotoSide)
            }

        }

    }

    @available(iOS 15.0, *)
    private static func buildSendMessageIntent(notificationContent: UNNotificationContent,
                                               infos: SendMessageIntentInfos,
                                               showGroupName: Bool) -> INSendMessageIntent? {
        var recipients = [infos.ownedINPerson]
        var speakableGroupName: INSpeakableString?
        if let groupInfos = infos.groupInfos, showGroupName {
            speakableGroupName = groupInfos.speakableGroupName
            recipients += groupInfos.groupRecipients
        }
        let intent = INSendMessageIntent(
            recipients: recipients,
            outgoingMessageType: .outgoingMessageText,
            content: notificationContent.body,
            speakableGroupName: speakableGroupName,
            conversationIdentifier: infos.discussionObjectID.uriRepresentation().absoluteString,
            serviceName: nil,
            sender: infos.contactINPerson,
            attachments: nil)
        if let groupInfos = infos.groupInfos {
            intent.setImage(groupInfos.groupINImage, forParameterNamed: \.speakableGroupName)
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
                 .increaseGroupOwnerTrustLevelRequired,
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
            let deepLink = ObvDeepLink.invitations
            notificationContent.userInfo[UserNotificationKeys.deepLink] = deepLink.url.absoluteString
            
            switch obvDialog.category {
            case .acceptInvite(contactIdentity: _):
                notificationId = ObvUserNotificationIdentifier.acceptInvite(persistedInvitationUUID: persistedInvitationUUID)
                notificationContent.userInfo[UserNotificationKeys.persistedInvitationUUID] = persistedInvitationUUID.uuidString
            case .sasExchange(contactIdentity: _, sasToDisplay: _, numberOfBadEnteredSas: let numberOfBadEnteredSas):
                guard numberOfBadEnteredSas == 0 else { return nil } // Do not show any notification when the user enters a bad SAS
                notificationId = ObvUserNotificationIdentifier.sasExchange(persistedInvitationUUID: persistedInvitationUUID)
            case .mutualTrustConfirmed(contactIdentity: _):
                notificationId = ObvUserNotificationIdentifier.mutualTrustConfirmed(persistedInvitationUUID: persistedInvitationUUID)
            case .acceptMediatorInvite(contactIdentity: _, mediatorIdentity: _):
                notificationId = ObvUserNotificationIdentifier.acceptMediatorInvite(persistedInvitationUUID: persistedInvitationUUID)
                notificationContent.userInfo[UserNotificationKeys.persistedInvitationUUID] = persistedInvitationUUID.uuidString
            case .acceptGroupInvite(groupMembers: _, groupOwner: _):
                notificationId = ObvUserNotificationIdentifier.acceptGroupInvite(persistedInvitationUUID: persistedInvitationUUID)
                notificationContent.userInfo[UserNotificationKeys.persistedInvitationUUID] = persistedInvitationUUID.uuidString
            case .autoconfirmedContactIntroduction(contactIdentity: _, mediatorIdentity: _):
                notificationId = ObvUserNotificationIdentifier.autoconfirmedContactIntroduction(persistedInvitationUUID: persistedInvitationUUID)
            case .increaseMediatorTrustLevelRequired(contactIdentity: _, mediatorIdentity: _):
                notificationId = ObvUserNotificationIdentifier.increaseMediatorTrustLevelRequired(persistedInvitationUUID: persistedInvitationUUID)
            case .oneToOneInvitationReceived(contactIdentity: _):
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
                 .increaseGroupOwnerTrustLevelRequired,
                 .freezeGroupV2Invite:
                // For now, we do not notify when receiving these dialogs
                return nil
            }
            
        case .completely:
            
            notificationId = ObvUserNotificationIdentifier.staticIdentifier
            
            // Even for an invitation, we navigate to the list of latest discussions
            let deepLink = ObvDeepLink.latestDiscussions
            notificationContent.userInfo[UserNotificationKeys.deepLink] = deepLink.url.absoluteString

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

        notificationContent.userInfo[UserNotificationKeys.deepLink] = deepLink.url.absoluteString
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
        notificationContent.userInfo[UserNotificationKeys.deepLink] = deepLink.url.absoluteString

        let notificationId = ObvUserNotificationIdentifier.shouldGrantRecordPermissionToReceiveIncomingCalls

        setThreadAndCategory(notificationId: notificationId, notificationContent: notificationContent)

        return (notificationId, notificationContent)
    }


    struct ReactionNotificationInfos {
        
        let messageObjectID: NSManagedObjectID
        let discussionObjectID: NSManagedObjectID
        let contactObjectID: NSManagedObjectID
        let contactCustomOrFullDisplayName: String
        let discussionNotificationSound: NotificationSound?
        let isEphemeralPersistedMessageSentWithLimitedVisibility: Bool
        let messageTextBody: String?
        let sendMessageIntentInfos: SendMessageIntentInfos? // Only used for iOS15+

        init(messageSent: PersistedMessageSent.Structure, contact: PersistedObvContactIdentity.Structure, urlForStoringPNGThumbnail: URL?) {
            let discussionKind = messageSent.discussionKind
            self.messageObjectID = messageSent.typedObjectID.objectID
            self.discussionObjectID = discussionKind.objectID
            self.contactObjectID = contact.typedObjectID.objectID
            self.contactCustomOrFullDisplayName = contact.customOrFullDisplayName
            self.discussionNotificationSound = discussionKind.localConfiguration.notificationSound
            self.isEphemeralPersistedMessageSentWithLimitedVisibility = messageSent.isEphemeralMessageWithLimitedVisibility
            self.messageTextBody = messageSent.textBody
            if #available(iOS 15.0, *) {
                self.sendMessageIntentInfos = SendMessageIntentInfos(contact: contact, discussionKind: discussionKind, urlForStoringPNGThumbnail: urlForStoringPNGThumbnail)
            } else {
                self.sendMessageIntentInfos = nil
            }
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
                notificationId = .newReaction(messageURI: infos.messageObjectID.uriRepresentation(), contactURI: infos.contactObjectID.uriRepresentation())
                notificationContent.body = String.localizedStringWithFormat(NSLocalizedString("MESSAGE_REACTION_NOTIFICATION_%@_%@", comment: ""), emoji, textBody)
            } else {
                notificationId = .newReactionNotificationWithHiddenContent
                notificationContent.body = String.localizedStringWithFormat(NSLocalizedString("MESSAGE_REACTION_NOTIFICATION_%@", comment: ""), emoji)
            }

            if #available(iOS 15.0, *), let sendMessageIntentInfos = infos.sendMessageIntentInfos {
                sendMessageIntent = buildSendMessageIntent(notificationContent: notificationContent,
                                                           infos: sendMessageIntentInfos,
                                                           showGroupName: false)
            } else {
                notificationContent.title = infos.contactCustomOrFullDisplayName
                notificationContent.subtitle = ""
            }

            let deepLink = ObvDeepLink.message(messageObjectURI: infos.messageObjectID.uriRepresentation())
            notificationContent.userInfo[UserNotificationKeys.deepLink] = deepLink.url.absoluteString
            notificationContent.userInfo[UserNotificationKeys.reactionTimestamp] = reactionTimestamp
            notificationContent.userInfo[UserNotificationKeys.reactionIdentifierForNotification] = notificationId.getIdentifier()
            notificationContent.userInfo[UserNotificationKeys.persistedDiscussionObjectURI] = infos.discussionObjectID.uriRepresentation().absoluteString

            setNotificationSound(discussionNotificationSound: infos.discussionNotificationSound, notificationContent: notificationContent)

        case .partially:
            notificationId = .newReactionNotificationWithHiddenContent

            notificationContent.title = Strings.NewPersistedReactionReceivedHiddenContent.title
            notificationContent.subtitle = ""
            notificationContent.body = Strings.NewPersistedReactionReceivedHiddenContent.body

            let deepLink = ObvDeepLink.message(messageObjectURI: infos.messageObjectID.uriRepresentation())
            notificationContent.userInfo[UserNotificationKeys.deepLink] = deepLink.url.absoluteString
            notificationContent.userInfo[UserNotificationKeys.reactionIdentifierForNotification] = notificationId.getIdentifier()

        case .completely:

            // In that case, we keep the "minimal" notification content created earlier.
            break
        }

        setThreadAndCategory(notificationId: notificationId, notificationContent: notificationContent)

        if #available(iOS 15.0, *),
           let sendMessageIntent = sendMessageIntent,
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
    
}
