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


/// Checks that each table of received signatures sees its own rows and nobody else's.
///
/// Four tables keep the signatures a protocol has already accepted, so that a message carrying one again is dropped. They have the
/// same two columns, so a request built on the wrong entity runs without complaint and never finds anything: `GroupV2SignatureReceived`
/// and `ContactOwnedIdentityDeletionSignatureReceived` both looked in `ChannelCreationPingSignatureReceived` for years, and every replay
/// check they guarded answered "not seen". Each test here writes a row and asks the table that wrote it, then writes the same identity
/// and signature into the two other tables and checks the first one still does not see them.
///
/// The model is built here with the three entities and their two columns, so the store can hold a row in the wrong table, which is what
/// the old code looked at. The store is SQLite, as on a device, and the context is saved before each question so that the store, and
/// not the context's pending changes, is what answers. `ChannelCreationPingSignatureReceived` keeps its predicates private, so the two
/// column names are written out.
final class SignatureReceivedTablesTests: XCTestCase {

    private var container: URL!
    private var coordinator: NSPersistentStoreCoordinator!
    private var context: NSManagedObjectContext!

    private static let prng = ObvCryptoSuite.sharedInstance.prngService()
    private static let server = URL(string: "https://server.test")!

    private let ownedIdentity = ObvOwnedCryptoIdentity.gen(withServerURL: server, using: prng).getObvCryptoIdentity()
    private let otherOwnedIdentity = ObvOwnedCryptoIdentity.gen(withServerURL: server, using: prng).getObvCryptoIdentity()

    private let signature = Data(repeating: 0xA5, count: 64)
    private let otherSignature = Data(repeating: 0x5A, count: 64)


    // MARK: - Setting up a store

    override func setUpWithError() throws {
        container = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SignatureReceivedTablesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        coordinator = NSPersistentStoreCoordinator(managedObjectModel: Self.model())
        _ = try coordinator.addPersistentStore(type: .sqlite, at: container.appendingPathComponent("store.sqlite"))
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
        model.entities = [
            entity("GroupV2SignatureReceived", GroupV2SignatureReceived.self),
            entity("ContactOwnedIdentityDeletionSignatureReceived", ContactOwnedIdentityDeletionSignatureReceived.self),
            entity("ChannelCreationPingSignatureReceived", ChannelCreationPingSignatureReceived.self),
        ]
        return model
    }


    /// One of the three tables: the same two columns as the production model, both required.
    private static func entity(_ name: String, _ managedObjectClass: NSManagedObject.Type) -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = name
        entity.managedObjectClassName = NSStringFromClass(managedObjectClass)
        entity.properties = [
            attribute("rawOwnedIdentity"),
            attribute("signature"),
        ]
        return entity
    }


    private static func attribute(_ name: String) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = .binaryDataAttributeType
        attribute.isOptional = false
        return attribute
    }


    // MARK: - Group v2 pings

    func testGroupV2TableSeesItsOwnRow() throws {
        XCTAssertFalse(try GroupV2SignatureReceived.exists(ownedCryptoIdentity: ownedIdentity, signature: signature, within: context))

        _ = GroupV2SignatureReceived(ownedCryptoIdentity: ownedIdentity, signature: signature, within: context)
        try context.save()

        XCTAssertTrue(try GroupV2SignatureReceived.exists(ownedCryptoIdentity: ownedIdentity, signature: signature, within: context))
    }


    func testGroupV2TableMatchesOnBothTheIdentityAndTheSignature() throws {
        _ = GroupV2SignatureReceived(ownedCryptoIdentity: ownedIdentity, signature: signature, within: context)
        try context.save()

        XCTAssertFalse(try GroupV2SignatureReceived.exists(ownedCryptoIdentity: ownedIdentity, signature: otherSignature, within: context))
        XCTAssertFalse(try GroupV2SignatureReceived.exists(ownedCryptoIdentity: otherOwnedIdentity, signature: signature, within: context))
    }


    /// The row the old code found, when it found anything, was in another table. The table must not see those.
    func testGroupV2TableDoesNotSeeTheOtherTables() throws {
        _ = ChannelCreationPingSignatureReceived(ownedCryptoIdentity: ownedIdentity, signature: signature, within: context)
        _ = ContactOwnedIdentityDeletionSignatureReceived(ownedCryptoIdentity: ownedIdentity, signature: signature, within: context)
        try context.save()

        XCTAssertFalse(try GroupV2SignatureReceived.exists(ownedCryptoIdentity: ownedIdentity, signature: signature, within: context))
    }


    // MARK: - Notices that a contact deleted their identity

    func testDeletionTableSeesItsOwnRow() throws {
        XCTAssertFalse(try ContactOwnedIdentityDeletionSignatureReceived.exists(ownedCryptoIdentity: ownedIdentity, signature: signature, within: context))

        _ = ContactOwnedIdentityDeletionSignatureReceived(ownedCryptoIdentity: ownedIdentity, signature: signature, within: context)
        try context.save()

        XCTAssertTrue(try ContactOwnedIdentityDeletionSignatureReceived.exists(ownedCryptoIdentity: ownedIdentity, signature: signature, within: context))
    }


    func testDeletionTableMatchesOnBothTheIdentityAndTheSignature() throws {
        _ = ContactOwnedIdentityDeletionSignatureReceived(ownedCryptoIdentity: ownedIdentity, signature: signature, within: context)
        try context.save()

        XCTAssertFalse(try ContactOwnedIdentityDeletionSignatureReceived.exists(ownedCryptoIdentity: ownedIdentity, signature: otherSignature, within: context))
        XCTAssertFalse(try ContactOwnedIdentityDeletionSignatureReceived.exists(ownedCryptoIdentity: otherOwnedIdentity, signature: signature, within: context))
    }


    func testDeletionTableDoesNotSeeTheOtherTables() throws {
        _ = ChannelCreationPingSignatureReceived(ownedCryptoIdentity: ownedIdentity, signature: signature, within: context)
        _ = GroupV2SignatureReceived(ownedCryptoIdentity: ownedIdentity, signature: signature, within: context)
        try context.save()

        XCTAssertFalse(try ContactOwnedIdentityDeletionSignatureReceived.exists(ownedCryptoIdentity: ownedIdentity, signature: signature, within: context))
    }


    // MARK: - The table the two others used to look in

    /// Read and found correct when the two others were fixed; this pins it.
    func testPingTableSeesItsOwnRowAndNotTheOthers() throws {
        _ = GroupV2SignatureReceived(ownedCryptoIdentity: ownedIdentity, signature: signature, within: context)
        _ = ContactOwnedIdentityDeletionSignatureReceived(ownedCryptoIdentity: ownedIdentity, signature: signature, within: context)
        try context.save()

        XCTAssertFalse(try ChannelCreationPingSignatureReceived.exists(ownedCryptoIdentity: ownedIdentity, signature: signature, within: context))

        _ = ChannelCreationPingSignatureReceived(ownedCryptoIdentity: ownedIdentity, signature: signature, within: context)
        try context.save()

        XCTAssertTrue(try ChannelCreationPingSignatureReceived.exists(ownedCryptoIdentity: ownedIdentity, signature: signature, within: context))
    }

}
