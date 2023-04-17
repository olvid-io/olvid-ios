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
import CoreData
import Intents
import os.log
import UIKit

protocol IntentDelegate: AnyObject {
    @available(iOS 14.0, *)
    static func getSendMessageIntentForMessageReceived(infos: ReceivedMessageIntentInfos,
                                                       showGroupName: Bool) -> INSendMessageIntent
}


@available(iOS 14.0, *)
final class IntentManager {

    fileprivate static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: UserNotificationCreator.self))

    fileprivate static let thumbnailPhotoSide = CGFloat(300)
    private var observationTokens = [NSObjectProtocol]()

    
    func performPostInitialization() {
        observeMessageInsertionToDonateINSendMessageIntent()
        observeDiscussionDeletionToDeleteAllAssociatedDonations()
        observeDiscussionLockToDeleteAllAssociatedDonations()
        observeDiscussionLocalConfigurationUpdatesToDeleteAllDonationsIfAppropriate()
        observeDiscussionGlobalConfigurationUpdatesToDeleteAllDonationsIfAppropriate()
    }

    
    /// One-stop method called when this manager needs to donate an `INSendMessageIntent` object to the system.
    ///
    /// Systematically using this method allows to make sure that users preferences are always taken into account, i.e., that we only perform donations if the global or discussion local configuration lets us do so.
    private static func makeDonation(discussionKind: PersistedDiscussion.StructureKind,
                                     intent: INSendMessageIntent,
                                     direction: INInteractionDirection) async {

        guard discussionKind.localConfiguration.performInteractionDonation ?? ObvMessengerSettings.Discussions.performInteractionDonation else { return }

        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = direction
        interaction.groupIdentifier = discussionKind.interactionGroupIdentifier
        do {
            try await interaction.donate()
            os_log("🎁 Successfully donated interaction", log: Self.log, type: .info)
        } catch {
            assertionFailure()
            os_log("🎁 Interaction donation failed: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
        }
    }

    
    private static func deleteAllDonations(for url: TypeSafeURL<PersistedDiscussion>) async {
        do {
            try await INInteraction.delete(with: url.interactionGroupIdentifier)
            os_log("🎁 Successfully deleted all interactions", log: Self.log, type: .info)
        } catch {
            assertionFailure()
            os_log("🎁 Interaction deletion failed: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
        }
    }

}

// MARK: - Notifications observation

@available(iOS 14.0, *)
extension IntentManager {

    private func observeMessageInsertionToDonateINSendMessageIntent() {
        let notification = NSNotification.Name.NSManagedObjectContextDidSave
        observationTokens.append(NotificationCenter.default.addObserver(forName: notification, object: nil, queue: nil) { notification in

            guard let context = (notification.object as? NSManagedObjectContext) else { assertionFailure(); return }
            guard context.concurrencyType != .mainQueueConcurrencyType else { return }
            guard let userInfo = notification.userInfo else { assertionFailure(); return }
            guard let insertedObjects = userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject> else { return }
            guard !insertedObjects.isEmpty else { return }

            // Process new PersistedMessageSent

            let newMessagesSent = insertedObjects
                .compactMap({ $0 as? PersistedMessageSent })
                .compactMap({ try? $0.toStructure() })
            for messageSent in newMessagesSent {
                let infos = SentMessageIntentInfos(messageSent: messageSent, urlForStoringPNGThumbnail: nil)
                let intent = Self.getSendMessageIntentForMessageSent(infos: infos)
                Task {
                    await Self.makeDonation(discussionKind: messageSent.discussionKind,
                                            intent: intent,
                                            direction: .outgoing)
                }
            }

            // Process new PersistedMessageReceived

            let newMessagesReceived = insertedObjects
                .compactMap({ $0 as? PersistedMessageReceived })
                .compactMap({ try? $0.toStructure() })
            for messageReceived in newMessagesReceived {
                let infos = ReceivedMessageIntentInfos(messageReceived: messageReceived, urlForStoringPNGThumbnail: nil)
                let intent = Self.getSendMessageIntentForMessageReceived(infos: infos, showGroupName: true)
                Task {
                    await Self.makeDonation(discussionKind: messageReceived.discussionKind,
                                            intent: intent,
                                            direction: .incoming)
                }
            }
            
        })
    }
    

    private func observeDiscussionDeletionToDeleteAllAssociatedDonations() {
        observationTokens.append(ObvMessengerCoreDataNotification.observePersistedDiscussionWasDeleted { discussionURL in
            Task {
                await Self.deleteAllDonations(for: discussionURL)
            }
        })
    }

    
    private func observeDiscussionLockToDeleteAllAssociatedDonations() {
        observationTokens.append(ObvMessengerCoreDataNotification.observePersistedDiscussionStatusChanged { discussionID, status in
            guard case .locked = status else { return }
            Task {
                await Self.deleteAllDonations(for: discussionID.uriRepresentation())
            }
        })
    }

    
    private func observeDiscussionLocalConfigurationUpdatesToDeleteAllDonationsIfAppropriate() {
        observationTokens.append(ObvMessengerInternalNotification.observeDiscussionLocalConfigurationHasBeenUpdated { configValue, objectId in
            guard case .performInteractionDonation(let performInteractionDonation) = configValue else { return }

            // Check whether the user locally disabled interaction donations
            let donationDisabledLocally = performInteractionDonation == false

            // Check whether the user locally set the interaction donation to `default` AND disabled the global interaction donation setting
            let donationDisabledGlobally = performInteractionDonation == nil && ObvMessengerSettings.Discussions.performInteractionDonation == false

            // If one of the two above conditions holds, we should delete all donations for the discussion
            guard donationDisabledLocally || donationDisabledGlobally else { return }

            ObvStack.shared.performBackgroundTask { context in
                guard let localConfiguration = try? PersistedDiscussionLocalConfiguration.get(with: objectId, within: context) else { return }
                guard let discussion = localConfiguration.discussion else { return }
                let discussionURI = discussion.typedObjectID.uriRepresentation()
                Task {
                    await Self.deleteAllDonations(for: discussionURI)
                }
            }
        })
    }

    
    private func observeDiscussionGlobalConfigurationUpdatesToDeleteAllDonationsIfAppropriate() {
        observationTokens.append(ObvMessengerSettingsNotifications.observePerformInteractionDonationSettingDidChange {
            guard ObvMessengerSettings.Discussions.performInteractionDonation == false else { return }

            // If the global interaction donation setting has been disabled, we should remove donations for all discussions for which the local interaction donation setting is set to `default`

            ObvStack.shared.performBackgroundTask { context in
                guard let discussions = try? PersistedDiscussion.getAllActiveDiscussionsForAllOwnedIdentities(within: context) else { return }
                let discussionURIs = discussions
                    .filter({ $0.localConfiguration.performInteractionDonation == nil })
                    .map({ $0.typedObjectID.uriRepresentation() })
                for discussionURI in discussionURIs {
                    Task {
                        await Self.deleteAllDonations(for: discussionURI)
                    }
                }
            }
        })
    }

}


// MARK: - INSendMessageIntent creation

@available(iOS 14.0, *)
extension IntentManager: IntentDelegate {

    static func getSendMessageIntentForMessageReceived(infos: ReceivedMessageIntentInfos,
                                                       showGroupName: Bool) -> INSendMessageIntent {
        var recipients = [infos.ownedINPerson]
        var speakableGroupName: INSpeakableString?
        if let groupInfos = infos.groupInfos, showGroupName {
            speakableGroupName = groupInfos.speakableGroupName
            recipients += groupInfos.groupRecipients
        }
        let sender = infos.contactINPerson

        return getSendMessageIntent(recipients: recipients,
                                    sender: sender,
                                    speakableGroupName: speakableGroupName,
                                    groupINImage: infos.groupInfos?.groupINImage,
                                    conversationIdentifier: infos.discussionObjectID.uriRepresentation().absoluteString)
    }


    private static func getSendMessageIntentForMessageSent(infos: SentMessageIntentInfos) -> INSendMessageIntent {
        let recipients = infos.recipients.persons
        var speakableGroupName: INSpeakableString?
        if let groupInfos = infos.recipients.groupInfos {
            speakableGroupName = groupInfos.speakableGroupName
        }
        let sender = infos.ownedINPerson

        return getSendMessageIntent(recipients: recipients,
                                    sender: sender,
                                    speakableGroupName: speakableGroupName,
                                    groupINImage: infos.recipients.groupInfos?.groupINImage,
                                    conversationIdentifier: infos.discussionObjectID.uriRepresentation().absoluteString)
    }


    private static func getSendMessageIntent(recipients: [INPerson],
                                             sender: INPerson,
                                             speakableGroupName: INSpeakableString?,
                                             groupINImage: INImage?,
                                             conversationIdentifier: String) -> INSendMessageIntent {
        let intent = INSendMessageIntent(
            recipients: recipients,
            outgoingMessageType: .outgoingMessageText,
            content: nil, // Do not expose message body to intent
            speakableGroupName: speakableGroupName,
            conversationIdentifier: conversationIdentifier,
            serviceName: nil,
            sender: sender,
            attachments: nil)
        if let groupINImage {
            intent.setImage(groupINImage, forParameterNamed: \.speakableGroupName)
        }
        return intent
    }

}


// MARK: - INImage Utils

@available(iOS 14.0, *)
extension IntentManager {

    fileprivate static func createINImage(photoURL: URL?, fallbackImage: UIImage?, storingPNGPhotoThumbnailAtURL thumbnailURL: URL?, thumbnailSide: CGFloat) -> INImage? {

        let pngData: Data?
        if let url = photoURL,
           let cgImage = UIImage(contentsOfFile: url.path)?.cgImage?.downsizeToSize(CGSize(width: thumbnailSide, height: thumbnailSide)),
           let _pngData = UIImage(cgImage: cgImage).pngData() {
            pngData = _pngData
        } else {
            pngData = fallbackImage?.pngData()
        }

        let image: INImage?
        if let pngData = pngData {
            if let thumbnailURL = thumbnailURL {
                do {
                    try pngData.write(to: thumbnailURL)
                    image = INImage(url: thumbnailURL)
                } catch {
                    os_log("Could not create PNG thumbnail file for contact", log: IntentManager.log, type: .fault)
                    image = INImage(imageData: pngData)
                }
            } else {
                image = INImage(imageData: pngData)
            }
        } else {
            image = nil
        }
        return image
    }
    
}


// MARK: - Intents informations

private enum SentMessageIntentInfosRecipients {
    case oneToOne(_: INPerson)
    case group(_: GroupInfos)

    var persons: [INPerson] {
        switch self {
        case .oneToOne(let contact):
            return [contact]
        case .group(let groupInfos):
            return groupInfos.groupRecipients
        }
    }

    var groupInfos: GroupInfos? {
        switch self {
        case .oneToOne: return nil
        case .group(let groupInfos): return groupInfos
        }
    }
}


// MARK: - SentMessageIntentInfos

private struct SentMessageIntentInfos {
    
    let discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>
    let ownedINPerson: INPerson
    let recipients: SentMessageIntentInfosRecipients

    @available(iOS 14.0, *)
    init(messageSent: PersistedMessageSent.Structure, urlForStoringPNGThumbnail: URL?) {
        let discussionKind = messageSent.discussionKind
        self.discussionObjectID = discussionKind.typedObjectID
        self.ownedINPerson = discussionKind.ownedIdentity.createINPerson(storingPNGPhotoThumbnailAtURL: urlForStoringPNGThumbnail, thumbnailSide: IntentManager.thumbnailPhotoSide)

        switch discussionKind {
        case .oneToOneDiscussion(let structure):
            let contactINPerson = structure.contactIdentity.createINPerson(storingPNGPhotoThumbnailAtURL: urlForStoringPNGThumbnail, thumbnailSide: IntentManager.thumbnailPhotoSide)
            self.recipients = .oneToOne(contactINPerson)
        case .groupDiscussion(let structure):
            let groupInfos = GroupInfos(groupDiscussion: structure,
                                         urlForStoringPNGThumbnail: urlForStoringPNGThumbnail)
            self.recipients = .group(groupInfos)
        case .groupV2Discussion(let structure):
            let groupInfos = GroupInfos(groupDiscussion: structure,
                                        urlForStoringPNGThumbnail: urlForStoringPNGThumbnail)
            self.recipients = .group(groupInfos)
        }
    }
}


// MARK: - ReceivedMessageIntentInfos

struct ReceivedMessageIntentInfos {

    let discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>
    let ownedINPerson: INPerson
    let contactINPerson: INPerson
    let groupInfos: GroupInfos? // Only set in the case of a group discussion

    @available(iOS 14.0, *)
    init(messageReceived: PersistedMessageReceived.Structure, urlForStoringPNGThumbnail: URL?) {
        let contact = messageReceived.contact
        let discussionKind = messageReceived.discussionKind
        self.init(contact: contact, discussionKind: discussionKind, urlForStoringPNGThumbnail: urlForStoringPNGThumbnail)
    }

    @available(iOS 14.0, *)
    init(contact: PersistedObvContactIdentity.Structure, discussionKind: PersistedDiscussion.StructureKind, urlForStoringPNGThumbnail: URL?) {
        let ownedIdentity = contact.ownedIdentity
        self.discussionObjectID = discussionKind.typedObjectID
        self.ownedINPerson = ownedIdentity.createINPerson(storingPNGPhotoThumbnailAtURL: urlForStoringPNGThumbnail,
                                                          thumbnailSide: IntentManager.thumbnailPhotoSide)
        self.contactINPerson = contact.createINPerson(storingPNGPhotoThumbnailAtURL: urlForStoringPNGThumbnail,
                                                      thumbnailSide: IntentManager.thumbnailPhotoSide)
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
}


// MARK: - GroupInfos

struct GroupInfos {
    
    let groupRecipients: [INPerson]
    let speakableGroupName: INSpeakableString
    let groupINImage: INImage?
    
    @available(iOS 14.0, *)
    init(groupDiscussion: PersistedGroupDiscussion.Structure, urlForStoringPNGThumbnail: URL?) {
        let contactGroup = groupDiscussion.contactGroup
        let contactIdentities = contactGroup.contactIdentities
        var groupRecipients = [INPerson]()
        for contactIdentity in contactIdentities {
            let inPerson = contactIdentity.createINPerson(storingPNGPhotoThumbnailAtURL: urlForStoringPNGThumbnail, thumbnailSide: IntentManager.thumbnailPhotoSide)
            groupRecipients.append(inPerson)
        }
        self.groupRecipients = groupRecipients
        self.speakableGroupName = INSpeakableString(spokenPhrase: groupDiscussion.title)
        self.groupINImage = contactGroup.createINImage(storingPNGPhotoThumbnailAtURL: urlForStoringPNGThumbnail,
                                                       thumbnailSide: IntentManager.thumbnailPhotoSide)
    }

    @available(iOS 14.0, *)
    init(groupDiscussion: PersistedGroupV2Discussion.Structure, urlForStoringPNGThumbnail: URL?) {
        let group = groupDiscussion.group
        let contactIdentities = group.contactIdentities
        var groupRecipients = [INPerson]()
        for contactIdentity in contactIdentities {
            let inPerson = contactIdentity.createINPerson(storingPNGPhotoThumbnailAtURL: urlForStoringPNGThumbnail, thumbnailSide: IntentManager.thumbnailPhotoSide)
            groupRecipients.append(inPerson)
        }
        self.groupRecipients = groupRecipients
        self.speakableGroupName = INSpeakableString(spokenPhrase: groupDiscussion.title)
        self.groupINImage = group.createINImage(storingPNGPhotoThumbnailAtURL: urlForStoringPNGThumbnail,
                                                thumbnailSide: IntentManager.thumbnailPhotoSide)
    }
    
}

// MARK: - Structures to INPerson helper

@available(iOS 14.0, *)
fileprivate extension PersistedObvOwnedIdentity.Structure {
    var personHandle: INPersonHandle {
        INPersonHandle(value: typedObjectID.objectID.uriRepresentation().absoluteString, type: .unknown)
    }

    func createINPerson(storingPNGPhotoThumbnailAtURL thumbnailURL: URL?, thumbnailSide: CGFloat) -> INPerson {

        let fillColor = cryptoId.colors.background
        let characterColor = cryptoId.colors.text
        let circledCharacter = UIImage.makeCircledCharacter(fromString: fullDisplayName,
                                                            circleDiameter: thumbnailSide,
                                                            fillColor: fillColor,
                                                            characterColor: characterColor)
        let image = IntentManager.createINImage(photoURL: photoURL,
                                                fallbackImage: circledCharacter,
                                                storingPNGPhotoThumbnailAtURL: thumbnailURL,
                                                thumbnailSide: thumbnailSide)

        return INPerson(personHandle: personHandle,
                        nameComponents: identityCoreDetails.personNameComponents,
                        displayName: fullDisplayName,
                        image: image,
                        contactIdentifier: nil,
                        customIdentifier: typedObjectID.objectID.uriRepresentation().absoluteString,
                        isMe: true)
    }
}


@available(iOS 14.0, *)
fileprivate extension PersistedObvContactIdentity.Structure {
    var personHandle: INPersonHandle {
        INPersonHandle(value: typedObjectID.objectID.uriRepresentation().absoluteString, type: .unknown)
    }

    func createINPerson(storingPNGPhotoThumbnailAtURL thumbnailURL: URL?, thumbnailSide: CGFloat) -> INPerson {

        let fillColor = cryptoId.colors.background
        let characterColor = cryptoId.colors.text
        let circledCharacter = UIImage.makeCircledCharacter(fromString: fullDisplayName,
                                                            circleDiameter: thumbnailSide,
                                                            fillColor: fillColor,
                                                            characterColor: characterColor)
        let image = IntentManager.createINImage(photoURL: displayPhotoURL,
                                                fallbackImage: circledCharacter,
                                                storingPNGPhotoThumbnailAtURL: thumbnailURL,
                                                thumbnailSide: thumbnailSide)

        return INPerson(personHandle: personHandle,
                        nameComponents: personNameComponents,
                        displayName: customOrFullDisplayName,
                        image: image,
                        contactIdentifier: nil,
                        customIdentifier: typedObjectID.objectID.uriRepresentation().absoluteString,
                        isMe: false)
    }
}

@available(iOS 14.0, *)
fileprivate extension PersistedContactGroup.Structure {

    func createINImage(storingPNGPhotoThumbnailAtURL thumbnailURL: URL?, thumbnailSide: CGFloat) -> INImage? {
        let groupColor = AppTheme.shared.groupColors(forGroupUid: groupUid)
        let circledSymbol = UIImage.makeCircledSymbol(from: ObvSystemIcon.person3Fill.systemName,
                                                      circleDiameter: thumbnailSide,
                                                      fillColor: groupColor.background,
                                                      symbolColor: groupColor.text)
        return IntentManager.createINImage(photoURL: displayPhotoURL,
                                           fallbackImage: circledSymbol,
                                           storingPNGPhotoThumbnailAtURL: thumbnailURL,
                                           thumbnailSide: thumbnailSide)
    }
}

@available(iOS 14.0, *)
fileprivate extension PersistedGroupV2.Structure {

    func createINImage(storingPNGPhotoThumbnailAtURL thumbnailURL: URL?, thumbnailSide: CGFloat) -> INImage? {
        let groupColor = AppTheme.shared.groupV2Colors(forGroupIdentifier: groupIdentifier)
        let circledSymbol = UIImage.makeCircledSymbol(from: ObvSystemIcon.person3Fill.systemName,
                                                      circleDiameter: thumbnailSide,
                                                      fillColor: groupColor.background,
                                                      symbolColor: groupColor.text)
        return IntentManager.createINImage(photoURL: displayPhotoURL,
                                           fallbackImage: circledSymbol,
                                           storingPNGPhotoThumbnailAtURL: thumbnailURL,
                                           thumbnailSide: thumbnailSide)
    }
}

fileprivate extension PersistedDiscussion.StructureKind {

    var ownedIdentity: PersistedObvOwnedIdentity.Structure {
        switch self {
        case .oneToOneDiscussion(structure: let structure):
            return structure.contactIdentity.ownedIdentity
        case .groupDiscussion(structure: let structure):
            return structure.ownerIdentity
        case .groupV2Discussion(structure: let structure):
            return structure.ownerIdentity
        }
    }

    var interactionGroupIdentifier: String {
        typedObjectID.uriRepresentation().interactionGroupIdentifier
    }

}


fileprivate extension PersistedDiscussion {
    
    var interactionGroupIdentifier: String {
        typedObjectID.uriRepresentation().interactionGroupIdentifier
    }
    
}


fileprivate extension TypeSafeURL<PersistedDiscussion> {
 
    var interactionGroupIdentifier: String {
        absoluteString
    }
    
}
