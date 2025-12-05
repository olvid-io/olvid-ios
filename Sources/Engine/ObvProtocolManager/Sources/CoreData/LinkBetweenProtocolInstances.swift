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
import ObvEncoder
import ObvTypes
import ObvCrypto
import OlvidUtils


@objc(LinkBetweenProtocolInstances)
final class LinkBetweenProtocolInstances: NSManagedObject {

    // MARK: Internal constants
    
    private static let entityName = "LinkBetweenProtocolInstances"
    
    // MARK: Attributes
    
    // Both the child and parent protocol instances share the same owned identity
    
    @NSManaged private(set) var expectedChildStateRawId: Int
    @NSManaged private(set) var messageToSendRawId: Int // When the child reaches the expected state, a message with this raw id will be sent to the parent protocol
    @NSManaged private var rawChildProtocolInstanceUid: Data? // Non-optional in the model
    
    // MARK: Relationships
    
    @NSManaged private(set) var parentProtocolInstance: ProtocolInstance? // Non-optional in the model
    
    // MARK: Other variables
    
    var protocolInstancesOwnedIdentity: ObvCryptoIdentity {
        get throws {
            guard let parentProtocolInstance else { assertionFailure(); throw ObvError.unexpectedNilValue }
            return try parentProtocolInstance.ownedCryptoIdentity
        }
    }
    
    var childProtocolInstanceUid: UID {
        get throws {
            guard let rawChildProtocolInstanceUid else { assertionFailure(); throw ObvError.unexpectedNilValue }
            guard let uid = UID(uid: rawChildProtocolInstanceUid) else { assertionFailure(); throw ObvError.couldNotParseValue }
            return uid
        }
    }
    
    // MARK: - Initializer
    
    /// 2025-08-27: ok
    convenience init?(parentProtocolInstance: ProtocolInstance, childProtocolInstanceUid: UID, expectedChildStateRawId: Int, messageToSendRawId: Int) {
        
        guard let context = parentProtocolInstance.managedObjectContext else { return nil }
        let entityDescription = NSEntityDescription.entity(forEntityName: LinkBetweenProtocolInstances.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        
        self.expectedChildStateRawId = expectedChildStateRawId
        self.messageToSendRawId = messageToSendRawId
        self.rawChildProtocolInstanceUid = childProtocolInstanceUid.raw
        
        self.parentProtocolInstance = parentProtocolInstance
        
    }

    enum ObvError: Error {
        case unexpectedNilValue
        case couldNotParseValue
    }
    
}


// MARK: - Convenience DB getters
extension LinkBetweenProtocolInstances {
    
    private struct Predicate {
        enum Key: String {
            // Attributes
            case expectedChildStateRawId = "expectedChildStateRawId"
            case messageToSendRawId = "messageToSendRawId"
            case rawChildProtocolInstanceUid = "rawChildProtocolInstanceUid"
            // Relationships
            case parentProtocolInstance = "parentProtocolInstance"
        }
        static func withChildProtocolInstanceUid(_ childProtocolInstanceUid: UID) -> NSPredicate {
            NSPredicate(Key.rawChildProtocolInstanceUid, EqualToData: childProtocolInstanceUid.raw)
        }
        static func withOwnedIdentity(_ ownedIdentity: ObvCryptoIdentity) -> NSPredicate {
            let rawKey: String = [
                Key.parentProtocolInstance.rawValue,
                ProtocolInstance.Predicate.Key.rawOwnedCryptoIdentity.rawValue,
            ].joined(separator: ".")
            return NSPredicate(rawKey, EqualToData: ownedIdentity.getIdentity())
        }
        static func withExpectedChildState(_ expectedChildState: ConcreteProtocolState) -> NSPredicate {
            NSPredicate(Key.expectedChildStateRawId, EqualToInt: expectedChildState.rawId)
        }
        static func withParentProtocolInstanceUid(_ parentProtocolInstanceUid: UID) -> NSPredicate {
            let rawKey: String = [
                Key.parentProtocolInstance.rawValue,
                ProtocolInstance.Predicate.Key.rawUID.rawValue,
            ].joined(separator: ".")
            return NSPredicate(rawKey, EqualToData: parentProtocolInstanceUid.raw)
        }
    }

    
    @nonobjc class func fetchRequest() -> NSFetchRequest<LinkBetweenProtocolInstances> {
        return NSFetchRequest<LinkBetweenProtocolInstances>(entityName: LinkBetweenProtocolInstances.entityName)
    }
    
    
    static func getGenericProtocolMessageToSendWhenChildProtocolInstance(withUid childUid: UID, andOwnedIdentity childOwnedCryptoIdentity: ObvCryptoIdentity, reachesState childState: ConcreteProtocolState, within context: NSManagedObjectContext) throws -> [GenericProtocolMessageToSend] {
        let request: NSFetchRequest<LinkBetweenProtocolInstances> = LinkBetweenProtocolInstances.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withChildProtocolInstanceUid(childUid),
            Predicate.withOwnedIdentity(childOwnedCryptoIdentity),
            Predicate.withExpectedChildState(childState),
        ])
        request.fetchBatchSize = 1_000
        guard let links = try? context.fetch(request) else { return [GenericProtocolMessageToSend]() }
        let encodedInputs = try ChildToParentProtocolMessageInputs(childProtocolInstanceUid: childUid,
                                                                   childProtocolInstanceReachedState: childState).toListOfEncoded()
        let messages: [GenericProtocolMessageToSend] = links.compactMap { link in
            do {
                guard let parentProtocolInstance = link.parentProtocolInstance else { return nil }
                return GenericProtocolMessageToSend(channelType: .local(ownedIdentity: try parentProtocolInstance.ownedCryptoIdentity),
                                                    cryptoProtocolId: try parentProtocolInstance.cryptoProtocolId,
                                                    protocolInstanceUid: try parentProtocolInstance.uid,
                                                    protocolMessageRawId: link.messageToSendRawId,
                                                    encodedInputs: encodedInputs)
            } catch {
                assertionFailure()
                return nil
            }
        }
        return messages
    }
    
    
    // Normaly, there should be only one parent protocol of a given protocol. But there might be multiple links, since the parent might require to be notified at various states of the child protocol.
    static func getAllLinksForWhichTheChildProtocolHasUid(_ childUid: UID, andOwnedIdentity childOwnedCryptoIdentity: ObvCryptoIdentity, within context: NSManagedObjectContext) throws -> [LinkBetweenProtocolInstances] {
        let request: NSFetchRequest<LinkBetweenProtocolInstances> = LinkBetweenProtocolInstances.fetchRequest()
        request.fetchBatchSize = 1_000
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withChildProtocolInstanceUid(childUid),
            Predicate.withOwnedIdentity(childOwnedCryptoIdentity),
        ])
        let links = try context.fetch(request)
        return links
    }
    
    
    static func getAllLinksForWhichTheParentProtocolHasUid(_ parentUid: UID, andOwnedIdentity childOwnedCryptoIdentity: ObvCryptoIdentity, within context: NSManagedObjectContext) throws -> [LinkBetweenProtocolInstances] {
        let request: NSFetchRequest<LinkBetweenProtocolInstances> = LinkBetweenProtocolInstances.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withParentProtocolInstanceUid(parentUid),
            Predicate.withOwnedIdentity(childOwnedCryptoIdentity),
        ])
        let links = try context.fetch(request)
        return links
    }
    
}
