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
import CoreData
import Intents
import os.log
import ObvUI
import UIKit
import ObvUICoreData
import ObvSettings


protocol IntentDelegate: AnyObject {
    @available(iOS 14.0, *)
    static func getSendMessageIntentForMessageReceived(infos: ReceivedMessageIntentInfos,
                                                       showGroupName: Bool) -> INSendMessageIntent
}


@available(iOS 14.0, *)
final class IntentManager {

    fileprivate static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: IntentManager.self))

    private var observationTokens = [NSObjectProtocol]()

    func performPostInitialization() {
        observeMessageInsertionToDonateINSendMessageIntent()
        observeDiscussionDeletionToDeleteAllAssociatedDonations()
        observeDiscussionLockToDeleteAllAssociatedDonations()
        observeDiscussionLocalConfigurationUpdatesToDeleteAllDonationsIfAppropriate()
        observeDiscussionGlobalConfigurationUpdatesToDeleteAllDonationsIfAppropriate()
    }

    
    private static func deleteAllDonations(for objectPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>) async {
        do {
            try await INInteraction.delete(with: objectPermanentID.interactionGroupIdentifier)
            os_log("🎁 Successfully deleted all interactions", log: Self.log, type: .info)
        } catch {
            assertionFailure()
            os_log("🎁 Interaction deletion failed: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
        }
    }

    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
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
                .compactMap({
                    try? $0.toStruct()
                })
            for messageSent in newMessagesSent {
                let infos = SentMessageIntentInfos(messageSent: messageSent)
                let intent = IntentManagerUtils.getSendMessageIntentForMessageSent(infos: infos)
                Task {
                    await IntentManagerUtils.makeDonation(discussionKind: messageSent.discussionKind,
                                            intent: intent,
                                            direction: .outgoing)
                }
            }

            // Process new PersistedMessageReceived

            let newMessagesReceived = insertedObjects
                .compactMap({ $0 as? PersistedMessageReceived })
                .compactMap({ try? $0.toStruct() })
            for messageReceived in newMessagesReceived {
                let infos = ReceivedMessageIntentInfos(messageReceived: messageReceived)
                let intent = Self.getSendMessageIntentForMessageReceived(infos: infos, showGroupName: true)
                Task {
                    await IntentManagerUtils.makeDonation(discussionKind: messageReceived.discussionKind,
                                            intent: intent,
                                            direction: .incoming)
                }
            }
            
        })
    }
    

    private func observeDiscussionDeletionToDeleteAllAssociatedDonations() {
        observationTokens.append(ObvMessengerCoreDataNotification.observePersistedDiscussionWasDeleted { discussionPermanentID, _ in
            Task {
                await Self.deleteAllDonations(for: discussionPermanentID)
            }
        })
    }

    
    private func observeDiscussionLockToDeleteAllAssociatedDonations() {
        observationTokens.append(ObvMessengerCoreDataNotification.observePersistedDiscussionStatusChanged { discussionPermanentID, status in
            guard case .locked = status else { return }
            Task {
                await Self.deleteAllDonations(for: discussionPermanentID)
            }
        })
    }

    
    private func observeDiscussionLocalConfigurationUpdatesToDeleteAllDonationsIfAppropriate() {
        observationTokens.append(ObvMessengerCoreDataNotification.observeDiscussionLocalConfigurationHasBeenUpdated { configValue, objectId in
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
                let discussionPermanentID = discussion.discussionPermanentID
                Task {
                    await Self.deleteAllDonations(for: discussionPermanentID)
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
                let discussionPermanentIDs = discussions
                    .filter({ $0.localConfiguration.performInteractionDonation == nil })
                    .map({ $0.discussionPermanentID })
                for discussionPermanentID in discussionPermanentIDs {
                    Task {
                        await Self.deleteAllDonations(for: discussionPermanentID)
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
        if let groupInfos = infos.groupInfos {
            speakableGroupName = groupInfos.speakableGroupName
            recipients += groupInfos.groupRecipients
        }
        let sender = infos.contactINPerson

        return IntentManagerUtils.getSendMessageIntent(recipients: recipients,
                                    sender: sender,
                                    speakableGroupName: speakableGroupName,
                                    groupINImage: infos.groupInfos?.groupINImage,
                                    conversationIdentifier: infos.conversationIdentifier)
    }

}


// MARK: - ReceivedMessageIntentInfos

struct ReceivedMessageIntentInfos {

    let discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>
    let ownedINPerson: INPerson
    let contactINPerson: INPerson
    let groupInfos: GroupInfos? // Only set in the case of a group discussion

    var conversationIdentifier: String { discussionPermanentID.description }
    
    @available(iOS 14.0, *)
    init(messageReceived: PersistedMessageReceived.Structure) {
        let contact = messageReceived.contact
        let discussionKind = messageReceived.discussionKind
        self.init(contact: contact, discussionKind: discussionKind)
    }

    @available(iOS 14.0, *)
    init(contact: PersistedObvContactIdentity.Structure, discussionKind: PersistedDiscussion.StructureKind) {
        self.discussionPermanentID = discussionKind.discussionPermanentID
        let ownedIdentity = contact.ownedIdentity
        self.ownedINPerson = ownedIdentity.createINPerson(withINImage: false)
        switch discussionKind {
        case .groupDiscussion(structure: let structure):
            self.contactINPerson = contact.createINPerson(withINImage: false)
            self.groupInfos = GroupInfos(groupDiscussion: structure, withINImage: true)
        case .groupV2Discussion(structure: let structure):
            self.contactINPerson = contact.createINPerson(withINImage: false)
            self.groupInfos = GroupInfos(groupDiscussion: structure, withINImage: true)
        case .oneToOneDiscussion:
            self.contactINPerson = contact.createINPerson(withINImage: true)
            self.groupInfos = nil
        }
    }
}


fileprivate extension PersistedDiscussion {
    
    var interactionGroupIdentifier: String {
        self.discussionPermanentID.interactionGroupIdentifier
    }
    
}
