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

import CoreData
import ObvCrypto
import XCTest
@testable import ObvProtocolManager


/// Checks which parents the sweep considers to be waiting for a child protocol that will never answer them.
///
/// The rows are written directly, with no protocol running: a protocol instance cannot be created without an identity manager
/// answering for its owned identity, and what is under test is the rule rather than the way a store comes to look like this.
/// The model is built here, from the same `Predicate.Key` values the rule's predicates are made of, so that renaming an attribute
/// carries over rather than breaking these tests. The store is SQLite, as on a device: an in-memory store answers some fetches
/// in memory and would not be the thing the rule runs against.
final class OrphanedParentSweepTests: XCTestCase {
    
    private var container: URL!
    private var coordinator: NSPersistentStoreCoordinator!
    private var context: NSManagedObjectContext!
    
    private let ownedIdentity = Data(repeating: 0x01, count: 32)
    private let otherOwnedIdentity = Data(repeating: 0x02, count: 32)
    
    private var nextUid: UInt32 = 0
    
    
    // MARK: - Setting up a store
    
    override func setUpWithError() throws {
        container = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("OrphanedParentSweepTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        coordinator = NSPersistentStoreCoordinator(managedObjectModel: Self.model())
        try coordinator.addPersistentStore(type: .sqlite, at: container.appendingPathComponent("store.sqlite"))
        context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
    }
    
    
    override func tearDownWithError() throws {
        context = nil
        coordinator = nil
        try? FileManager.default.removeItem(at: container)
        container = nil
    }
    
    
    private static func model() -> NSManagedObjectModel {
        
        let model = NSManagedObjectModel()
        
        let protocolInstance = NSEntityDescription()
        protocolInstance.name = "ProtocolInstance"
        protocolInstance.managedObjectClassName = NSStringFromClass(ProtocolInstance.self)
        
        let link = NSEntityDescription()
        link.name = "LinkBetweenProtocolInstances"
        link.managedObjectClassName = NSStringFromClass(LinkBetweenProtocolInstances.self)
        
        let receivedMessage = NSEntityDescription()
        receivedMessage.name = "ReceivedMessage"
        receivedMessage.managedObjectClassName = NSStringFromClass(ReceivedMessage.self)
        
        let linkFromParent = NSRelationshipDescription()
        linkFromParent.name = ProtocolInstance.Predicate.Key.linkBetweenProtocolInstance.rawValue
        linkFromParent.destinationEntity = link
        linkFromParent.maxCount = 1
        linkFromParent.isOptional = true
        linkFromParent.deleteRule = .cascadeDeleteRule
        
        let parentFromLink = NSRelationshipDescription()
        parentFromLink.name = "parentProtocolInstance"
        parentFromLink.destinationEntity = protocolInstance
        parentFromLink.maxCount = 1
        parentFromLink.isOptional = true
        parentFromLink.deleteRule = .nullifyDeleteRule
        
        linkFromParent.inverseRelationship = parentFromLink
        parentFromLink.inverseRelationship = linkFromParent
        
        protocolInstance.properties = [
            attribute(ProtocolInstance.Predicate.Key.cryptoProtocolRawId.rawValue, .integer64AttributeType),
            attribute(ProtocolInstance.Predicate.Key.currentStateRawId.rawValue, .integer64AttributeType),
            attribute(ProtocolInstance.Predicate.Key.rawEncodedCurrentState.rawValue, .binaryDataAttributeType),
            attribute(ProtocolInstance.Predicate.Key.rawOwnedCryptoIdentity.rawValue, .binaryDataAttributeType),
            attribute(ProtocolInstance.Predicate.Key.rawUID.rawValue, .binaryDataAttributeType),
            linkFromParent,
        ]
        
        // LinkBetweenProtocolInstances keeps its predicates private, so these two names are written out
        
        link.properties = [
            attribute("messageToSendRawId", .integer64AttributeType),
            attribute("rawChildProtocolInstanceUid", .binaryDataAttributeType),
            parentFromLink,
        ]
        
        receivedMessage.properties = [
            attribute(ReceivedMessage.Predicate.Key.protocolMessageRawId.rawValue, .integer64AttributeType),
            attribute(ReceivedMessage.Predicate.Key.protocolRawId.rawValue, .integer64AttributeType),
            attribute(ReceivedMessage.Predicate.Key.rawEncodedEncodedInputs.rawValue, .binaryDataAttributeType),
            attribute(ReceivedMessage.Predicate.Key.rawEncodedUserDialogResponse.rawValue, .binaryDataAttributeType),
            attribute(ReceivedMessage.Predicate.Key.rawMessageIdOwnedIdentity.rawValue, .binaryDataAttributeType),
            attribute(ReceivedMessage.Predicate.Key.rawMessageIdUid.rawValue, .binaryDataAttributeType),
            attribute(ReceivedMessage.Predicate.Key.rawProtocolInstanceUid.rawValue, .binaryDataAttributeType),
            attribute(ReceivedMessage.Predicate.Key.rawReceptionChannelInfo.rawValue, .binaryDataAttributeType),
            attribute(ReceivedMessage.Predicate.Key.timestamp.rawValue, .dateAttributeType),
            attribute(ReceivedMessage.Predicate.Key.userDialogUuid.rawValue, .UUIDAttributeType),
        ]
        
        model.entities = [protocolInstance, link, receivedMessage]
        
        return model
        
    }
    
    
    private static func attribute(_ name: String, _ type: NSAttributeType) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = true
        return attribute
    }
    
    
    // MARK: - Writing rows
    
    /// A fresh 32 byte UID, distinct within one test.
    private func makeUid() -> UID {
        nextUid += 1
        var raw = Data(repeating: 0x00, count: UID.length - MemoryLayout<UInt32>.size)
        withUnsafeBytes(of: nextUid.bigEndian) { raw.append(contentsOf: $0) }
        return UID(uid: raw)!
    }
    
    
    @discardableResult
    private func insertInstance(_ cryptoProtocolId: CryptoProtocolId, inStateRawId stateRawId: Int, uid: UID, ownedIdentity: Data? = nil) -> ProtocolInstance {
        let instance = NSEntityDescription.insertNewObject(forEntityName: "ProtocolInstance", into: context) as! ProtocolInstance
        instance.setValue(cryptoProtocolId.rawValue, forKey: ProtocolInstance.Predicate.Key.cryptoProtocolRawId.rawValue)
        instance.setValue(stateRawId, forKey: ProtocolInstance.Predicate.Key.currentStateRawId.rawValue)
        instance.setValue(Data([0x00]), forKey: ProtocolInstance.Predicate.Key.rawEncodedCurrentState.rawValue)
        instance.setValue(ownedIdentity ?? self.ownedIdentity, forKey: ProtocolInstance.Predicate.Key.rawOwnedCryptoIdentity.rawValue)
        instance.setValue(uid.raw, forKey: ProtocolInstance.Predicate.Key.rawUID.rawValue)
        return instance
    }
    
    
    /// A `ContactDeviceDiscoveryProtocol` waiting for a child, linked to a child instance that is not created here.
    @discardableResult
    private func insertWaitingContactDeviceDiscovery(childUid: UID, ownedIdentity: Data? = nil) -> ProtocolInstance {
        let parent = insertInstance(.contactDeviceDiscovery,
                                    inStateRawId: ContactDeviceDiscoveryProtocol.StateId.waitingForChildProtocol.rawValue,
                                    uid: makeUid(),
                                    ownedIdentity: ownedIdentity)
        XCTAssertNotNil(LinkBetweenProtocolInstances(parentProtocolInstance: parent, childProtocolInstanceUid: childUid, messageToSendRawId: 1))
        return parent
    }
    
    
    @discardableResult
    private func insertWaitingKeycloakContactAddition(childUid: UID) -> ProtocolInstance {
        let parent = insertInstance(.keycloakContactAddition,
                                    inStateRawId: KeycloakContactAdditionProtocol.StateId.waitingForDeviceDiscovery.rawValue,
                                    uid: makeUid())
        XCTAssertNotNil(LinkBetweenProtocolInstances(parentProtocolInstance: parent, childProtocolInstanceUid: childUid, messageToSendRawId: 1))
        return parent
    }
    
    
    private func insertReceivedMessage(waitingFor protocolInstanceUid: UID, ownedIdentity: Data? = nil) {
        let message = NSEntityDescription.insertNewObject(forEntityName: "ReceivedMessage", into: context)
        message.setValue(1, forKey: ReceivedMessage.Predicate.Key.protocolMessageRawId.rawValue)
        message.setValue(CryptoProtocolId.contactDeviceDiscovery.rawValue, forKey: ReceivedMessage.Predicate.Key.protocolRawId.rawValue)
        message.setValue(Data([0x00]), forKey: ReceivedMessage.Predicate.Key.rawEncodedEncodedInputs.rawValue)
        message.setValue(ownedIdentity ?? self.ownedIdentity, forKey: ReceivedMessage.Predicate.Key.rawMessageIdOwnedIdentity.rawValue)
        message.setValue(makeUid().raw, forKey: ReceivedMessage.Predicate.Key.rawMessageIdUid.rawValue)
        message.setValue(protocolInstanceUid.raw, forKey: ReceivedMessage.Predicate.Key.rawProtocolInstanceUid.rawValue)
        message.setValue(Data([0x00]), forKey: ReceivedMessage.Predicate.Key.rawReceptionChannelInfo.rawValue)
        message.setValue(Date(), forKey: ReceivedMessage.Predicate.Key.timestamp.rawValue)
    }
    
    
    // MARK: - Asking the rule
    
    private func candidates() throws -> [NSManagedObjectID] {
        try ProtocolInstance.getContactDeviceDiscoveryAndKeycloakContactAdditionInstancesWaitingForAChildThatWillNeverAnswer(within: context)
    }
    
    
    @discardableResult
    private func deleteAmongAllCandidates() throws -> [CryptoProtocolId: Int] {
        try ProtocolInstance.deleteContactDeviceDiscoveryAndKeycloakContactAdditionInstancesWaitingForAChildThatWillNeverAnswer(among: candidates(), within: context)
    }
    
    
    private func numberOfInstances() throws -> Int {
        try context.count(for: NSFetchRequest<ProtocolInstance>(entityName: "ProtocolInstance"))
    }
    
    
    private func numberOfLinks() throws -> Int {
        try context.count(for: NSFetchRequest<LinkBetweenProtocolInstances>(entityName: "LinkBetweenProtocolInstances"))
    }
    
    
    // MARK: - What is swept away
    
    func testAParentWhoseChildIsNowhereIsDeleted() throws {
        
        insertWaitingContactDeviceDiscovery(childUid: makeUid())
        try context.save()
        
        XCTAssertEqual(try candidates().count, 1)
        
        let deleted = try deleteAmongAllCandidates()
        try context.save()
        
        XCTAssertEqual(deleted, [.contactDeviceDiscovery: 1])
        XCTAssertEqual(try numberOfInstances(), 0)
        XCTAssertEqual(try numberOfLinks(), 0, "The link is deleted with the parent it belongs to")
        
    }
    
    
    func testAWaitingKeycloakContactAdditionIsSweptToo() throws {
        
        insertWaitingKeycloakContactAddition(childUid: makeUid())
        try context.save()
        
        XCTAssertEqual(try deleteAmongAllCandidates(), [.keycloakContactAddition: 1])
        
    }
    
    
    func testTheCountsAreGivenPerProtocol() throws {
        
        insertWaitingContactDeviceDiscovery(childUid: makeUid())
        insertWaitingContactDeviceDiscovery(childUid: makeUid())
        insertWaitingKeycloakContactAddition(childUid: makeUid())
        try context.save()
        
        XCTAssertEqual(try deleteAmongAllCandidates(), [.contactDeviceDiscovery: 2, .keycloakContactAddition: 1])
        XCTAssertEqual(try numberOfInstances(), 0)
        
    }
    
    
    // MARK: - What is kept, and why
    
    func testAParentWhoseChildStillExistsIsKept() throws {
        
        let childUid = makeUid()
        insertWaitingContactDeviceDiscovery(childUid: childUid)
        insertInstance(.deviceDiscoveryForRemoteIdentity, inStateRawId: 1, uid: childUid)
        try context.save()
        
        XCTAssertEqual(try candidates().count, 0)
        
    }
    
    
    /// The pair is starting: the link and the child's first message were saved together, and that message has not been processed yet,
    /// so the child's instance does not exist.
    func testAParentWhoseChildHasAMessageWaitingIsKept() throws {
        
        let childUid = makeUid()
        insertWaitingContactDeviceDiscovery(childUid: childUid)
        insertReceivedMessage(waitingFor: childUid)
        try context.save()
        
        XCTAssertEqual(try candidates().count, 0)
        
    }
    
    
    /// The pair is finishing: the save that deleted the child posted its result to this parent, which has not processed it yet. Deleting
    /// the parent now would lose that result.
    func testAParentWhoseOwnResultIsWaitingIsKept() throws {
        
        let parent = insertWaitingContactDeviceDiscovery(childUid: makeUid())
        insertReceivedMessage(waitingFor: try parent.uid)
        try context.save()
        
        XCTAssertEqual(try candidates().count, 0)
        
    }
    
    
    func testAParentHoldingNoLinkIsKept() throws {
        
        insertInstance(.contactDeviceDiscovery,
                       inStateRawId: ContactDeviceDiscoveryProtocol.StateId.waitingForChildProtocol.rawValue,
                       uid: makeUid())
        try context.save()
        
        XCTAssertEqual(try candidates().count, 0, "Deleting on no evidence at all is the one thing the rule never does")
        
    }
    
    
    /// A keycloak contact addition keeps its link after its child has finished, so a parent past its waiting state is live work.
    func testAnInstancePastItsWaitingStateIsKept() throws {
        
        let parent = insertInstance(.keycloakContactAddition,
                                    inStateRawId: KeycloakContactAdditionProtocol.StateId.waitingForConfirmation.rawValue,
                                    uid: makeUid())
        XCTAssertNotNil(LinkBetweenProtocolInstances(parentProtocolInstance: parent, childProtocolInstanceUid: makeUid(), messageToSendRawId: 1))
        try context.save()
        
        XCTAssertEqual(try candidates().count, 0)
        
    }
    
    
    /// Only the two protocols that start a device discovery as a child are swept, whatever state anything else is in.
    func testAnotherProtocolIsNeverSelected() throws {
        
        let instance = insertInstance(.groupV2, inStateRawId: 1, uid: makeUid())
        XCTAssertNotNil(LinkBetweenProtocolInstances(parentProtocolInstance: instance, childProtocolInstanceUid: makeUid(), messageToSendRawId: 1))
        try context.save()
        
        XCTAssertEqual(try candidates().count, 0)
        
    }
    
    
    // MARK: - The owned identity is part of the comparison
    
    func testAChildOfAnotherOwnedIdentityDoesNotSaveTheParent() throws {
        
        let childUid = makeUid()
        insertWaitingContactDeviceDiscovery(childUid: childUid)
        insertInstance(.deviceDiscoveryForRemoteIdentity, inStateRawId: 1, uid: childUid, ownedIdentity: otherOwnedIdentity)
        try context.save()
        
        XCTAssertEqual(try candidates().count, 1)
        
    }
    
    
    func testAMessageOfAnotherOwnedIdentityDoesNotSaveTheParent() throws {
        
        let childUid = makeUid()
        let parent = insertWaitingContactDeviceDiscovery(childUid: childUid)
        insertReceivedMessage(waitingFor: childUid, ownedIdentity: otherOwnedIdentity)
        insertReceivedMessage(waitingFor: try parent.uid, ownedIdentity: otherOwnedIdentity)
        try context.save()
        
        XCTAssertEqual(try candidates().count, 1)
        
    }
    
    
    // MARK: - The second pass only touches what it is given
    
    func testOnlyTheCandidatesGivenAreDeleted() throws {
        
        let kept = insertWaitingContactDeviceDiscovery(childUid: makeUid())
        let swept = insertWaitingContactDeviceDiscovery(childUid: makeUid())
        try context.save()
        
        let deleted = try ProtocolInstance.deleteContactDeviceDiscoveryAndKeycloakContactAdditionInstancesWaitingForAChildThatWillNeverAnswer(
            among: [swept.objectID],
            within: context)
        try context.save()
        
        XCTAssertEqual(deleted, [.contactDeviceDiscovery: 1])
        XCTAssertEqual(try numberOfInstances(), 1)
        XCTAssertFalse(kept.isDeleted)
        
    }
    
    
    /// A candidate the first pass found and that has since been given something to wait for is not deleted, which is the whole purpose
    /// of asking again on the queue running the protocol steps.
    func testACandidateThatIsNoLongerOrphanedIsNotDeleted() throws {
        
        let childUid = makeUid()
        insertWaitingContactDeviceDiscovery(childUid: childUid)
        try context.save()
        
        let candidates = try self.candidates()
        XCTAssertEqual(candidates.count, 1)
        
        // The child's instance is created, as processing the child's first message would do
        
        insertInstance(.deviceDiscoveryForRemoteIdentity, inStateRawId: 1, uid: childUid)
        try context.save()
        
        let deleted = try ProtocolInstance.deleteContactDeviceDiscoveryAndKeycloakContactAdditionInstancesWaitingForAChildThatWillNeverAnswer(
            among: candidates,
            within: context)
        
        XCTAssertEqual(deleted, [:])
        XCTAssertEqual(try numberOfInstances(), 2)
        
    }
    
    
    func testAnEmptyListOfCandidatesDeletesNothing() throws {
        
        insertWaitingContactDeviceDiscovery(childUid: makeUid())
        try context.save()
        
        let deleted = try ProtocolInstance.deleteContactDeviceDiscoveryAndKeycloakContactAdditionInstancesWaitingForAChildThatWillNeverAnswer(
            among: [],
            within: context)
        
        XCTAssertEqual(deleted, [:])
        XCTAssertEqual(try numberOfInstances(), 1)
        
    }
    
    
    /// More candidates than one slice of the "IN" statement they are asked for in.
    func testMoreCandidatesThanOneSlice() throws {
        
        let numberOfOrphans = 250
        
        for _ in 0..<numberOfOrphans {
            insertWaitingContactDeviceDiscovery(childUid: makeUid())
        }
        try context.save()
        
        XCTAssertEqual(try candidates().count, numberOfOrphans)
        XCTAssertEqual(try deleteAmongAllCandidates(), [.contactDeviceDiscovery: numberOfOrphans])
        
        try context.save()
        
        XCTAssertEqual(try numberOfInstances(), 0)
        XCTAssertEqual(try numberOfLinks(), 0)
        
    }
    
}
