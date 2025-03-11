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
import ObvTypes
import ObvCrypto


@objc(PersistedObvMessage)
final class PersistedObvMessage: NSManagedObject {
    
    private static let entityName = "PersistedObvMessage"
    
    // MARK: - Attributes
    
    @NSManaged private var downloadTimestampFromServer: Date? // Expected to be non-nil
    @NSManaged private var expectedAttachmentsCount: Int
    @NSManaged private var extendedMessagePayload: Data?
    @NSManaged private var localDownloadTimestamp: Date? // Expected to be non-nil
    @NSManaged private var messagePayload: Data? // Expected to be non-nil
    @NSManaged private var messageUploadTimestampFromServer: Date? // Expected to be non-nil
    @NSManaged private var rawContactDeviceUID: Data? // Expected to be non-nil (except for old notifications)
    @NSManaged private var rawContactIdentity: Data? // Expected to be non-nil
    @NSManaged private var rawMessageIdFromServer: Data?
    @NSManaged private var rawOwnedIdentity: Data? // Expected to be non-nil
    @NSManaged private var wasPersistedInApp: Bool // False on creation, set to True when the ObvMessage was persisted by the app

    // MARK: - Relationships

    private var notification: PersistedUserNotification? // Expected to be non-nil
    
    // MARK: - Accessors
    
    private var ownedCryptoId: ObvCryptoId {
        get throws {
            guard let rawOwnedIdentity else {
                assertionFailure()
                throw ObvError.rawOwnedIdentityIsNil
            }
            return try ObvCryptoId(identity: rawOwnedIdentity)
        }
    }
    
    private var fromContactIdentity: ObvContactIdentifier {
        get throws {
            guard let rawContactIdentity else {
                assertionFailure()
                throw ObvError.rawContactIdentityIsNil
            }
            let contactCryptoId = try ObvCryptoId(identity: rawContactIdentity)
            return .init(contactCryptoId: contactCryptoId, ownedCryptoId: try ownedCryptoId)
        }
    }
    
    /// Expected to be non-nil (except for old notifications, published prior version 3.4)
    private var fromContactDeviceUID: UID? {
        guard let rawContactDeviceUID else { return nil }
        guard let contactCryptoId = UID(uid: rawContactDeviceUID) else { assertionFailure(); return nil }
        return contactCryptoId
    }
    
    private var messageId: ObvMessageIdentifier {
        get throws {
            guard let rawMessageIdFromServer else {
                assertionFailure()
                throw ObvError.rawMessageIdFromServerIsNil
            }
            guard let uid = UID(uid: rawMessageIdFromServer) else {
                assertionFailure()
                throw ObvError.couldNotParseMessageIdFromServer
            }
            return ObvMessageIdentifier(ownedCryptoId: try ownedCryptoId, uid: uid)
        }
    }
    
    
    var obvMessage: ObvMessage {
        get throws {
            guard let messageUploadTimestampFromServer,
                  let downloadTimestampFromServer,
                  let localDownloadTimestamp,
                  let messagePayload else {
                assertionFailure()
                throw ObvError.unexpectedNilValue
            }
            return ObvMessage(
                fromContactIdentity: try fromContactIdentity,
                fromContactDeviceUID: self.fromContactDeviceUID,
                messageId: try messageId,
                attachments: [], // Since the ObvMessage comes from a remote user notification, we expect no attachments.
                expectedAttachmentsCount: expectedAttachmentsCount,
                messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                downloadTimestampFromServer: downloadTimestampFromServer,
                localDownloadTimestamp: localDownloadTimestamp,
                messagePayload: messagePayload,
                extendedMessagePayload: extendedMessagePayload)
        }
    }
    
    
    // MARK: - Initializer

    private convenience init(obvMessage: ObvMessage, within context: NSManagedObjectContext) throws {
        
        let entityDescription = NSEntityDescription.entity(forEntityName: Self.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        
        self.rawOwnedIdentity = obvMessage.fromContactIdentity.ownedCryptoId.getIdentity()
        self.rawContactIdentity = obvMessage.fromContactIdentity.contactCryptoId.getIdentity()
        self.rawContactDeviceUID = obvMessage.fromContactDeviceUID?.raw // Expected to be non-nil
        self.rawMessageIdFromServer = obvMessage.messageId.uid.raw
        self.expectedAttachmentsCount = obvMessage.expectedAttachmentsCount
        self.messageUploadTimestampFromServer = obvMessage.messageUploadTimestampFromServer
        self.downloadTimestampFromServer = obvMessage.downloadTimestampFromServer
        self.localDownloadTimestamp = obvMessage.localDownloadTimestamp
        self.messagePayload = obvMessage.messagePayload
        self.extendedMessagePayload = obvMessage.extendedMessagePayload
        self.wasPersistedInApp = false
        
        // Note that we discard any content found in obvMessage.attachments (which is empty anyway when the ObvMessage comes from the notification extension).

    }
    
    static func createContent(obvMessage: ObvMessage, within context: NSManagedObjectContext) throws -> PersistedObvMessage {
        return try self.init(obvMessage: obvMessage, within: context)
    }
    
    
    func deletePersistedObvMessage() throws {
        guard let context = self.managedObjectContext else {
            throw ObvError.noManagedObjectContext
        }
        context.delete(self)
    }
    
    
    /// When the app is launched, we persist the `ObvMessages` contained in persisted user notification. Each time such an `ObvMessage` is persisted, we call this method.
    /// This allows not to try to persist it again.
    func markAsPersistedInApp() {
        if !wasPersistedInApp {
            wasPersistedInApp = true
        }
    }
    
}


extension PersistedObvMessage {
    
    enum Predicate {
        enum Key: String {
            // Attributes
            case messageUploadTimestampFromServer = "messageUploadTimestampFromServer"
            case wasPersistedInApp = "wasPersistedInApp"
            // Relationships
            case notification = "notification"
        }
        static var withNoAssociatedNotification: NSPredicate {
            .init(withNilValueForKey: Key.notification)
        }
    }
    
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<PersistedObvMessage> {
        return NSFetchRequest<PersistedObvMessage>(entityName: Self.entityName)
    }
    
    
    static func deleteOrphanedPersistedObvMessage(within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<PersistedObvMessage> = Self.fetchRequest()
        request.predicate = Predicate.withNoAssociatedNotification
        request.fetchBatchSize = 100
        request.propertiesToFetch = []
        let items = try context.fetch(request)
        for item in items {
            try item.deletePersistedObvMessage()
        }
    }
    
}


// MARK: - Errors

extension PersistedObvMessage {
    
    enum ObvError: Swift.Error {
        case noManagedObjectContext
        case rawContactIdentityIsNil
        case rawOwnedIdentityIsNil
        case rawMessageIdFromServerIsNil
        case couldNotParseMessageIdFromServer
        case unexpectedNilValue
    }
    
}
