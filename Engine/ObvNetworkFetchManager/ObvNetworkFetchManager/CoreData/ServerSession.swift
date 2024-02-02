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
import CoreData
import os.log
import ObvTypes
import ObvCrypto
import OlvidUtils
import ObvMetaManager


@objc(ServerSession)
final class ServerSession: NSManagedObject, ObvErrorMaker {

    private static let entityName = "ServerSession"
    static let errorDomain = "ServerSession"

    // MARK: Attributes

    @NSManaged private var rawAPIKeyExpirationDate: Date?
    @NSManaged private var rawAPIKeyStatus: NSNumber?
    @NSManaged private var rawAPIPermissions: NSNumber?
    @NSManaged private var rawOwnedCryptoId: Data
    @NSManaged private(set) var token: Data?
    
    // MARK: Other variables
    
    var ownedCryptoIdentity: ObvCryptoIdentity {
        get throws {
            guard let cryptoIdentity = ObvCryptoIdentity(from: rawOwnedCryptoId) else {
                throw Self.makeError(message: "Could not decode rawOwnedCryptoId")
            }
            return cryptoIdentity
        }
    }
    
    
    private(set) var apiKeyExpirationDate: Date? {
        get { self.rawAPIKeyExpirationDate }
        set {
            if self.rawAPIKeyExpirationDate != newValue {
                self.rawAPIKeyExpirationDate = newValue
            }
        }
    }
    
    
    private(set) var apiKeyStatus: APIKeyStatus? {
        get {
            guard let rawAPIKeyStatus else { return nil }
            guard let currentValue = APIKeyStatus(rawValue: Int(truncating: rawAPIKeyStatus)) else { assertionFailure(); return nil }
            return currentValue
        }
        set {
            guard let newValue else {
                if self.rawAPIKeyStatus != nil {
                    self.rawAPIKeyStatus = nil
                }
                return
            }
            let newAPIKeyStatus = NSNumber(integerLiteral: newValue.rawValue)
            if self.rawAPIKeyStatus != newAPIKeyStatus {
                self.rawAPIKeyStatus = newAPIKeyStatus
            }
        }
    }
    
    
    private(set) var apiPermissions: APIPermissions? {
        get {
            guard let rawAPIPermissions else { return nil }
            let currentValue = APIPermissions(rawValue: Int(truncating: rawAPIPermissions))
            return currentValue
        }
        set {
            guard let newValue else {
                if self.rawAPIPermissions != nil {
                    self.rawAPIPermissions = nil
                }
                return
            }
            let newAPIPermissions = NSNumber(integerLiteral: newValue.rawValue)
            if self.rawAPIPermissions != newAPIPermissions {
                self.rawAPIPermissions = newAPIPermissions
            }
        }
    }
    
    var apiKeyElements: APIKeyElements? {
        guard let apiKeyStatus, let apiPermissions else { return nil }
        return .init(
            status: apiKeyStatus,
            permissions: apiPermissions,
            expirationDate: apiKeyExpirationDate)
    }
    
    // MARK: - Initializer

    private convenience init(identity: ObvCryptoIdentity, within context: NSManagedObjectContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: ServerSession.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        self.rawAPIKeyExpirationDate = nil
        self.rawAPIKeyStatus = nil
        self.rawAPIPermissions = nil
        self.rawOwnedCryptoId = identity.getIdentity()
        self.token = nil
    }

}


// MARK: - Other methods

extension ServerSession {

    func resetSession() {
        if token != nil {
            token = nil
        }
    }
    
    
    func save(serverSessionToken: Data, apiKeyElements: APIKeyElements) {
        if self.token != serverSessionToken {
            self.token = serverSessionToken
        }
        if self.apiKeyStatus != apiKeyElements.status {
            self.apiKeyStatus = apiKeyElements.status
        }
        if self.apiPermissions != apiKeyElements.permissions {
            self.apiPermissions = apiKeyElements.permissions
        }
        if self.apiKeyExpirationDate != apiKeyElements.expirationDate {
            self.apiKeyExpirationDate = apiKeyElements.expirationDate
        }
    }

}


// MARK: - Convenience DB getters

extension ServerSession {

    private struct Predicate {
        fileprivate enum Key: String {
            case rawAPIKeyExpirationDate = "rawAPIKeyExpirationDate"
            case rawAPIKeyStatus = "rawAPIKeyStatus"
            case rawAPIPermissions = "rawAPIPermissions"
            case rawOwnedCryptoId = "rawOwnedCryptoId"
            case token = "token"
        }
        static func withOwnedCryptoId(_ ownedCryptoId: ObvCryptoIdentity) -> NSPredicate {
            NSPredicate(Key.rawOwnedCryptoId, EqualToData: ownedCryptoId.getIdentity())
        }
    }
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<ServerSession> {
        return NSFetchRequest<ServerSession>(entityName: ServerSession.entityName)
    }

    
    static func get(within context: NSManagedObjectContext, withIdentity cryptoIdentity: ObvCryptoIdentity) throws -> ServerSession? {
        let request: NSFetchRequest<ServerSession> = ServerSession.fetchRequest()
        request.predicate = Predicate.withOwnedCryptoId(cryptoIdentity)
        let item = (try context.fetch(request)).first
        return item
    }

    
    static func getOrCreate(within context: NSManagedObjectContext, withIdentity identity: ObvCryptoIdentity) throws -> ServerSession {
        if let serverSession = try get(within: context, withIdentity: identity) {
            return serverSession
        } else {
            return ServerSession(identity: identity, within: context)
        }
    }
    
    
    static func getAllServerSessions(within context: NSManagedObjectContext) throws -> [ServerSession] {
        let request: NSFetchRequest<ServerSession> = ServerSession.fetchRequest()
        request.fetchBatchSize = 100
        let items = try context.fetch(request)
        return items
    }
    

    static func deleteAllSessionsOfIdentity(_ ownedCryptoId: ObvCryptoIdentity, within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<ServerSession> = ServerSession.fetchRequest()
        request.predicate = Predicate.withOwnedCryptoId(ownedCryptoId)
        let items = try context.fetch(request)
        for item in items {
            context.delete(item)
        }
    }
    
    
    static func getAllTokens(within context: NSManagedObjectContext) throws -> [(ownedCryptoId: ObvCryptoIdentity, token: Data)] {
        let request: NSFetchRequest<ServerSession> = ServerSession.fetchRequest()
        request.fetchBatchSize = 100
        let items = try context.fetch(request)
        return items.compactMap { item in
            guard let token = item.token else { return nil }
            return try? (item.ownedCryptoIdentity, token)
        }
    }

}
