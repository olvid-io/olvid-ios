/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
    
    // MARK: Relationships
    
    @NSManaged private var linkBetweenProtocolInstance: LinkBetweenProtocolInstances? // Set when the instance starts a child protocol, and kept until the instance is deleted
    
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
            // Attributes
            case cryptoProtocolRawId = "cryptoProtocolRawId"
            case currentStateRawId = "currentStateRawId"
            case rawEncodedCurrentState = "rawEncodedCurrentState"
            case rawOwnedCryptoIdentity = "rawOwnedCryptoIdentity"
            case rawUID = "rawUID"
            // Relationships
            case linkBetweenProtocolInstance = "linkBetweenProtocolInstance" // Set when the instance starts a child protocol, and kept until the instance is deleted
        }
        static func withCryptoProtocolId(_ cryptoProtocolId: CryptoProtocolId) -> NSPredicate {
            NSPredicate(Key.cryptoProtocolRawId, EqualToInt: cryptoProtocolId.rawValue)
        }
        static func withUID(_ uid: UID) -> NSPredicate {
            withUID(uid.raw)
        }
        static func withUID(_ rawUID: Data) -> NSPredicate {
            NSPredicate(Key.rawUID, EqualToData: rawUID)
        }
        static func withUIDDistinctFrom(_ uid: UID) -> NSPredicate {
            NSCompoundPredicate(notPredicateWithSubpredicate: withUID(uid))
        }
        static func withOwnedIdentity(_ ownedIdentity: ObvCryptoIdentity) -> NSPredicate {
            withOwnedIdentity(ownedIdentity.getIdentity())
        }
        static func withOwnedIdentity(_ ownedIdentity: Data) -> NSPredicate {
            NSPredicate(Key.rawOwnedCryptoIdentity, EqualToData: ownedIdentity)
        }
        static func withCurrentStateRawId(_ currentStateRawId: Int) -> NSPredicate {
            NSPredicate(Key.currentStateRawId, EqualToInt: currentStateRawId)
        }
        static func withObjectIDIn(_ objectIDs: [NSManagedObjectID]) -> NSPredicate {
            NSPredicate(withObjectIDIn: objectIDs)
        }
        /// The two protocols that start a device discovery as a child protocol, each in the state where it waits for that child.
        static var waitingForADeviceDiscoveryChild: NSPredicate {
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSCompoundPredicate(andPredicateWithSubpredicates: [
                    withCryptoProtocolId(.contactDeviceDiscovery),
                    withCurrentStateRawId(ContactDeviceDiscoveryProtocol.StateId.waitingForChildProtocol.rawValue),
                ]),
                NSCompoundPredicate(andPredicateWithSubpredicates: [
                    withCryptoProtocolId(.keycloakContactAddition),
                    withCurrentStateRawId(KeycloakContactAdditionProtocol.StateId.waitingForDeviceDiscovery.rawValue),
                ]),
            ])
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
        request.includesPropertyValues = false
        guard let item = try context.fetch(request).first else { return }
        try item.deleteProtocolInstance()
    }
    
    
    static func count(within context: NSManagedObjectContext) -> Int {
        let request = NSFetchRequest<ProtocolInstance>(entityName: ProtocolInstance.entityName)
        return (try? context.count(for: request)) ?? 0
    }
    

    /// How many rows there are, per protocol, and how many belong to a protocol id we do not recognise.
    ///
    /// **One grouped query rather than one count per protocol.** There are two dozen protocols, so asking each in turn would be two dozen passes over the
    /// table — and though this entity carries `byCryptoProtocolRawIdIndex`, so each of those passes would be cheap, two dozen of them are not. A `GROUP BY` on the raw id answers all of them at once,
    /// materialising nothing.
    ///
    /// The unrecognised rows are returned rather than dropped: the raw ids have gaps, two protocols having been retired, and a row quietly discarded would
    /// make the per-protocol figures fail to add up to the total — which is the one piece of arithmetic a reader of these figures can actually perform.
    static func countPerCryptoProtocolId(within context: NSManagedObjectContext) throws -> (perProtocol: [CryptoProtocolId: Int], unrecognised: Int) {

        let rawIdKey = Predicate.Key.cryptoProtocolRawId.rawValue
        let countKey = "count"

        let countExpression = NSExpressionDescription()
        countExpression.name = countKey
        countExpression.expression = NSExpression(forFunction: "count:", arguments: [NSExpression(forKeyPath: rawIdKey)])
        countExpression.expressionResultType = .integer64AttributeType

        let request = NSFetchRequest<NSDictionary>(entityName: ProtocolInstance.entityName)
        request.resultType = .dictionaryResultType
        request.propertiesToGroupBy = [rawIdKey]
        request.propertiesToFetch = [rawIdKey, countExpression]

        var perProtocol = [CryptoProtocolId: Int]()
        var unrecognised = 0

        for item in try context.fetch(request) {
            guard let count = (item[countKey] as? NSNumber)?.intValue else { assertionFailure(); continue }
            guard let rawId = (item[rawIdKey] as? NSNumber)?.intValue, let cryptoProtocolId = CryptoProtocolId(rawValue: rawId) else {
                unrecognised += count
                continue
            }
            perProtocol[cryptoProtocolId, default: 0] += count
        }

        return (perProtocol, unrecognised)

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
    
    
    /// Returns `true` iff an instance with this UID exists under this owned identity.
    ///
    /// The parameters are the raw stored values, so that a caller asking this of many instances in a row does not have to parse an
    /// owned identity for each of them.
    static func exists(rawUID: Data, rawOwnedCryptoIdentity: Data, within context: NSManagedObjectContext) throws -> Bool {
        let request: NSFetchRequest<ProtocolInstance> = ProtocolInstance.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withUID(rawUID),
            Predicate.withOwnedIdentity(rawOwnedCryptoIdentity),
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
            request.includesPropertyValues = false
            request.fetchBatchSize = 100
            let items = try context.fetch(request)
            try items.forEach { try $0.deleteProtocolInstance() }
        }
        
    }
    
    
    static func deleteOwnedIdentityTransferProtocolInstances(within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<ProtocolInstance> = ProtocolInstance.fetchRequest()
        request.predicate = Predicate.withCryptoProtocolId(.ownedIdentityTransfer)
        request.includesPropertyValues = false
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
        request.includesPropertyValues = false
        let items = try context.fetch(request)
        try items.forEach({ try $0.deleteProtocolInstance() })
    }
    
    
    private static let maxNumberOfCandidatesPerFetch = 100
    
    
    /// Returns the instances of the two protocols that start a device discovery as a child protocol, waiting for a child that no longer
    /// exists, with no message waiting either for that child or for the instance itself, so that nothing can ever make them progress.
    ///
    /// This is the first of the two passes of the sweep that deletes such instances, and may be performed on any background context: what
    /// it returns is a list of candidates rather than a decision. The second pass, which decides and deletes, is
    /// ``deleteContactDeviceDiscoveryAndKeycloakContactAdditionInstancesWaitingForAChildThatWillNeverAnswer(among:within:)``.
    static func getContactDeviceDiscoveryAndKeycloakContactAdditionInstancesWaitingForAChildThatWillNeverAnswer(
        within context: NSManagedObjectContext
    ) throws -> [NSManagedObjectID] {
        return try instancesWaitingForAChildThatWillNeverAnswer(among: nil, within: context)
            .map(\.objectID)
    }
    
    
    /// Deletes those of the `candidates` that still wait for a child that will never answer, and returns how many were deleted, per
    /// protocol. Each instance takes its link row with it, the relationship cascading.
    ///
    /// This is the second of the two passes, and must be performed on the queue running the protocol steps. It applies the rule again
    /// rather than trusting the candidates it is given: the first pass compares three entities over several fetches, between which a
    /// protocol step can commit, so each of its reads may land just after what it was looking for has moved. On the protocol queue no step
    /// can run at all, so this answer holds. Without this second pass, a contact device discovery could lose its result, and a keycloak
    /// contact addition the contact it was about to create.
    static func deleteContactDeviceDiscoveryAndKeycloakContactAdditionInstancesWaitingForAChildThatWillNeverAnswer(
        among candidates: [NSManagedObjectID],
        within context: NSManagedObjectContext
    ) throws -> [CryptoProtocolId: Int] {
        
        guard !candidates.isEmpty else { return [:] }
        
        // The candidates go into an SQL "IN" statement, whose size is limited, so they are asked for in slices
        
        var numberOfDeletedInstancesPerProtocol = [CryptoProtocolId: Int]()
        
        for slice in candidates.toSlices(ofMaxSize: maxNumberOfCandidatesPerFetch) {
            
            let items = try instancesWaitingForAChildThatWillNeverAnswer(among: slice, within: context)
            
            for item in items {
                
                // The protocol is read before the deletion, and counted after it, so that the figures report what was deleted
                
                let cryptoProtocolId = try? item.cryptoProtocolId
                
                do {
                    try item.deleteProtocolInstance()
                } catch {
                    assertionFailure() // In production, continue anyway
                    continue
                }
                
                if let cryptoProtocolId {
                    numberOfDeletedInstancesPerProtocol[cryptoProtocolId, default: 0] += 1
                }
                
            }
            
        }
        
        return numberOfDeletedInstancesPerProtocol
        
    }
    
    
    /// The rule both passes share: among every instance of the two protocols in its waiting state, or among the `candidates` alone, those
    /// that nothing can make progress on. Every way out of the loop below keeps the instance, so one is returned only on positive evidence
    /// that neither its child nor a message for either end is left to answer it.
    private static func instancesWaitingForAChildThatWillNeverAnswer(among candidates: [NSManagedObjectID]?, within context: NSManagedObjectContext) throws -> [ProtocolInstance] {
        
        var itemsToReturn = [ProtocolInstance]()
        
        let subpredicates: [NSPredicate?] = [
            Predicate.waitingForADeviceDiscoveryChild,
            candidates.map(Predicate.withObjectIDIn),
        ]
        
        let request: NSFetchRequest<ProtocolInstance> = ProtocolInstance.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates.compactMap { $0 })
        request.relationshipKeyPathsForPrefetching = [Predicate.Key.linkBetweenProtocolInstance.rawValue]
        let items = try context.fetch(request)
                
        for item in items {
            
            guard let rawOwnedCryptoIdentity = item.rawOwnedCryptoIdentity, let rawUID = item.rawUID else { assertionFailure(); continue }
            
            // A parent holding no link waits for nothing, and is nonetheless kept. Deleting it is the one decision this method could
            // make on no evidence at all, so a selection that was one day widened by mistake would empty the table through this
            // branch alone. Both protocols create their link in the save that leaves them waiting, so such a parent is not expected
            
            guard let link = item.linkBetweenProtocolInstance else { continue }
            
            guard let childProtocolInstanceUid = try? link.childProtocolInstanceUid else { continue }
            
            // The child's instance exists, so this parent waits for something that can still answer it
            
            guard try !ProtocolInstance.exists(rawUID: childProtocolInstanceUid.raw, rawOwnedCryptoIdentity: rawOwnedCryptoIdentity, within: context) else { continue }
            
            // The child's instance may not exist yet: the link and the child's first message are saved together, and the instance
            // is created when that message is processed
            
            guard try !ReceivedMessage.exists(rawProtocolInstanceUid: childProtocolInstanceUid.raw, rawOwnedCryptoIdentity: rawOwnedCryptoIdentity, within: context) else { continue }
            
            // The child may just have finished: the save that deletes it posts its result to this parent, which waits as a message
            // carrying the parent's own UID. Deleting the parent now would lose that result
            
            guard try !ReceivedMessage.exists(rawProtocolInstanceUid: rawUID, rawOwnedCryptoIdentity: rawOwnedCryptoIdentity, within: context) else { continue }
            
            // Neither the child nor a message for the child or for this parent exists, so nothing can make this parent progress
            
            itemsToReturn.append(item)
            
        }

        return itemsToReturn
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
