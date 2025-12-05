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
import OSLog
import CoreData
import ObvMetaManager
import ObvEncoder
import ObvCrypto
import ObvTypes


@objc(PendingServerQuery)
final class PendingServerQuery: NSManagedObject {

    private static let entityName = "PendingServerQuery"
    private static let logger = Logger(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: PendingServerQuery.entityName)

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
    
    // MARK: - Observers
    
    private static var observersHolder = ObserversHolder()
    
    public static func addObvObserver(_ newObserver: PendingServerQueryObserver) async {
        await observersHolder.addObserver(newObserver)
    }

    // MARK: - Initializer

    private convenience init(serverQuery: ServerQuery, within context: NSManagedObjectContext) {

        let entityDescription = NSEntityDescription.entity(forEntityName: PendingServerQuery.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        self.encodedElements = serverQuery.encodedElements
        self.queryType = serverQuery.queryType
        self.rawOwnedIdentity = serverQuery.ownedIdentity.getIdentity()
        self.isWebSocket = serverQuery.isWebSocket
        self.rawCreationDate = Date.now

    }
    
    
    static func createPendingServerQuery(serverQuery: ServerQuery, within context: NSManagedObjectContext) -> Self {
        let newPendingServerQuery = Self.init(serverQuery: serverQuery, within: context)
        return newPendingServerQuery
    }

}


// MARK: - Other functions

extension PendingServerQuery {

    func deletePendingServerQuery() throws {
        guard let context = self.managedObjectContext else {
            assertionFailure()
            throw ObvError.noContext
        }
        context.delete(self)
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

    
    static func get(objectId: NSManagedObjectID, within context: NSManagedObjectContext) throws -> PendingServerQuery? {
        let request: NSFetchRequest<PendingServerQuery> = PendingServerQuery.fetchRequest()
        request.predicate = Predicate.withObjectID(objectId)
        request.fetchLimit = 1
        let item = try context.fetch(request).first
        return item
    }
    

    enum BoolOrAny {
        case any
        case bool(_ value: Bool)
    }
    
    
    static func getAllServerQuery(for identity: ObvCryptoIdentity, isWebSocket: BoolOrAny, within context: NSManagedObjectContext) throws -> [PendingServerQuery] {
        let request: NSFetchRequest<PendingServerQuery> = PendingServerQuery.fetchRequest()
        var subpredicates = [Predicate.withOwnedCryptoIdentity(identity)]
        switch isWebSocket {
        case .any:
            break
        case .bool(let isWebSocket):
            subpredicates += [Predicate.whereIsWebSocketIs(isWebSocket)]
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)
        request.fetchBatchSize = 1_000
        let items = try context.fetch(request)
        return items
    }

    
    static func getAllServerQuery(isWebSocket: BoolOrAny, within context: NSManagedObjectContext) throws -> [PendingServerQuery] {
        let request: NSFetchRequest<PendingServerQuery> = PendingServerQuery.fetchRequest()
        request.fetchBatchSize = 1_000
        switch isWebSocket {
        case .any:
            break
        case .bool(let isWebSocket):
            request.predicate = Predicate.whereIsWebSocketIs(isWebSocket)
        }
        let items = try context.fetch(request)
        return items
    }
    
    
    static func deleteAllServerQuery(for identity: ObvCryptoIdentity, within context: NSManagedObjectContext) throws {
        let serverQueries = try getAllServerQuery(for: identity, isWebSocket: .any, within: context)
        for serverQuery in serverQueries {
            do {
                try serverQuery.deletePendingServerQuery()
            } catch {
                assertionFailure() // In production, continue with the next server query
            }
        }
    }

    
    static func deleteAllWebSocketServerQuery(within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<PendingServerQuery> = PendingServerQuery.fetchRequest()
        request.predicate = Predicate.whereIsWebSocketIs(true)
        let items = try context.fetch(request)
        items.forEach { item in
            do {
                try item.deletePendingServerQuery()
            } catch {
                assertionFailure() // In production, continue with the next server query
            }
        }
    }
    
}


// MARK: - Errors

extension PendingServerQuery {
    
    enum ObvError: Error {
        case couldNotFindPendingServerQuery
        case couldNotParseOwnedIdentity
        case noContext
    }
    
}

// MARK: - Managing Change Events

extension PendingServerQuery {

    override func didSave() {
        super.didSave()

        if self.isInserted {
            let objectID = self.objectID
            let isWebSocket = self.isWebSocket
            Task { await Self.observersHolder.aPendingServerQueryWasInserted(objectID: objectID, isWebSocket: isWebSocket) }
        }
        
    }

}


// MARK: - PendingServerQuery observers

public protocol PendingServerQueryObserver: AnyObject {
    func aPendingServerQueryWasInserted(objectID: NSManagedObjectID, isWebSocket: Bool) async
}


private actor ObserversHolder: PendingServerQueryObserver {
    
    private var observers = [WeakObserver]()
    
    private final class WeakObserver {
        private(set) weak var value: PendingServerQueryObserver?
        init(value: PendingServerQueryObserver?) {
            self.value = value
        }
    }
    
    func addObserver(_ newObserver: PendingServerQueryObserver) {
        self.observers.append(.init(value: newObserver))
    }
    
    // Implementing PersistedDiscussionObserver
    
    func aPendingServerQueryWasInserted(objectID: NSManagedObjectID, isWebSocket: Bool) async {
        await withTaskGroup(of: Void.self) { taskGroup in
            for observer in observers.compactMap(\.value) {
                taskGroup.addTask {
                    await observer.aPendingServerQueryWasInserted(objectID: objectID, isWebSocket: isWebSocket)
                }
            }
        }
    }
    
}
