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
import os.log
import ObvTypes
import ObvCrypto
import OlvidUtils


@objc(ServerSession)
final class ServerSession: NSManagedObject, ObvManagedObject, ObvErrorMaker {

    // MARK: Internal constants

    private static let entityName = "ServerSession"
    static let errorDomain = "ServerSession"
    private static let challengeKey = "challenge"
    private static let cryptoIdentityKey = "cryptoIdentity"
    private static let responseKey = "response"
    private static let tokenKey = "token"

    // MARK: Attributes

    @NSManaged private(set) var cryptoIdentity: ObvCryptoIdentity
    @NSManaged var nonce: Data?
    @NSManaged private(set) var response: Data? 
    @NSManaged var token: Data?

    // MARK: Other variables

    var obvContext: ObvContext?

    // MARK: - Initializer

    convenience init(identity: ObvCryptoIdentity, within obvContext: ObvContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: ServerSession.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        self.cryptoIdentity = identity
    }

}


// MARK: - Other methods

extension ServerSession {

    // This method sets the identity's server session token to None only if its current value is equal to the token value passed as a parameter. This is used in many operations: at the beginning of their execute, they keep a local copy of the token. If they cancel because the token they use is invalid, they call this method to clean the identity's session. This way of doing things allows to make sure that the operation does not clean a fresh token that would have been create while the operation was executing.
    func deleteToken(ifEqualTo token: Data) {
        if self.token != nil, self.token! == token {
            self.token = nil
        }
    }

    static func getToken(within obvContext: ObvContext, forIdentity identity: ObvCryptoIdentity) throws -> Data? {
        var token: Data? = nil
        try obvContext.performAndWaitOrThrow {
            let serverSession = try ServerSession.get(within: obvContext, withIdentity: identity)
            token = serverSession?.token
        }
        return token
    }

    func resetSession() {
        nonce = nil
        response = nil
        token = nil
    }

    func store(response: Data, ifCurrentNonceIs serverNonce: Data) throws {
        guard let localNonce = nonce else { throw Self.makeError(message: "No local nonce") }
        guard serverNonce == localNonce else { throw Self.makeError(message: "server nonce is distinct from local nonce") }
        self.response = response
    }

    func store(token: Data, ifCurrentNonceIs serverNonce: Data) throws {
        guard let localNonce = nonce else { throw Self.makeError(message: "No local nonce") }
        guard serverNonce == localNonce else { throw Self.makeError(message: "server nonce is distinct from local nonce") }
        self.token = token
    }
}


// MARK: - Convenience DB getters

extension ServerSession {

    @nonobjc class func fetchRequest() -> NSFetchRequest<ServerSession> {
        return NSFetchRequest<ServerSession>(entityName: ServerSession.entityName)
    }

    class func get(within obvContext: ObvContext, withIdentity cryptoIdentity: ObvCryptoIdentity) throws -> ServerSession? {
        let request: NSFetchRequest<ServerSession> = ServerSession.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", ServerSession.cryptoIdentityKey, cryptoIdentity)
        let item = (try obvContext.fetch(request)).first
        return item
    }

    class func getOrCreate(within obvContext: ObvContext, withIdentity identity: ObvCryptoIdentity) throws -> ServerSession {
        if let serverSession = try get(within: obvContext, withIdentity: identity) {
            return serverSession
        } else {
            return ServerSession(identity: identity, within: obvContext)
        }
    }

    static func delete(ifTokenIs token: Data, for identity: ObvCryptoIdentity, within obvContext: ObvContext) {
        let request: NSFetchRequest<ServerSession> = ServerSession.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", ServerSession.cryptoIdentityKey, identity)
        if let item = (try? obvContext.fetch(request))?.first {
            if item.token == token {
                obvContext.delete(item)
            }
        }
    }
    
    static func deleteAllSessionsOfIdentity(_ identity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        let request: NSFetchRequest<ServerSession> = ServerSession.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", ServerSession.cryptoIdentityKey, identity)
        let items = try obvContext.fetch(request)
        for item in items {
            obvContext.delete(item)
        }
    }
}
