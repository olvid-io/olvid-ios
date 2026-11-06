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
import ObvDatabaseManager
import ObvEncoder
import ObvMetaManager
import ObvTypes
import OlvidUtils
import XCTest
@testable import ObvIdentityManager


/// Checks that a message key wrapped with a prekey of the current device is unwrapped once and refused when it comes again.
///
/// A prekey is kept for months and unwrapping with it consumes nothing, so the receiver keeps the signature of every message it
/// accepts, in `PreKeySignatureReceived`, and refuses a message whose signature it already holds. The signature carries fresh
/// randomness, so the same message key wrapped twice gives two signatures, and both are accepted: no genuine message is refused.
///
/// The signature is recorded only once the sender is known. A message from an identity that is not a contact yet is parked by
/// the fetch manager and unwrapped again when the identity becomes one, so recording it on the first pass would refuse it on the
/// second. That case is tested here on the owned identity, which is where the decision is made.
///
/// The store is the engine's own model over SQLite and is never saved: the fetches the code under test makes see unsaved inserts,
/// and a save would post through a notification delegate these tests do not have. The sender's side of the wrap is `fileprivate`
/// to the prekey entities, so the test builds the wrapped key itself, in the same steps.
final class PreKeySignatureReceivedTests: XCTestCase {

    private let prng = ObvCryptoSuite.sharedInstance.prngService()
    private let serverURL = URL(string: "https://server.olvid.io")!

    private var directory: URL!
    private var coordinator: NSPersistentStoreCoordinator!
    private var context: NSManagedObjectContext!
    private var identityManager: ObvIdentityManagerImplementation!

    private var ownedIdentity: OwnedIdentity!
    private var ownedCryptoIdentity: ObvCryptoIdentity!
    private var currentDeviceUID: UID!
    private var devicePreKey: DevicePreKey!

    /// Alice is a contact. The stranger is not, until a test makes her one.
    private var alice: ObvOwnedCryptoIdentity!
    private var stranger: ObvOwnedCryptoIdentity!


    // MARK: - Setting up a store

    override func setUpWithError() throws {

        directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("PreKeySignatureReceivedTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let modelURL = try XCTUnwrap(Bundle(for: ObvDatabaseManager.self).url(forResource: "ObvEngine", withExtension: "momd"))
        let model = try XCTUnwrap(NSManagedObjectModel(contentsOf: modelURL))
        coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        _ = try coordinator.addPersistentStore(type: .sqlite, at: directory.appendingPathComponent("store.sqlite"))
        context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator

        // The entities reach their delegate manager through a weak static the manager's initializer sets.
        identityManager = ObvIdentityManagerImplementation(sharedContainerIdentifier: "PreKeySignatureReceivedTests", prng: prng, identityPhotosDirectory: directory)

        ownedIdentity = try XCTUnwrap(OwnedIdentity(serverURL: serverURL,
                                                    identityDetails: try Self.details(firstName: "Owner"),
                                                    accordingTo: .KEM_ECIES_Curve25519_and_DEM_CTR_AES_256_then_HMAC_SHA_256,
                                                    and: .Signature_with_EC_SDSA_with_Curve25519,
                                                    keycloakState: nil,
                                                    nameForCurrentDevice: "Device",
                                                    using: prng,
                                                    within: context))
        ownedCryptoIdentity = try ownedIdentity.cryptoIdentity
        currentDeviceUID = try ownedIdentity.currentDevice.uid

        devicePreKey = try PreKeyForCurrentOwnedDevice.createPreKeyForCurrentOwnedDevice(forCurrentOwnedDevice: ownedIdentity.currentDevice,
                                                                                         serverCurrentTimestamp: .now,
                                                                                         prng: prng)

        alice = ObvOwnedCryptoIdentity.gen(withServerURL: serverURL, using: prng)
        stranger = ObvOwnedCryptoIdentity.gen(withServerURL: serverURL, using: prng)
        try makeContact(alice, firstName: "Alice")

    }


    override func tearDownWithError() throws {
        context = nil
        coordinator = nil
        identityManager = nil
        try? FileManager.default.removeItem(at: directory)
        directory = nil
    }


    // MARK: - A contact

    func testTheSameWrappedKeyIsRefusedTheSecondTime() throws {
        let wrapped = try wrap(messageKey(), from: alice)

        XCTAssertTrue(isAccepted(try unwrap(wrapped)))
        XCTAssertTrue(isRefused(try unwrap(wrapped)))
        XCTAssertEqual(try numberOfSignaturesRecorded(), 1)
    }


    func testTheSameMessageKeyWrappedTwiceIsAcceptedTwice() throws {
        let messageKey = messageKey()
        let first = try wrap(messageKey, from: alice)
        let second = try wrap(messageKey, from: alice)
        XCTAssertNotEqual(first.raw, second.raw)

        XCTAssertTrue(isAccepted(try unwrap(first)))
        XCTAssertTrue(isAccepted(try unwrap(second)))
        XCTAssertEqual(try numberOfSignaturesRecorded(), 2)
    }


    // MARK: - Another device of the owned identity

    func testAMessageFromAnotherOwnedDeviceIsRefusedTheSecondTime() throws {
        let wrapped = try wrap(messageKey(), from: try ownedIdentity.ownedCryptoIdentity)

        XCTAssertTrue(isAccepted(try unwrap(wrapped)))
        XCTAssertTrue(isRefused(try unwrap(wrapped)))
        XCTAssertEqual(try numberOfSignaturesRecorded(), 1)
    }


    // MARK: - A sender who is not a contact yet

    func testAMessageFromAStrangerIsRecordedOnlyWhenSheBecomesAContact() throws {
        let wrapped = try wrap(messageKey(), from: stranger)

        // Parked by the fetch manager, and unwrapped again later: nothing may be recorded.
        guard case .unwrapSucceededButRemoteCryptoIdIsUnknown = try unwrap(wrapped) else { return XCTFail("The stranger is not a contact") }
        XCTAssertEqual(try numberOfSignaturesRecorded(), 0)

        try makeContact(stranger, firstName: "Stranger")

        XCTAssertTrue(isAccepted(try unwrap(wrapped)))
        XCTAssertEqual(try numberOfSignaturesRecorded(), 1)
        XCTAssertTrue(isRefused(try unwrap(wrapped)))
    }


    // MARK: - The store's own guard

    /// The replay check reads the table before a row is written, so the constraint never fires in a batch. This checks that the
    /// store refuses the pair all the same: two rows for one prekey and one signature cannot be saved. The save is the only one
    /// in these tests, and it must fail: a successful save runs the entities' `didSave` hooks, which need a delegate manager
    /// the tests do not build. The error code is what tells a refusal by the constraint from any other failure.
    func testTheStoreRefusesASecondRowForTheSamePreKeyAndSignature() throws {
        let preKey = try XCTUnwrap(try context.fetch(PreKeyForCurrentOwnedDevice.fetchRequest()).first)
        let signature = Data(repeating: 0x5A, count: 80)

        try PreKeySignatureReceived.create(signature: signature, preKey: preKey)
        try PreKeySignatureReceived.create(signature: signature, preKey: preKey)
        XCTAssertEqual(try numberOfSignaturesRecorded(), 2)

        XCTAssertThrowsError(try context.save()) { error in
            XCTAssertEqual((error as NSError).code, NSManagedObjectConstraintMergeError)
        }
    }


    // MARK: - The prekey's deletion

    func testTheRowsGoWithThePreKey() throws {
        XCTAssertTrue(isAccepted(try unwrap(try wrap(messageKey(), from: alice))))
        XCTAssertTrue(isAccepted(try unwrap(try wrap(messageKey(), from: alice))))
        XCTAssertEqual(try numberOfSignaturesRecorded(), 2)

        let preKeys = try context.fetch(PreKeyForCurrentOwnedDevice.fetchRequest())
        XCTAssertEqual(preKeys.count, 1)
        try preKeys.forEach { try $0.deletePreKeyForCurrentOwnedDevice() }
        context.processPendingChanges() // Applies the cascade without a save

        XCTAssertEqual(try numberOfSignaturesRecorded(), 0)
    }


    // MARK: - The sender's side

    private func messageKey() -> any AuthenticatedEncryptionKey {
        ObvCryptoSuite.sharedInstance.authenticatedEncryption().generateKey(with: prng)
    }


    /// What `PreKeyAbstract.wrap` does for a sender: the message key, her device and her identity, signed with fresh randomness
    /// over a challenge naming the receiver and the prekey, all encrypted to the prekey and prefixed with its id.
    private func wrap(_ messageKey: any AuthenticatedEncryptionKey, from sender: ObvOwnedCryptoIdentity) throws -> EncryptedData {
        let senderDeviceUID = UID.gen(with: prng)
        let encodedToSend = [messageKey, senderDeviceUID, sender.getObvCryptoIdentity()].obvEncode()
        let challenge = ChallengeType.encryptionWithPreKey(encodedToSend: encodedToSend,
                                                           toIdentity: ownedCryptoIdentity,
                                                           toDeviceUID: currentDeviceUID,
                                                           preKeyId: devicePreKey.keyId)
        let response = try XCTUnwrap(ObvSolveChallengeStruct.solveChallenge(challenge,
                                                                            with: sender.privateKeyForAuthentication,
                                                                            and: sender.publicKeyForAuthentication,
                                                                            using: prng))
        let plaintext = [encodedToSend, response.obvEncode()].obvEncode().rawData
        let encrypted = try XCTUnwrap(PublicKeyEncryption.encrypt(plaintext, using: devicePreKey.encryptionKey, and: prng))
        return devicePreKey.keyId.concat(with: encrypted)
    }


    // MARK: - The receiver's side

    private func unwrap(_ wrapped: EncryptedData) throws -> ResultOfUnwrapWithPreKey {
        try ownedIdentity.unwrapForCurrentOwnedDevice(wrapped)
    }


    private func isAccepted(_ result: ResultOfUnwrapWithPreKey) -> Bool {
        if case .unwrapSucceeded = result { return true }
        return false
    }


    private func isRefused(_ result: ResultOfUnwrapWithPreKey) -> Bool {
        if case .signatureWasAlreadyAccepted = result { return true }
        return false
    }


    private func numberOfSignaturesRecorded() throws -> Int {
        try context.count(for: PreKeySignatureReceived.fetchRequest())
    }


    // MARK: - Helpers

    private func makeContact(_ identity: ObvOwnedCryptoIdentity, firstName: String) throws {
        _ = try XCTUnwrap(ContactIdentity(cryptoIdentity: identity.getObvCryptoIdentity(),
                                          identityCoreDetails: try Self.details(firstName: firstName).coreDetails,
                                          trustOrigin: .direct(timestamp: .now),
                                          ownedIdentity: ownedIdentity,
                                          isKnownToBeOneToOne: true))
    }


    private static func details(firstName: String) throws -> ObvIdentityDetails {
        ObvIdentityDetails(coreDetails: try ObvIdentityCoreDetails(firstName: firstName, lastName: nil, company: nil, position: nil, signedUserDetails: nil), photoURL: nil)
    }

}
