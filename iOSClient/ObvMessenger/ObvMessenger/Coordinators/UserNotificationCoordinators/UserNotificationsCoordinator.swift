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
import UserNotifications
import os.log
import ObvEngine
import ObvTypes
import CoreData
import AVFAudio

final class UserNotificationsCoordinator: NSObject {
    
    private var observationTokens = [NSObjectProtocol]()
    private var kvoTokens = [NSKeyValueObservation]()

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))

    private let appDelegate = UIApplication.shared.delegate as! AppDelegate

    private let userNotificationCenterDelegate: UserNotificationCenterDelegate
    
    private let userDefaults = UserDefaults(suiteName: ObvMessengerConstants.appGroupIdentifier)
    
    // MARK: - Initializer
    
    override init() {
        self.userNotificationCenterDelegate = UserNotificationCenterDelegate()
        super.init()

        // Register as the UNUserNotificationCenter's delegate
        
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.delegate = userNotificationCenterDelegate

        // Register the custom actions/categories
        
        let categories = Set(UserNotificationCategory.allCases.map { $0.getCategory() })
        notificationCenter.setNotificationCategories(categories)
        
        // Observe notifications
        
        observeNewPersistedInvitationNotifications()
        observeRequestIdentifiersOfSilentNotificationsAddedByExtension()
        observeAppDelegateLifecycleNotifications()
        observeTheBodyOfPersistedMessageReceivedDidChangeNotifications()
        observePersistedMessageReceivedWasDeletedNotifications()
        observeUserRequestedDeletionOfPersistedDiscussionNotifications()
        observeReportCallEventNotifications()
        observePersistedMessageReactionReceived()
        observePersistedMessageReactionReceivedWasDeletedNotifications()
    }
    
    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }
    
}

// MARK: - Managing User Notifications related to received messages

extension UserNotificationsCoordinator {

    private func observeReportCallEventNotifications() {
        observationTokens.append(ObvMessengerInternalNotification.observeReportCallEvent { (callUUID, callReport, groupId, ownedCryptoId) in
            ObvStack.shared.performBackgroundTask { (context) in

                switch callReport {
                case .missedIncomingCall(caller: let caller, participantCount: let participantCount),
                     .filteredIncomingCall(caller: let caller, participantCount: let participantCount):
                    guard let callerID = caller?.contactID else { return }
                    let notificationCenter = UNUserNotificationCenter.current()

                    guard let ownedIdentity = try? PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: context) else { return }

                    guard let contactIdentity = try? PersistedObvContactIdentity.get(objectID: callerID, within: context) else { assertionFailure(); return }

                    let discussion: PersistedDiscussion?
                    if let groupId = groupId {
                        guard let contactGroup = try? PersistedContactGroup.getContactGroup(groupId: groupId, ownedIdentity: ownedIdentity) else { return }
                        discussion = contactGroup.discussion
                    } else {
                        discussion = try? PersistedOneToOneDiscussion.get(with: contactIdentity)
                    }
                    guard let discussion = discussion else { return }

                    var contactIdentityDisplayName = contactIdentity.customDisplayName ?? contactIdentity.identityCoreDetails.getDisplayNameWithStyle(.full)
                    if let participantCount = participantCount, participantCount > 1 {
                        contactIdentityDisplayName += " + \(participantCount - 1)"
                    }

                    let (notificationId, notificationContent) = UserNotificationCreator.createMissedCallNotification(callUUID: callUUID, contact: contactIdentity, discussion: discussion, urlForStoringPNGThumbnail: nil, badge: nil)
                    UserNotificationsScheduler.filteredScheduleNotification(discussion: discussion, notificationId: notificationId, notificationContent: notificationContent, notificationCenter: notificationCenter)
                case .rejectedIncomingCallBecauseOfDeniedRecordPermission:
                    switch AVAudioSession.sharedInstance().recordPermission {
                    case .undetermined:
                        let notificationCenter = UNUserNotificationCenter.current()
                        let (notificationId, notificationContent) = UserNotificationCreator.createRequestRecordPermissionNotification()
                        UserNotificationsScheduler.scheduleNotification(notificationId: notificationId, notificationContent: notificationContent, notificationCenter: notificationCenter)
                    case .denied:
                        let notificationCenter = UNUserNotificationCenter.current()
                        let (notificationId, notificationContent) = UserNotificationCreator.createDeniedRecordPermissionNotification()
                        UserNotificationsScheduler.scheduleNotification(notificationId: notificationId, notificationContent: notificationContent, notificationCenter: notificationCenter)
                    case .granted:
                        break
                    @unknown default:
                        break
                    }
                case .acceptedOutgoingCall, .acceptedIncomingCall, .rejectedOutgoingCall, .rejectedIncomingCall, .busyOutgoingCall, .unansweredOutgoingCall, .uncompletedOutgoingCall, .newParticipantInIncomingCall, .newParticipantInOutgoingCall:
                    // Do nothing
                    break
                }
            }
        })
    }
    
    /// When the user decides to delete a discussion, it would too expensive to check whethere there exists a notification for one of the messages within the discussion.
    /// But we do want to delete such a notification if one exist. For now, we simply delete all notifications.
    private func observeUserRequestedDeletionOfPersistedDiscussionNotifications() {
        observationTokens.append(ObvMessengerInternalNotification.observeUserRequestedDeletionOfPersistedDiscussion() { (_, _, _) in
            let notificationCenter = UNUserNotificationCenter.current()
            notificationCenter.removeAllDeliveredNotifications()
            notificationCenter.removeAllPendingNotificationRequests()
        })
    }

    
    /// When a received reaction message is deleted (for whatever reason), we want to removing any existing notification related
    /// to this reaction
    private func observePersistedMessageReactionReceivedWasDeletedNotifications() {
        observationTokens.append(ObvMessengerInternalNotification.observePersistedMessageReactionReceivedWasDeleted { (messageURI, contactURI) in
            let notificationCenter = UNUserNotificationCenter.current()
            let notificationId = ObvUserNotificationIdentifier.newReaction(messageURI: messageURI, contactURI: contactURI)
            UserNotificationsScheduler.removeAllNotificationWithIdentifier(notificationId, notificationCenter: notificationCenter)
        })
    }

    /// When a received message is deleted (for whatever reason), we want to removing any existing notification related
    /// to this message
    private func observePersistedMessageReceivedWasDeletedNotifications() {
        observationTokens.append(ObvMessengerInternalNotification.observePersistedMessageReceivedWasDeleted { (_, messageIdentifierFromEngine, _, _, _) in
            let notificationCenter = UNUserNotificationCenter.current()
            let notificationId = ObvUserNotificationIdentifier.newMessage(messageIdentifierFromEngine: messageIdentifierFromEngine)
            UserNotificationsScheduler.removeAllNotificationWithIdentifier(notificationId, notificationCenter: notificationCenter)
        })
    }
    
    
    private func observeTheBodyOfPersistedMessageReceivedDidChangeNotifications() {
        observationTokens.append(ObvMessengerInternalNotification.observeTheBodyOfPersistedMessageReceivedDidChange { (persistedMessageReceivedObjectID) in
            ObvStack.shared.performBackgroundTask { (context) in
                let notificationCenter = UNUserNotificationCenter.current()
                guard let messageReceived = try? PersistedMessageReceived.get(with: persistedMessageReceivedObjectID, within: context) as? PersistedMessageReceived else { assertionFailure(); return }
                guard let contactIdentity = messageReceived.contactIdentity else { assertionFailure(); return }
                let discussion = messageReceived.discussion
                let (notificationId, notificationContent) = UserNotificationCreator.createNewMessageNotification(
                    body: messageReceived.textBody ?? "",
                    messageIdentifierFromEngine: messageReceived.messageIdentifierFromEngine,
                    contact: contactIdentity,
                    attachmentsFileNames: [],
                    discussion: discussion,
                    urlForStoringPNGThumbnail: nil,
                    badge: nil)
                UserNotificationsScheduler.filteredScheduleNotification(discussion: discussion, notificationId: notificationId, notificationContent: notificationContent, notificationCenter: notificationCenter)
            }
        })
    }
    
    
    // Eeach time the notification extension adds a notification with minimal content (e.g., when it fails to decrypt the notification), we execute the following block.
    // This block first removes all "minimal" notifications and search for unread messages which do not have a corresponding user notifications. The missing notifications are then added.
    private func observeRequestIdentifiersOfSilentNotificationsAddedByExtension() {
        guard let userDefaults = self.userDefaults else {
            os_log("The user defaults database is not set", log: log, type: .fault)
            return
        }
        let token = userDefaults.observe(\.requestIdentifiersOfSilentNotificationsAddedByExtension) { [weak self] (userDefaults, change) in
            guard let _self = self else { return }
            _self.removeAllSilentNotificationsAddedByExtension()
            _self.addMissingNewMessageNotifications()
        }
        kvoTokens.append(token)
    }
    
    
    private func removeAllSilentNotificationsAddedByExtension() {
        guard let userDefaults = self.userDefaults else {
            os_log("The user defaults database is not set", log: log, type: .fault)
            return
        }
        guard let requestIdentifiersWithDatesOfSilentNotificationsAddedByExtension = userDefaults.notificationRequestIdentifiersWithDates(forKey: ObvMessengerConstants.requestIdentifiersOfSilentNotificationsAddedByExtension) else {
            os_log("Could not get the request identifiers of minimal notifications added by the extension", log: log, type: .error)
            return
        }
        let requestIdentifiersOfSilentNotificationsAddedByExtension = requestIdentifiersWithDatesOfSilentNotificationsAddedByExtension.map { $0.requestIdentifier }
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.removeDeliveredNotifications(withIdentifiers: requestIdentifiersOfSilentNotificationsAddedByExtension)
    }
    
    
    private func addMissingNewMessageNotifications() {
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.getDeliveredNotifications { [weak self] (deliveredNotifications) in
            guard let _self = self else { return }
            let log = _self.log
            let messageIdentifiersOfDeliveredNotifications = Set(deliveredNotifications.compactMap { $0.request.content.userInfo["messageIdentifierForNotification"] as? String })
            ObvStack.shared.performBackgroundTaskAndWait { (context) in
                let newMessagesAndNotificationIdentifiers: [(message: PersistedMessageReceived, notificationIdentifier: String)]
                do {
                    let newMessages = try PersistedMessageReceived.getAllNew(with: context)
                    newMessagesAndNotificationIdentifiers = newMessages.compactMap {
                        ($0, ObvUserNotificationIdentifier.newMessage(messageIdentifierFromEngine: $0.messageIdentifierFromEngine).getIdentifier())
                    }
                } catch {
                    os_log("Could not get new messages", log: log, type: .fault)
                    return
                }
                let messageIdentifiersOfNewMessages = Set(newMessagesAndNotificationIdentifiers.map { $0.notificationIdentifier })
                guard !messageIdentifiersOfNewMessages.isEmpty else { return }
                let messageIdentifiersOfMissingNotifications = messageIdentifiersOfNewMessages.subtracting(messageIdentifiersOfDeliveredNotifications)
                guard !messageIdentifiersOfMissingNotifications.isEmpty else { return }
                for (newMessage, identifierForNotification) in newMessagesAndNotificationIdentifiers {
                    guard messageIdentifiersOfMissingNotifications.contains(identifierForNotification) else { continue }
                    if let contactIdentity = newMessage.contactIdentity {
                        let discussion = newMessage.discussion
                        let (notificationId, notificationContent) = UserNotificationCreator.createNewMessageNotification(
                            body: newMessage.textBody ?? "",
                            messageIdentifierFromEngine: newMessage.messageIdentifierFromEngine,
                            contact: contactIdentity,
                            attachmentsFileNames: [],
                            discussion: discussion,
                            urlForStoringPNGThumbnail: nil,
                            badge: nil)
                        UserNotificationsScheduler.filteredScheduleNotification(discussion: discussion, notificationId: notificationId, notificationContent: notificationContent, notificationCenter: notificationCenter)
                    }
                }
            }
        }
    }

    private func observePersistedMessageReactionReceived() {
        let NotificationName = NSNotification.Name.NSManagedObjectContextDidSave
        let notificationCenter = UNUserNotificationCenter.current()
        let token = NotificationCenter.default.addObserver(forName: NotificationName, object: nil, queue: nil) { (notification) in
            guard let userInfo = notification.userInfo else { return }
            var currentReactionNotificationTimestamps: [String: Date] = [:]
            func update(_ requests: [UNNotificationRequest]) {
                for request in requests {
                    guard request.content.userInfo[UserNotificationKeys.id] as? Int == ObvUserNotificationID.newReaction.rawValue else { continue }
                    guard let timestamp = request.content.userInfo[UserNotificationKeys.reactionTimestamp] as? Date else { assertionFailure(); continue }
                    currentReactionNotificationTimestamps[request.identifier] = timestamp
                }
            }
            let insertedObjects = userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject> ?? Set()
            let updatedObjects = userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject> ?? Set()
            let insertedAndUpdatedObjects = insertedObjects.union(updatedObjects)
            guard !insertedAndUpdatedObjects.isEmpty else { return }
            let insertedAndUpdatedReactions = insertedAndUpdatedObjects.compactMap { $0 as? PersistedMessageReactionReceived }
            guard !insertedAndUpdatedReactions.isEmpty else { return }
            let group = DispatchGroup()
            do {
                group.enter()
                notificationCenter.getDeliveredNotifications { deliveredNotifications in
                    let deliveredNotificationsRequests = deliveredNotifications.map { $0.request }
                    update(deliveredNotificationsRequests)
                    group.leave()
                }
            }
            do {
                group.enter()
                notificationCenter.getPendingNotificationRequests { pendingNotificationsRequests in
                    update(pendingNotificationsRequests)
                    group.leave()
                }
            }
            group.wait()
            for reaction in insertedAndUpdatedReactions {
                guard let discussion = reaction.message?.discussion else { continue }
                guard let (notificationId, notificationContent) = UserNotificationCreator.createReactionNotification(reaction: reaction) else { continue }

                if let currentTimestamp = currentReactionNotificationTimestamps[notificationId.getIdentifier()] {
                    if currentTimestamp >= reaction.timestamp {
                        // If it there is aleady a notification with a more recent date we must not update it
                        continue
                    }
                }

                UserNotificationsScheduler.filteredScheduleNotification(discussion: discussion, notificationId: notificationId, notificationContent: notificationContent, notificationCenter: notificationCenter)
            }
        }
        observationTokens.append(token)
    }
}


// MARK: - Hide notifications content when active exits the active state

extension UserNotificationsCoordinator {
    
    private func observeAppDelegateLifecycleNotifications() {
        // If the app quits the active state, and if the user decided to hide all notifications content, we delete all notifications to make sure there is no content left in the notication center.
        let token = ObvMessengerInternalNotification.observeAppStateChanged(queue: OperationQueue.main) { (previousState, currentState) in
            guard previousState.iOSAppState == .mayResignActive && (currentState.iOSAppState != .active || !currentState.isInitializedAndActive) else { return }
            guard ObvMessengerSettings.Privacy.hideNotificationContent != .no else { return }
            // If we reach this point, the app is exiting the active state and the user decided to hide notifications content. So we should do so now.
            let notificationCenter = UNUserNotificationCenter.current()
            notificationCenter.removeAllPendingNotificationRequests()
            notificationCenter.removeAllDeliveredNotifications()
        }
        observationTokens.append(token)
    }
    
}

// MARK: - Managing User Notifications related to invitations

extension UserNotificationsCoordinator {
    
    private func observeNewPersistedInvitationNotifications() {
        let token = ObvMessengerInternalNotification.observeNewOrUpdatedPersistedInvitation { (obvDialog, persistedInvitationUUID) in
            let notificationCenter = UNUserNotificationCenter.current()
            notificationCenter.getNotificationSettings { (settings) in
                // Do not schedule notifications if not authorized.
                guard settings.authorizationStatus == .authorized && settings.alertSetting == .enabled else { return }
                guard let (notificationId, notificationContent) = UserNotificationCreator.createInvitationNotification(obvDialog: obvDialog, persistedInvitationUUID: persistedInvitationUUID) else { return }
                /* 2021-01-11: The following line was commented out. The reason is that we noticed in the header of the addNotificationRequest method of the API (called within scheduleNotification)
                 * that this call will "will replace an existing notification request with the same identifier". So there is no need to remove it beforehand ourselves.
                 */
                UserNotificationsScheduler.scheduleNotification(notificationId: notificationId, notificationContent: notificationContent, notificationCenter: notificationCenter)
            }
        }
        observationTokens.append(token)
    }
}


// MARK: - Helpers

extension UserNotificationsCoordinator {
    

}


// This extension makes it possible to use kvo on the user defaults dictionary used by the notification extension

private extension UserDefaults {
    @objc dynamic var requestIdentifiersOfSilentNotificationsAddedByExtension: String {
        return ObvMessengerConstants.requestIdentifiersOfSilentNotificationsAddedByExtension
    }
}
