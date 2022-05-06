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

import UserNotifications
import ObvEngine
import os.log
import OlvidUtils
import ObvTypes


class NotificationService: UNNotificationServiceExtension {

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: NotificationService.self))
    
    var contentHandler: ((UNNotificationContent) -> Void)?
    var silentAttemptContent: UNNotificationContent?
    var fullAttemptContent: UNNotificationContent?
    var requestIdentifier: String?
    static let runningLog = RunningLogError()
    
    private let userDefaults = UserDefaults(suiteName: ObvMessengerConstants.appGroupIdentifier)
    private let internalQueue = DispatchQueue(label: "NotificationService internal queue")
    
    private let contactThumbnailFileManager = ContactThumbnailFileManager()

    private static var obvEngine: ObvEngine?
    
    private static func makeError(message: String) -> Error {
        NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message])
    }

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        
        os_log("Entering didReceive method", log: log, type: .debug)
        
        contactThumbnailFileManager.deleteOldFiles()
        
        defer {
            cleanUserDefaults()
            addNotification()
        }
        
        // Store the request and content handler, and create a minimal notification to instantiate the full attempt content.
        // This minimal attempt content allows to make sure we display a notification in all situations (even in bad cases where
        // The engine fails to load, e.g., because a database migration is required and the app has not been started yet since
        // The last app upgrade).
        self.contentHandler = contentHandler
        self.fullAttemptContent = UserNotificationCreator.createMinimalNotification(badge: nil).notificationContent
        self.silentAttemptContent = UNNotificationContent()  /// "empty" content object to suppress the notification
        self.requestIdentifier = request.identifier

        // Initialize the engine
        if NotificationService.obvEngine == nil {
            let mainEngineContainer = ObvMessengerConstants.containerURL.mainEngineContainer
            ObvEngine.mainContainerURL = mainEngineContainer
            do {
                NotificationService.obvEngine = try ObvEngine.startLimitedToDecrypting(sharedContainerIdentifier: ObvMessengerConstants.appGroupIdentifier, logPrefix: "DecryptingLimitedEngine", appType: .notificationExtension, runningLog: NotificationService.runningLog)
            } catch {
                os_log("Could not start the obvEngine (happens when a migration is needed)", log: log, type: .fault)
                return
            }
        }
        
        // Initialize the CoreData Stack
        
        do {
            try ObvStack.initSharedInstance(transactionAuthor: ObvMessengerConstants.AppType.notificationExtension.transactionAuthor, runningLog: NotificationService.runningLog, enableMigrations: false)
        } catch let error {
            os_log("Could initialize the ObvStack within the notification service extension: %{public}@", log: log, type: .fault, error.localizedDescription)
            return
        }

        // Extract the information from the received notification
        
        guard let encryptedNotification = EncryptedPushNotification(content: request.content) else {
            os_log("Could not extract information from the received notification", log: log, type: .error)
            return
        }
        
        // First try: Decrypt the notification in order to create an appropriate user notification
        
        if tryToCreateNewMessageNotificationByDecrypting(encryptedPushNotification: encryptedNotification, request: request) {
            os_log("The encrypted push notification was successfully decrypted and the notification was set", log: log, type: .info)
            return
        }
        
        // Second try: If we reach this point, it might be the case that we could not decrypt the notification because the decryption key was not available.
        // This happens in particular when the message was already fetched and decrypted by the app. In that case, the decrypted might already be in database.
        // So we try to fetch it from there.
        
        if tryToCreateNewMessageNotificationByFetchingReceivedMessageFromDatabase(encryptedPushNotification: encryptedNotification, request: request) {
            os_log("The message was found in database. We used it to populate the notification.", log: log, type: .info)
            return
        }
        
        // If we reach this point, we could not decrypt, we could not get the message from the app. We do not display a user notification.
        // It might be the case that the app is in foreground and that we are receiving a message from a non-OntToOne contact or within an unknown group discussion.
        // In those cases, we do not want to display a user notification, we we set the fullAttemptContent to nil.
        
        self.fullAttemptContent = nil
        
    }

    // Update the app badge value within user defaults. The actual app badge is updated using the User Notification badge content.
    private func incrAndGetBadge() -> NSNumber {
        let currentBadgeValue = self.userDefaults?.integer(forKey: UserDefaultsKeyForBadge.keyForAppBadgeCount) ?? 0
        let newBadgeValue = currentBadgeValue + 1
        self.userDefaults?.set(newBadgeValue, forKey: UserDefaultsKeyForBadge.keyForAppBadgeCount)
        return newBadgeValue as NSNumber
    }

    
    private func tryToCreateNewMessageNotificationByFetchingReceivedMessageFromDatabase(encryptedPushNotification: EncryptedPushNotification, request: UNNotificationRequest) -> Bool {

        var returnValue = false
        
        ObvStack.shared.performBackgroundTaskAndWait { [weak self] (context) in

            let messageReceived: PersistedMessageReceived
            do {
                guard let _message = try PersistedMessageReceived.getAll(messageIdentifierFromEngine: encryptedPushNotification.messageIdentifierFromEngine, within: context)
                        .sorted(by: { $0.timestamp < $1.timestamp }).last else {
                    os_log("Could not get find any PersistedMessageReceived for the given message identifier from engine", log: log, type: .error)
                    return
                }
                messageReceived = _message
            } catch {
                os_log("Could not get any PersistedMessageReceived from engine: %{public}@", log: log, type: .fault, error.localizedDescription)
                return
            }
            
            // Save the notification identifier (forced by iOS) and associate it with the message
            
            ObvUserNotificationIdentifier.saveIdentifierForcedInNotificationExtension(
                identifier: request.identifier,
                messageIdentifierFromEngine: messageReceived.messageIdentifierFromEngine,
                timestamp: messageReceived.timestamp)

            // We do not need to save a serialized version of the message for the app (since the app is obviously aware of the message).
            // Similarly, we do not need to create a return receipt. The app took care of that.
                        
            // Construct the notification content
            
            guard let contact = messageReceived.contactIdentity else {
                os_log("Could not determine the contact", log: log, type: .error)
                return
            }
            let discussion = messageReceived.discussion
            if discussion.shouldMuteNotifications {
                self?.fullAttemptContent = nil
            } else {
                let badge = incrAndGetBadge()
                let (_, notificationContent) = UserNotificationCreator.createNewMessageNotification(
                    body: messageReceived.textBody ?? UserNotificationCreator.Strings.NewPersistedMessageReceivedMinimal.body,
                    isEphemeralMessageWithUserAction: messageReceived.isEphemeralMessageWithUserAction,
                    messageIdentifierFromEngine: messageReceived.messageIdentifierFromEngine,
                    contact: contact,
                    attachmentsFileNames: [],
                    discussion: discussion,
                    urlForStoringPNGThumbnail: contactThumbnailFileManager.getFreshRandomURLForStoringNewPNGThumbnail(),
                    badge: badge)
                self?.fullAttemptContent = notificationContent
            }
            
            returnValue = true

        }
        
        return returnValue
        
    }
    
    
    /// Returns true if the encrypted pushed notification was processed, either because a user notification was created, or because we detected that no notification should be shown.
    private func tryToCreateNewMessageNotificationByDecrypting(encryptedPushNotification: EncryptedPushNotification, request: UNNotificationRequest) -> Bool {

        guard NotificationService.obvEngine != nil else {
            os_log("Could not get the obvEngine", log: log, type: .error)
            return false
        }
        
        // Decrypt the information
        
        let obvMessage: ObvMessage
        do {
            obvMessage = try NotificationService.obvEngine!.decrypt(encryptedPushNotification: encryptedPushNotification)
        } catch {
            os_log("Could not decrypt information", log: log, type: .info)
            return false
        }
        
        // Create the persistent message received using the message payload

        let messagePayload = obvMessage.messagePayload
        let persistedItemJSON: PersistedItemJSON
        do {
            persistedItemJSON = try PersistedItemJSON.decode(messagePayload)
        } catch {
            os_log("Could not decode the message payload", log: log, type: .error)
            return false
        }

        guard persistedItemJSON.message != nil || persistedItemJSON.reactionJSON != nil else {
            os_log("We received a notification for an item that does not contain a valid message nor a valid reaction message, which is unexpected", log: log, type: .fault)
            return false
        }

        // Grab the persisted contact and the appropriate discussion
        
        var returnValue = false
        
        ObvStack.shared.performBackgroundTaskAndWait { [weak self] (context) in
            
            guard let _self = self else { return }
            
            guard let persistedContactIdentity = try? PersistedObvContactIdentity.get(persisted: obvMessage.fromContactIdentity, whereOneToOneStatusIs: .any, within: context) else {
                os_log("Could not recover the persisted contact identity", log: _self.log, type: .fault)
                return
            }

            let groupId: (groupUid: UID, groupOwner: ObvCryptoId)?
            if let messageJSON = persistedItemJSON.message {
                groupId = messageJSON.groupId
            } else if let reactionJSON = persistedItemJSON.reactionJSON {
                groupId = reactionJSON.groupId
            } else {
                os_log("The received item should be a message or a reaction", log: _self.log, type: .fault)
                assertionFailure()
                return
            }
            
            let discussion: PersistedDiscussion
            do {
                if let groupId = groupId {
                    guard let ownedIdentity = persistedContactIdentity.ownedIdentity else {
                        os_log("Could not find owned identity. This is ok if it was just deleted.", log: log, type: .error)
                        return
                    }
                    guard let contactGroup = try PersistedContactGroup.getContactGroup(groupId: groupId, ownedIdentity: ownedIdentity) else {
                        throw Self.makeError(message: "Could not find contact group")
                    }
                    discussion = contactGroup.discussion
                } else if let oneToOneDiscussion = try persistedContactIdentity.oneToOneDiscussion {
                    discussion = oneToOneDiscussion
                } else {
                    os_log("Could not find an appropriate discussion where the received message could go.", log: log, type: .error)
                    // We return `true` since we are in a situation where we can decide that no user notification should be shown
                    self?.fullAttemptContent = nil
                    returnValue = true
                    return
                }
            } catch {
                assertionFailure()
                os_log("Core data error: %{public}@", log: log, type: .fault, error.localizedDescription)
                return
            }
            
            // If we reach this point, we found an appropriate discussion where the message can go
            
            // Save the notification identifier (forced by iOS) and associate it with the message
            
            ObvUserNotificationIdentifier.saveIdentifierForcedInNotificationExtension(
                identifier: request.identifier,
                messageIdentifierFromEngine: obvMessage.messageIdentifierFromEngine,
                timestamp: obvMessage.messageUploadTimestampFromServer)
            
            // Save a serialized version of the `ObvMessage` in an appropriate location so that the app can fetch it immediately at next launch
            
            do {
                let jsonDecryptedMessage = try obvMessage.encodeToJson()
                let directory = ObvMessengerConstants.containerURL.forMessagesDecryptedWithinNotificationExtension
                let filename = [encryptedPushNotification.messageIdFromServerAsString, "json"].joined(separator: ".")
                let filepath = directory.appendingPathComponent(filename)
                try jsonDecryptedMessage.write(to: filepath)
                os_log("📮 Notification extension has saved a serialized version of the message.", log: log, type: .info)
            } catch let error {
                os_log("📮 Could not save a serialized version of the message: %{public}@", log: log, type: .fault, error.localizedDescription)
                // Continue anyway
            }

            // If there is a return receipt within the json item we received, we use it to send a return receipt for the received obvMessage
            
            if let returnReceiptJSON = persistedItemJSON.returnReceipt {
                do {
                    try NotificationService.obvEngine!.postReturnReceiptWithElements(
                        returnReceiptJSON.elements,
                        andStatus: ReturnReceiptJSON.Status.delivered.rawValue,
                        forContactCryptoId: obvMessage.fromContactIdentity.cryptoId,
                        ofOwnedIdentityCryptoId: obvMessage.fromContactIdentity.ownedIdentity.cryptoId)
                } catch {
                    os_log("The Return Receipt could not be posted", log: log, type: .fault)
                    // Continue anyway
                }
            }

            // Depending on whether the discussion is muted or not, we construct the notification content

            if discussion.shouldMuteNotifications {

                self?.fullAttemptContent = nil
                
            } else {
                // Construct the notification content

                if let messageJSON = persistedItemJSON.message {
                    let textBody: String?
                    var isEphemeralMessageWithUserAction = false
                    if let expiration = messageJSON.expiration, expiration.visibilityDuration != nil || expiration.readOnce {
                        isEphemeralMessageWithUserAction = true
                    }
                    if isEphemeralMessageWithUserAction {
                        textBody = NSLocalizedString("EPHEMERAL_MESSAGE", comment: "")
                    } else {
                        textBody = messageJSON.body
                    }
                    let badge = incrAndGetBadge()
                    let (_, notificationContent) = UserNotificationCreator.createNewMessageNotification(
                        body: textBody ?? UserNotificationCreator.Strings.NewPersistedMessageReceivedMinimal.body,
                        isEphemeralMessageWithUserAction: isEphemeralMessageWithUserAction,
                        messageIdentifierFromEngine: encryptedPushNotification.messageIdentifierFromEngine,
                        contact: persistedContactIdentity,
                        attachmentsFileNames: [],
                        discussion: discussion,
                        urlForStoringPNGThumbnail: contactThumbnailFileManager.getFreshRandomURLForStoringNewPNGThumbnail(),
                        badge: badge)
                    self?.fullAttemptContent = notificationContent
                } else if let reactionJSON = persistedItemJSON.reactionJSON {
                    self?.fullAttemptContent = nil // Do not want any minimal notification on failure for reaction.

                    guard let message = try? PersistedMessage.findMessageFrom(reference: reactionJSON.messageReference, within: discussion) else { return }
                    guard message is PersistedMessageSent, !message.isWiped else { return }

                    if let emoji = reactionJSON.emoji {
                        if let (_, notificationContent) = UserNotificationCreator.createReactionNotification(message: message, contact: persistedContactIdentity, emoji: emoji, reactionTimestamp: obvMessage.messageUploadTimestampFromServer) {
                            self?.fullAttemptContent = notificationContent
                        }
                    } else {
                        // Nothing can be done: we are not able to remove the notification from the extension and we cannot wake up the app.
                    }
                }

            }
            returnValue = true
        }

        return returnValue        
    }
    
    private func addNotification() {
        if addFullNotification() { return }
        if addSilentNotification() { return }
        os_log("Could not add notification at all", log: log, type: .fault)
    }

    
    private func addFullNotification() -> Bool {
        guard let contentHandler = self.contentHandler else {
            os_log("The content handler is not set", log: log, type: .fault)
            return false
        }
        guard let fullAttemptContent = self.fullAttemptContent else {
            os_log("The full attemps content is not set", log: log, type: .error)
            return false
        }
        contentHandler(fullAttemptContent)
        notifyAppOfNewFullNotification()
        return true
    }

    private func addSilentNotification() -> Bool {
        guard let contentHandler = self.contentHandler else {
            os_log("The content handler is not set", log: log, type: .fault)
            return false
        }
        guard let silentAttemptContent = self.silentAttemptContent else {
            os_log("The silent attemps content is not set", log: log, type: .fault)
            return false
        }
        contentHandler(silentAttemptContent)
        notifyAppOfNewSilentNotification()
        return true
    }
    
    private func notifyAppOfNotification(with key: String) {
        guard let userDefaults = self.userDefaults else {
            os_log("Could not access user defaults", log: log, type: .fault)
            return
        }
        guard let requestIdentifier = self.requestIdentifier else {
            os_log("The request identifier is not set", log: log, type: .fault)
            return
        }
        internalQueue.sync {
            var notificationRequestIdentifiersWithDates = userDefaults.notificationRequestIdentifiersWithDates(forKey: key) ?? []
            let newIdentifierWithDate = UNNotificationRequestIdentifierWithDate(requestIdentifier: requestIdentifier, date: Date())
            notificationRequestIdentifiersWithDates.append(newIdentifierWithDate)
            userDefaults.set(notificationRequestIdentifiersWithDates, forKey: key)
        }
    }

    private func notifyAppOfNewSilentNotification() {
        notifyAppOfNotification(with: ObvMessengerConstants.requestIdentifiersOfSilentNotificationsAddedByExtension)
    }

    private func notifyAppOfNewFullNotification() {
        notifyAppOfNotification(with: ObvMessengerConstants.requestIdentifiersOfFullNotificationsAddedByExtension)
    }

    private func cleanNotifications(for key: String) {
        guard let userDefaults = self.userDefaults else {
            os_log("Could not access user defaults", log: log, type: .fault)
            return
        }
        internalQueue.sync {
            let notificationRequestIdentifiersWithDates = userDefaults.notificationRequestIdentifiersWithDates(forKey: key) ?? []
            let yesterday = Date().addingTimeInterval(TimeInterval.init(60*60*24)) // One day
            let notificationRequestIdentifiersWithDatesToKeep = notificationRequestIdentifiersWithDates.filter { $0.date > yesterday }
            os_log("We cleaned %d old entries in the user defaults db for notifications", log: log, type: .info, notificationRequestIdentifiersWithDates.count - notificationRequestIdentifiersWithDatesToKeep.count)
            userDefaults.set(notificationRequestIdentifiersWithDatesToKeep, forKey: key)
        }
    }

    private func cleanUserDefaults() {
        cleanNotifications(for: ObvMessengerConstants.requestIdentifiersOfSilentNotificationsAddedByExtension)
        cleanNotifications(for: ObvMessengerConstants.requestIdentifiersOfFullNotificationsAddedByExtension)
    }

    
    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
        addNotification()
    }
    
}


fileprivate extension EncryptedPushNotification {
    
    init?(content: UNNotificationContent) {
        
        let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "EncryptedPushNotification")

        let wrappedKeyString = content.userInfo["encryptedHeader"] as? String ?? content.title
        let encryptedContentString = content.userInfo["encryptedMessage"] as? String ?? content.body
        
        guard let wrappedKey = Data(base64Encoded: wrappedKeyString) else {
            os_log("Could not decode de base64encoded wrapped key string found in the encrypted header of the user info", log: log, type: .error)
            return nil
        }
        
        guard let encryptedContent = Data(base64Encoded: encryptedContentString) else {
            os_log("Could not decode de base64encoded encrypted content found in the encrypted message field of the user info", log: log, type: .error)
            return nil
        }
        
        guard let maskingUID = content.userInfo["maskinguid"] as? String else {
            os_log("Could not find the masking uid (as a String) in the user info dictionary", log: log, type: .error)
            return nil
        }
        
        guard let messageUploadTimestampFromServerAsDouble = content.userInfo["timestamp"] as? Double else {
            os_log("Could not find the message upload timestamp from server (as a Double) in the user info dictionary", log: log, type: .error)
            return nil
        }

        guard let messageIdFromServer = content.userInfo["messageuid"] as? String else {
            os_log("Could not find the messageId from server (as a String) in the user info dictionary", log: log, type: .error)
            return nil
        }
        
        let messageUploadTimestampFromServer = Date(timeIntervalSince1970: messageUploadTimestampFromServerAsDouble / 1000.0)

        self.init(messageIdFromServer: messageIdFromServer,
                  wrappedKey: wrappedKey,
                  encryptedContent: encryptedContent,
                  maskingUID: maskingUID,
                  messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                  localDownloadTimestamp: Date())
        
    }
    
}


fileprivate final class ContactThumbnailFileManager {

    private let ttlOfThumbnailFile = TimeInterval(60) // In seconds
    private let maxNumberOfFilesToKeep = 200
    
    private var directoryForThumnails: URL? {
        let temporaryDirectory = FileManager.default.temporaryDirectory
        let directory = temporaryDirectory.appendingPathComponent("ContactThumbnailFileManager", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            } catch {
                return nil
            }
        }
        return directory
    }

    fileprivate func getFreshRandomURLForStoringNewPNGThumbnail() -> URL? {
        guard let directory = directoryForThumnails else { assertionFailure(); return nil }
        let filename = [UUID().uuidString, "png"].joined(separator: ".")
        let url = URL(fileURLWithPath: directory.path).appendingPathComponent(filename)
        return url
    }
    
    
    /// Deletes all thumbnail files older than the TTL. If required, delete more files to make sure we do not keep more than a certain amount of files.
    fileprivate func deleteOldFiles() {
        let dateLimit = Date(timeIntervalSinceNow: -ttlOfThumbnailFile)
        guard let directory = directoryForThumnails else { assertionFailure(); return }
        // First pass: delete old files
        do {
            guard let fileURLs = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey]) else { return }
            for fileURL in fileURLs {
                guard let attributes = try? fileURL.resourceValues(forKeys: Set([.creationDateKey])) else { continue }
                guard let creationDate = attributes.creationDate, creationDate < dateLimit else { debugPrint("Keep"); return }
                // If we reach this point, we should delete the archive
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        // Second pass: keep no more than `maxNumberOfFilesToKeep` files
        do {
            guard let fileURLs = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey]) else { return }
            guard fileURLs.count > maxNumberOfFilesToKeep else { return }
            let fileURLsAndCreationDates: [(url: URL, creationDate: Date)] = fileURLs
                .compactMap({
                    guard let attributes = try? $0.resourceValues(forKeys: Set([.creationDateKey])) else { return nil }
                    guard let creationDate = attributes.creationDate else { return nil }
                    return ($0, creationDate)
                })
            var sortedURLs = fileURLsAndCreationDates.sorted(by: { $0.creationDate < $1.creationDate }).map({ $0.url })
            guard sortedURLs.count > maxNumberOfFilesToKeep else { return }
            sortedURLs.removeLast(sortedURLs.count - maxNumberOfFilesToKeep)
            for fileURL in sortedURLs {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }
    
}
