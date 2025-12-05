/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import OlvidUtils
import ObvCrypto
import OSLog


@objc(KeycloakRevokedIdentity)
final class KeycloakRevokedIdentity: NSManagedObject {
    
    // MARK: Internal constants
    
    private static let entityName = "KeycloakRevokedIdentity"

    private static let errorDomain = "KeycloakRevokedIdentity"
    private static func makeError(message: String) -> Error { NSError(domain: errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { KeycloakRevokedIdentity.makeError(message: message) }

    static weak var delegateManager: ObvIdentityDelegateManager?
    
    private static var logSubsystem: String { delegateManager?.logSubsystem ?? ObvIdentityDelegateManager.defaultLogSubsystem }
    private static var logger: Logger = { Logger(subsystem: KeycloakRevokedIdentity.logSubsystem, category: "KeycloakRevokedIdentity") }()

    // MARK: Attributes

    @NSManaged private var rawIdentity: Data
    @NSManaged private var rawRevocationType: Int
    @NSManaged private(set) var revocationTimestamp: Date
    
    // MARK: Relationships

    @NSManaged private(set) var keycloakServer: KeycloakServer? // Expected to be non-nil
    
    // MARK: Other variables

    enum RevocationType: Int {
        case compromised = 0
        case leftCompany = 1
    }
    
    var identity: ObvCryptoIdentity {
        get throws {
            guard let cryptoId = ObvCryptoIdentity(from: rawIdentity) else { throw makeError(message: "Could not deserialize identity stored in database") }
            return cryptoId
        }
    }
    
    private func setIdentiy(with cryptoIdentity: ObvCryptoIdentity) {
        self.rawIdentity = cryptoIdentity.getIdentity()
    }
    
    var revocationType: RevocationType {
        get throws {
            guard let type = RevocationType(rawValue: rawRevocationType) else { throw makeError(message: "Could not deserialize revocation type from database") }
            return type
        }
    }
    
    private func setRevocationType(_ revocationType: RevocationType) {
        self.rawRevocationType = revocationType.rawValue
    }
        
    // MARK: - Initializer

    convenience init?(keycloakServer: KeycloakServer, keycloakRevocation: JsonKeycloakRevocation) throws {
        try self.init(
            keycloakServer: keycloakServer,
            identity: keycloakRevocation.cryptoIdentity,
            revocationType: keycloakRevocation.revocationType,
            revocationTimestamp: keycloakRevocation.revocationTimestamp)
    }
    
    convenience init?(keycloakServer: KeycloakServer, identity: ObvCryptoIdentity, revocationType: RevocationType, revocationTimestamp: Date) throws {
        guard let context = keycloakServer.managedObjectContext else { throw KeycloakRevokedIdentity.makeError(message: "KeycloakRevokedIdentity initialization failed, cannot find appropriate context") }

        guard try KeycloakRevokedIdentity.noEntryExists(keycloakServer: keycloakServer, identity: identity, revocationType: revocationType, revocationTimestamp: revocationTimestamp) else {
            Self.logger.info("A previous entry with the identical values already exists within the KeycloakRevokedIdentity database, we skip this init")
            return nil
        }
        
        let entityDescription = NSEntityDescription.entity(forEntityName: KeycloakRevokedIdentity.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        self.setIdentiy(with: identity)
        self.setRevocationType(revocationType)
        self.revocationTimestamp = revocationTimestamp
        self.keycloakServer = keycloakServer
    }
    
    
    func delete() throws {
        guard let context = self.managedObjectContext else { assertionFailure(); throw makeError(message: "Could not delete KeycloakRevokedIdentity instance since no obv context could be found.") }
        context.delete(self)
    }

    // MARK: - Database queries
    
    private struct Predicate {
        enum Key: String {
            case rawIdentity = "rawIdentity"
            case rawRevocationType = "rawRevocationType"
            case revocationTimestamp = "revocationTimestamp"
            case keycloakServer = "keycloakServer"
        }
        static func withKeycloakServer(_ keycloakServer: KeycloakServer) -> NSPredicate {
            NSPredicate.init(Key.keycloakServer, equalTo: keycloakServer)
        }
        static func withRevocationTimestampBeforeDate(_ date: Date) -> NSPredicate {
            NSPredicate(Key.revocationTimestamp, earlierThan: date)
        }
        static func withIdentity(_ identity: ObvCryptoIdentity) -> NSPredicate {
            NSPredicate(format: "%K == %@", Key.rawIdentity.rawValue, identity.getIdentity() as NSData)
        }
        static func withRevocationType(_ revocationType: RevocationType) -> NSPredicate {
            NSPredicate(format: "%K == %d", Key.rawRevocationType.rawValue, revocationType.rawValue)
        }
        static func withRevocationTimestamp(_ revocationTimestamp: Date) -> NSPredicate {
            NSPredicate(Key.revocationTimestamp, equalToDate: revocationTimestamp)
        }
    }
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<KeycloakRevokedIdentity> {
        return NSFetchRequest<KeycloakRevokedIdentity>(entityName: KeycloakRevokedIdentity.entityName)
    }
    
    
    private static func noEntryExists(keycloakServer: KeycloakServer, identity: ObvCryptoIdentity, revocationType: RevocationType, revocationTimestamp: Date) throws -> Bool {
        guard let context = keycloakServer.managedObjectContext else { assertionFailure(); throw KeycloakRevokedIdentity.makeError(message: "Could not find obv context in KeycloakServer instance (3)") }
        let request: NSFetchRequest<KeycloakRevokedIdentity> = KeycloakRevokedIdentity.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withKeycloakServer(keycloakServer),
            Predicate.withIdentity(identity),
            Predicate.withRevocationType(revocationType),
            Predicate.withRevocationTimestamp(revocationTimestamp),
        ])
        request.fetchLimit = 1
        let item = try context.fetch(request).first
        return item == nil
    }

    
    static func batchDeleteEntriesWithRevocationTimestampBeforeDate(_ date: Date, for keycloakServer: KeycloakServer) throws {
        guard let context = keycloakServer.managedObjectContext else { assertionFailure(); throw KeycloakRevokedIdentity.makeError(message: "Could not find obv context in KeycloakServer instance") }
        let request: NSFetchRequest<NSFetchRequestResult> = KeycloakRevokedIdentity.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withKeycloakServer(keycloakServer),
            Predicate.withRevocationTimestampBeforeDate(date),
        ])
        let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        batchDeleteRequest.resultType = .resultTypeObjectIDs
        let result = try context.execute(batchDeleteRequest) as? NSBatchDeleteResult
        // The previous call **immediately** updates the SQLite database
        // We merge the changes back to the current context
        if let objectIDArray = result?.result as? [NSManagedObjectID] {
            let changes = [NSUpdatedObjectsKey : objectIDArray]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])
        } else {
            assertionFailure()
        }
    }
    
    
    static func get(keycloakServer: KeycloakServer, identity: ObvCryptoIdentity) throws -> [KeycloakRevokedIdentity] {
        guard let context = keycloakServer.managedObjectContext else { assertionFailure(); throw KeycloakRevokedIdentity.makeError(message: "Could not find obv context in KeycloakServer instance (2)") }
        let request: NSFetchRequest<KeycloakRevokedIdentity> = KeycloakRevokedIdentity.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withKeycloakServer(keycloakServer),
            Predicate.withIdentity(identity),
        ])
        return try context.fetch(request)
    }
    
}
