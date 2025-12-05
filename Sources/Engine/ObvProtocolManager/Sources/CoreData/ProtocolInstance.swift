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
import OSLog
import OlvidUtils
import ObvEncoder
import ObvTypes
import ObvCrypto
import ObvMetaManager


@objc(ProtocolInstance)
final class ProtocolInstance: NSManagedObject, ObvErrorMaker {
    
    // MARK: Internal constants
    
    private static let entityName = "ProtocolInstance"
    static let errorDomain = "ProtocolInstance"
    
    // MARK: Attributes
        
    @NSManaged private var cryptoProtocolRawId: Int
    @NSManaged private(set) var currentStateRawId: Int
    @NSManaged private var rawEncodedCurrentState: Data? // Non-optional in the model, raw value of an ObvEncoded
    @NSManaged private var rawOwnedCryptoIdentity: Data? // Non-optional in the model
    @NSManaged private var rawUID: Data? // Non-optional in the model
    
    // MARK: Other variables
    
    var cryptoProtocolId: CryptoProtocolId {
        get throws {
            guard let cryptoProtocolId = CryptoProtocolId(rawValue: cryptoProtocolRawId) else { assertionFailure(); throw ObvError.couldNotParseValue }
            return cryptoProtocolId
        }
    }
    
    var ownedCryptoIdentity: ObvCryptoIdentity {
        get throws(ObvError) {
            guard let rawOwnedCryptoIdentity else { assertionFailure(); throw .unexpectedNilValue }
            guard let ownedCryptoIdentity = ObvCryptoIdentity(from: rawOwnedCryptoIdentity) else { assertionFailure(); throw .couldNotParseValue }
            return ownedCryptoIdentity
        }
    }
    
    var uid: UID {
        get throws(ObvError) {
            guard let rawUID else { assertionFailure(); throw .unexpectedNilValue }
            guard let uid = UID(uid: rawUID) else { assertionFailure(); throw .couldNotParseValue }
            return uid
        }
    }
    
    var encodedCurrentState: ObvEncoded {
        get throws(ObvError) {
            guard let rawEncodedCurrentState else { assertionFailure(); throw .unexpectedNilValue }
            guard let encoded = ObvEncoded(withRawData: rawEncodedCurrentState) else { assertionFailure(); throw .couldNotParseValue }
            return encoded
        }
    }

    // MARK: - Initializer
    
    /// 2025-08-27: ok
    convenience init?(cryptoProtocolId: CryptoProtocolId, protocolInstanceUid: UID, ownedCryptoIdentity: ObvCryptoIdentity, initialState: ConcreteProtocolState, delegateManager: ObvProtocolDelegateManager, within obvContext: ObvContext) {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolInstance.entityName)
        
        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            return nil
        }
        
        // Check that no entry with the same `uid` and `contactIdentity` exists
        do {
            guard try !ProtocolInstance.exists(uid: protocolInstanceUid, ownedCryptoIdentity: ownedCryptoIdentity, within: obvContext.context) else {
                os_log("Cannot create a protocol instance with the same uid and owned identity twice", log: log, type: .error)
                return nil
            }
        } catch let error {
            os_log("%@", log: log, type: .fault, error.localizedDescription)
            return nil
        }
        let entityDescription = NSEntityDescription.entity(forEntityName: ProtocolInstance.entityName, in: obvContext.context)!
        
        // We check that the identity passed is indeed "owned" or, in the case of the owned identity transfer protocol, if the identity is ephemeral
        do {
            let identityIsOwned = try identityDelegate.isOwned(ownedCryptoIdentity, within: obvContext)
            guard identityIsOwned || (cryptoProtocolId == .ownedIdentityTransfer && ownedCryptoIdentity.serverURL == ObvConstants.ephemeralIdentityServerURL) else { return nil }
        } catch {
            assertionFailure()
            return nil
        }
        
        guard let encodedCurrentState = try? initialState.obvEncode() else { assertionFailure(); return nil }
        
        self.init(entity: entityDescription, insertInto: obvContext.context)
        
        self.cryptoProtocolRawId = cryptoProtocolId.rawValue
        self.currentStateRawId = initialState.rawId
        self.rawEncodedCurrentState = encodedCurrentState.rawData
        self.rawOwnedCryptoIdentity = ownedCryptoIdentity.getIdentity()
        self.rawUID = protocolInstanceUid.raw
        
    }
    
    private func deleteProtocolInstance() throws {
        guard let managedObjectContext else { assertionFailure(); throw ObvError.noContext }
        managedObjectContext.delete(self)
    }
    
}


// MARK: - Updating the current state

extension ProtocolInstance {
    
    func updateCurrentState(with state: ConcreteProtocolState) throws {
        self.rawEncodedCurrentState = try state.obvEncode().rawData
        self.currentStateRawId = state.rawId
    }
}


// MARK: - Convenience DB getters
extension ProtocolInstance {

    struct Predicate {
        enum Key: String {
            case cryptoProtocolRawId = "cryptoProtocolRawId"
            case currentStateRawId = "currentStateRawId"
            case rawEncodedCurrentState = "rawEncodedCurrentState"
            case rawOwnedCryptoIdentity = "rawOwnedCryptoIdentity"
            case rawUID = "rawUID"
        }
        static func withCryptoProtocolId(_ cryptoProtocolId: CryptoProtocolId) -> NSPredicate {
            NSPredicate(Key.cryptoProtocolRawId, EqualToInt: cryptoProtocolId.rawValue)
        }
        static func withUID(_ uid: UID) -> NSPredicate {
            NSPredicate(Key.rawUID, EqualToData: uid.raw)
        }
        static func withUIDDistinctFrom(_ uid: UID) -> NSPredicate {
            NSCompoundPredicate(notPredicateWithSubpredicate: withUID(uid))
        }
        static func withOwnedIdentity(_ ownedIdentity: ObvCryptoIdentity) -> NSPredicate {
            NSPredicate(Key.rawOwnedCryptoIdentity, EqualToData: ownedIdentity.getIdentity())
        }
        static func withCurrentStateRawId(_ currentStateRawId: Int) -> NSPredicate {
            NSPredicate(Key.currentStateRawId, EqualToInt: currentStateRawId)
        }
    }
    
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<ProtocolInstance> {
        return NSFetchRequest<ProtocolInstance>(entityName: ProtocolInstance.entityName)
    }

        
    static func get(cryptoProtocolId: CryptoProtocolId, uid: UID, ownedIdentity: ObvCryptoIdentity, within context: NSManagedObjectContext) throws -> ProtocolInstance? {
        let request: NSFetchRequest<ProtocolInstance> = ProtocolInstance.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withCryptoProtocolId(cryptoProtocolId),
            Predicate.withOwnedIdentity(ownedIdentity),
            Predicate.withUID(uid),
        ])
        request.fetchLimit = 1
        let item = try context.fetch(request).first
        return item
    }
    

    static func getAll(within context: NSManagedObjectContext) throws -> [ProtocolInstance] {
        let request: NSFetchRequest<ProtocolInstance> = ProtocolInstance.fetchRequest()
        let items = try context.fetch(request)
        return items
    }
    
    
    static func getAllOwnedCryptoIdsAssociatedToProtocolInstances(within context: NSManagedObjectContext) throws -> Set<ObvCryptoIdentity> {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: ProtocolInstance.entityName)
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = [Predicate.Key.rawOwnedCryptoIdentity.rawValue]
        request.returnsDistinctResults = true
        guard let results = try context.fetch(request) as? [[String: Data]] else {
            assertionFailure()
            throw ObvError.couldNotCastFetchedResult
        }
        let ownedCryptoIds: Set<ObvCryptoIdentity> = Set(results.compactMap {
            guard let identity = $0[Predicate.Key.rawOwnedCryptoIdentity.rawValue] else { assertionFailure(); return nil }
            return ObvCryptoIdentity(from: identity)
        })
        return ownedCryptoIds
    }
    
    
    /// This is called during bootstrap. It allows to remove certain protocol instances (for a limited set of protocol kinds) associated to an owned identity that could not be found in the identity manager database.
    static func batchDeleteAppropriateProtocolInstancesAssociatedToNonExistingOwnedIdentity(nonExistingOwnedCryptoId: ObvCryptoIdentity, within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<NSFetchRequestResult> = ProtocolInstance.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnedIdentity(nonExistingOwnedCryptoId),
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                Predicate.withCryptoProtocolId(.ownedDeviceDiscovery),
            ]),
        ])
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        deleteRequest.resultType = .resultTypeObjectIDs
        let result = try context.execute(deleteRequest) as? NSBatchDeleteResult
        // The previous call **immediately** updates the SQLite database
        // We merge the changes back to the current context
        if let objectIDArray = result?.result as? [NSManagedObjectID] {
            let changes = [NSUpdatedObjectsKey : objectIDArray]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])
        } else {
            assertionFailure()
        }
    }
    
    
    static func getAll(cryptoProtocolId: CryptoProtocolId, within context: NSManagedObjectContext) throws -> [ProtocolInstance] {
        let request: NSFetchRequest<ProtocolInstance> = ProtocolInstance.fetchRequest()
        request.predicate = Predicate.withCryptoProtocolId(cryptoProtocolId)
        let items = try context.fetch(request)
        return items
    }
    
    
    static func getAllPrimaryKeysOfOwnedIdentityTransferProtocolInstances(within context: NSManagedObjectContext) throws -> [(ownedCryptoIdentity: ObvCryptoIdentity, protocolInstanceUID: UID)] {
        let request: NSFetchRequest<ProtocolInstance> = ProtocolInstance.fetchRequest()
        request.predicate = Predicate.withCryptoProtocolId(.ownedIdentityTransfer)
        let items = try context.fetch(request)
        return items.compactMap { try? ($0.ownedCryptoIdentity, $0.uid) }
    }
    
    
    static func deleteProtocolInstance(uid: UID, ownedCryptoIdentity: ObvCryptoIdentity, within context: NSManagedObjectContext) throws {
        // We do not execute a batch delete since this method does not call the willSave/didSave methods, which are required.
        let request: NSFetchRequest<ProtocolInstance> = ProtocolInstance.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withUID(uid),
            Predicate.withOwnedIdentity(ownedCryptoIdentity),
        ])
        request.fetchLimit = 1
        request.propertiesToFetch = []
        guard let item = try context.fetch(request).first else { return }
        try item.deleteProtocolInstance()
    }
    
    
    static func count(within context: NSManagedObjectContext) -> Int {
        let request = NSFetchRequest<ProtocolInstance>(entityName: ProtocolInstance.entityName)
        return (try? context.count(for: request)) ?? 0
    }
    
    
    static func exists(uid: UID, ownedCryptoIdentity: ObvCryptoIdentity, within context: NSManagedObjectContext) throws -> Bool {
        let request: NSFetchRequest<ProtocolInstance> = ProtocolInstance.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withUID(uid),
            Predicate.withOwnedIdentity(ownedCryptoIdentity),
        ])
        request.fetchLimit = 1
        request.propertiesToFetch = []
        let item = try context.fetch(request).first
        return item != nil
    }
    
    
    static func exists(cryptoProtocolId: CryptoProtocolId, uid: UID, ownedIdentity: ObvCryptoIdentity, within context: NSManagedObjectContext) throws -> Bool {
        let request: NSFetchRequest<ProtocolInstance> = ProtocolInstance.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withCryptoProtocolId(cryptoProtocolId),
            Predicate.withOwnedIdentity(ownedIdentity),
            Predicate.withUID(uid),
        ])
        request.fetchLimit = 1
        request.propertiesToFetch = []
        let item = try context.fetch(request).first
        return item != nil
    }

    
    static func deleteProtocolInstancesInAFinalState(within context: NSManagedObjectContext) throws {

        for cryptoProtocolId in CryptoProtocolId.allCases {
            let finalStateRawIds = cryptoProtocolId.finalStateRawIds
            guard !finalStateRawIds.isEmpty else { continue }
            // Construct a predicate keeping only the ProtocolInstance values in a final state (for the current cryptoProtocolId)
            let inFinalState = NSCompoundPredicate(orPredicateWithSubpredicates: finalStateRawIds.map({ Predicate.withCurrentStateRawId($0) }))
            // Use the previous predicate to construct the "final" predicate, allowing to get all ProtocolInstances for this cryptoProtocolId that are in a final state
            let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Predicate.withCryptoProtocolId(cryptoProtocolId),
                inFinalState
            ])
            // Use the predicate to fetch and delete
            let request: NSFetchRequest<ProtocolInstance> = ProtocolInstance.fetchRequest()
            request.predicate = predicate
            request.propertiesToFetch = []
            request.fetchBatchSize = 100
            let items = try context.fetch(request)
            try items.forEach { try $0.deleteProtocolInstance() }
        }
        
    }
    
    
    static func deleteOwnedIdentityTransferProtocolInstances(within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<ProtocolInstance> = ProtocolInstance.fetchRequest()
        request.predicate = Predicate.withCryptoProtocolId(.ownedIdentityTransfer)
        request.propertiesToFetch = []
        request.fetchBatchSize = 100
        let items = try context.fetch(request)
        try items.forEach({ try $0.deleteProtocolInstance() })
    }
    
    
    static func deleteAllProtocolInstancesOfOwnedIdentity(_ ownedCryptoIdentity: ObvCryptoIdentity, withProtocolInstanceUidDistinctFrom protocolInstanceUid: UID, within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<ProtocolInstance> = ProtocolInstance.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnedIdentity(ownedCryptoIdentity),
            Predicate.withUIDDistinctFrom(protocolInstanceUid),
        ])
        request.fetchBatchSize = 100
        request.propertiesToFetch = []
        let items = try context.fetch(request)
        try items.forEach({ try $0.deleteProtocolInstance() })
    }
    
}


// MARK: - Errors

extension ProtocolInstance {
    
    enum ObvError: Error {
        case couldNotCastFetchedResult
        case noContext
        case couldNotParseValue
        case unexpectedNilValue
    }
    
}
