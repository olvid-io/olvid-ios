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
import os.log
import CoreData
import ObvMetaManager
import ObvEncoder
import ObvCrypto
import ObvTypes
import OlvidUtils


@objc(PendingServerQuery)
final class PendingServerQuery: NSManagedObject, ObvManagedObject {

    private static let entityName = "PendingServerQuery"

    // MARK: Attributes
    
    @NSManaged private(set) var isWebSocket: Bool
    @NSManaged private var rawCreationDate: Date? // Expected to be non-nil
    @NSManaged private var rawEncodedElements: Data
    @NSManaged private var rawEncodedQueryType: Data
    @NSManaged private var rawEncodedResponseType: Data?
    @NSManaged private var rawOwnedIdentity: Data
    
    
    // MARK: Accessors
    
    private(set) var encodedElements: ObvEncoded {
        get { ObvEncoded(withRawData: rawEncodedElements)! }
        set { self.rawEncodedElements = newValue.rawData }
    }
    
    var creationDate: Date {
        assert(rawCreationDate != nil)
        return rawCreationDate ?? .distantPast
    }
    
    private(set) var queryType: ServerQuery.QueryType {
        get { ServerQuery.QueryType(ObvEncoded(withRawData: rawEncodedQueryType)!)! }
        set { self.rawEncodedQueryType = newValue.obvEncode().rawData }
    }
    
    
    var responseType: ServerResponse.ResponseType? {
        get {
            guard let rawEncodedResponseType else { return nil }
            guard let encodedResponseType = ObvEncoded(withRawData: rawEncodedResponseType),
                  let responseType = ServerResponse.ResponseType(encodedResponseType) else { assertionFailure(); return nil }
            return responseType
        }
        set {
            guard let newValue else { assertionFailure("We do not expect to set a nil value"); return }
            self.rawEncodedResponseType = newValue.obvEncode().rawData
        }
    }
    
    
    var ownedIdentity: ObvCryptoIdentity {
        get throws {
            guard let ownedCryptoIdentity = ObvCryptoIdentity(from: rawOwnedIdentity) else {
                if !isDeleted { assertionFailure() }
                throw ObvError.couldNotParseOwnedIdentity
            }
            return ownedCryptoIdentity
        }
    }
    
    
    // MARK: Other variables

    weak var delegateManager: ObvNetworkFetchDelegateManager?
    var obvContext: ObvContext?

    
    // MARK: - Initializer

    convenience init(serverQuery: ServerQuery, delegateManager: ObvNetworkFetchDelegateManager, within obvContext: ObvContext) {

        let entityDescription = NSEntityDescription.entity(forEntityName: PendingServerQuery.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)

        self.encodedElements = serverQuery.encodedElements
        self.queryType = serverQuery.queryType
        self.rawOwnedIdentity = serverQuery.ownedIdentity.getIdentity()
        self.delegateManager = delegateManager
        self.obvContext = obvContext
        self.isWebSocket = serverQuery.isWebSocket
        self.rawCreationDate = Date.now

    }

}


// MARK: - Other functions

extension PendingServerQuery {

    func deletePendingServerQuery(within obvContext: ObvContext) {
        guard self.managedObjectContext == obvContext.context else {
            assertionFailure("Unexpected context")
            return
        }
        self.obvContext = obvContext
        obvContext.delete(self)
    }

}

// MARK: - Convenience DB getters

extension PendingServerQuery {
    
    struct Predicate {
        enum Key: String {
            case isWebSocket = "isWebSocket"
            case rawCreationDate = "rawCreationDate"
            case rawEncodedElements = "rawEncodedElements"
            case rawEncodedQueryType = "rawEncodedQueryType"
            case rawEncodedResponseType = "rawEncodedResponseType"
            case rawOwnedIdentity = "rawOwnedIdentity"
        }
        static func withOwnedCryptoIdentity(_ ownedCryptoIdentity: ObvCryptoIdentity) -> NSPredicate {
            NSPredicate(Key.rawOwnedIdentity, EqualToData: ownedCryptoIdentity.getIdentity())
        }
        static func whereIsWebSocketIs(_ isWebSocket: Bool) -> NSPredicate {
            NSPredicate(Key.isWebSocket, is: isWebSocket)
        }
        static func withObjectID(_ objectID: NSManagedObjectID) -> NSPredicate {
            NSPredicate(withObjectID: objectID)
        }
    }

    
    @nonobjc static func fetchRequest() -> NSFetchRequest<PendingServerQuery> {
        NSFetchRequest<PendingServerQuery>(entityName: PendingServerQuery.entityName)
    }

    
    static func get(objectId: NSManagedObjectID, delegateManager: ObvNetworkFetchDelegateManager, within obvContext: ObvContext) throws -> PendingServerQuery? {
        let request: NSFetchRequest<PendingServerQuery> = PendingServerQuery.fetchRequest()
        request.predicate = Predicate.withObjectID(objectId)
        request.fetchLimit = 1
        let item = try obvContext.fetch(request).first
        item?.delegateManager = delegateManager
        item?.obvContext = obvContext
        return item
    }
    

    enum BoolOrAny {
        case any
        case bool(_ value: Bool)
    }
    
    
    static func getAllServerQuery(for identity: ObvCryptoIdentity, isWebSocket: BoolOrAny, delegateManager: ObvNetworkFetchDelegateManager, within obvContext: ObvContext) throws -> [PendingServerQuery] {
        let request: NSFetchRequest<PendingServerQuery> = PendingServerQuery.fetchRequest()
        var subpredicates = [Predicate.withOwnedCryptoIdentity(identity)]
        switch isWebSocket {
        case .any:
            break
        case .bool(let isWebSocket):
            subpredicates += [Predicate.whereIsWebSocketIs(isWebSocket)]
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)
        let items = try obvContext.fetch(request)
        items.forEach { item in
            item.delegateManager = delegateManager
            item.obvContext = obvContext
        }
        return items
    }

    
    static func getAllServerQuery(isWebSocket: BoolOrAny, delegateManager: ObvNetworkFetchDelegateManager, within obvContext: ObvContext) throws -> [PendingServerQuery] {
        let request: NSFetchRequest<PendingServerQuery> = PendingServerQuery.fetchRequest()
        request.fetchBatchSize = 1_000
        switch isWebSocket {
        case .any:
            break
        case .bool(let isWebSocket):
            request.predicate = Predicate.whereIsWebSocketIs(isWebSocket)
        }
        let items = try obvContext.fetch(request)
        items.forEach { item in
            item.delegateManager = delegateManager
            item.obvContext = obvContext
        }
        return items
    }
    
    
    static func deleteAllServerQuery(for identity: ObvCryptoIdentity, delegateManager: ObvNetworkFetchDelegateManager, within obvContext: ObvContext) throws {
        let serverQueries = try getAllServerQuery(for: identity, isWebSocket: .any, delegateManager: delegateManager, within: obvContext)
        for serverQuery in serverQueries {
            serverQuery.deletePendingServerQuery(within: obvContext)
        }
    }

    
    static func deleteAllWebSocketServerQuery(within obvContext: ObvContext) throws {
        let request: NSFetchRequest<PendingServerQuery> = PendingServerQuery.fetchRequest()
        request.predicate = Predicate.whereIsWebSocketIs(true)
        let items = try obvContext.fetch(request)
        items.forEach { item in
            item.deletePendingServerQuery(within: obvContext)
        }
    }
    
}


// MARK: - Errors

extension PendingServerQuery {
    
    enum ObvError: Error {
        case theDelegateManagerIsNil
        case couldNotFindPendingServerQuery
        case couldNotParseOwnedIdentity
    }
    
}

// MARK: - Managing Change Events

extension PendingServerQuery {

    override func didSave() {
        super.didSave()

        guard let delegateManager = delegateManager else {
            let log = OSLog.init(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: PendingServerQuery.entityName)
            os_log("The delegate manager is not set", log: log, type: .fault)
            return
        }

        if isInserted, let flowId = self.obvContext?.flowId {
            let objectID = self.objectID
            let isWebSocket = self.isWebSocket
            Task { await delegateManager.networkFetchFlowDelegate.newPendingServerQueryToProcessWithObjectId(objectID, isWebSocket: isWebSocket, flowId: flowId) }
        }
    }

}
