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


/// A store holding an owned identity, two contacts and what a group v2 is made of, for tests about who holds the admin key.
///
/// The model is the engine's own, read from the database manager's bundle, and the store is SQLite in a directory of its own.
/// Nothing is ever saved: an entity's `didSave` posts through a notification delegate these tests do not have, and the fetches
/// the code under test makes see unsaved inserts. The identity manager is kept because every entity reaches its delegate
/// manager through a weak static the manager's initializer sets.
///
/// The administrators chain is one block decoded from hand-made data and force-marked as checked: nothing here verifies a
/// signature, and the code under test reads permissions from the blob's members, not from the chain.
final class GroupV2TestStore {

    let prng = ObvCryptoSuite.sharedInstance.prngService()
    let serverURL = URL(string: "https://server.olvid.io")!

    private let directory: URL
    private let coordinator: NSPersistentStoreCoordinator
    let context: NSManagedObjectContext
    let identityManager: ObvIdentityManagerImplementation

    let ownedIdentity: OwnedIdentity
    let alice: ContactIdentity
    let bob: ContactIdentity

    let ownedCryptoIdentity: ObvCryptoIdentity
    let aliceCryptoIdentity: ObvCryptoIdentity
    let bobCryptoIdentity: ObvCryptoIdentity

    let groupIdentifier: GroupV2.Identifier
    private let administratorsChain: GroupV2.AdministratorsChain

    /// The keys a sender could hand over. The admin key is the one the tests look for.
    let mainSeed: Seed
    let versionSeed: Seed
    let adminKey: PrivateKeyForAuthentication

    private var names = [ObvCryptoIdentity: String]()
    private var nonces = [ObvCryptoIdentity: Data]()


    init() throws {

        directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("GroupV2TestStore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let modelURL = try XCTUnwrap(Bundle(for: ObvDatabaseManager.self).url(forResource: "ObvEngine", withExtension: "momd"))
        let model = try XCTUnwrap(NSManagedObjectModel(contentsOf: modelURL))
        coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(type: .sqlite, at: directory.appendingPathComponent("store.sqlite"))
        context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator

        identityManager = ObvIdentityManagerImplementation(sharedContainerIdentifier: "GroupV2TestStore", prng: prng, identityPhotosDirectory: directory)

        ownedIdentity = try XCTUnwrap(OwnedIdentity(serverURL: serverURL,
                                                    identityDetails: try Self.details(firstName: "Owner"),
                                                    accordingTo: .KEM_ECIES_Curve25519_and_DEM_CTR_AES_256_then_HMAC_SHA_256,
                                                    and: .Signature_with_EC_SDSA_with_Curve25519,
                                                    keycloakState: nil,
                                                    nameForCurrentDevice: "Device",
                                                    using: prng,
                                                    within: context))
        ownedCryptoIdentity = try ownedIdentity.cryptoIdentity

        aliceCryptoIdentity = ObvOwnedCryptoIdentity.gen(withServerURL: serverURL, using: prng).getObvCryptoIdentity()
        bobCryptoIdentity = ObvOwnedCryptoIdentity.gen(withServerURL: serverURL, using: prng).getObvCryptoIdentity()
        alice = try XCTUnwrap(ContactIdentity(cryptoIdentity: aliceCryptoIdentity,
                                              identityCoreDetails: try Self.details(firstName: "Alice").coreDetails,
                                              trustOrigin: .direct(timestamp: .now),
                                              ownedIdentity: ownedIdentity,
                                              isKnownToBeOneToOne: true))
        bob = try XCTUnwrap(ContactIdentity(cryptoIdentity: bobCryptoIdentity,
                                            identityCoreDetails: try Self.details(firstName: "Bob").coreDetails,
                                            trustOrigin: .direct(timestamp: .now),
                                            ownedIdentity: ownedIdentity,
                                            isKnownToBeOneToOne: true))

        administratorsChain = try XCTUnwrap(Self.chain(startedBy: ownedCryptoIdentity, prng: prng))
        groupIdentifier = GroupV2.Identifier(groupUID: administratorsChain.groupUID, serverURL: serverURL, category: .server)

        mainSeed = prng.genSeed()
        versionSeed = prng.genSeed()
        adminKey = ObvOwnedCryptoIdentity.gen(withServerURL: serverURL, using: prng).privateKeyForAuthentication

        names = [ownedCryptoIdentity: "Owner", aliceCryptoIdentity: "Alice", bobCryptoIdentity: "Bob"]
        nonces = [ownedCryptoIdentity: prng.genBytes(count: 16), aliceCryptoIdentity: prng.genBytes(count: 16), bobCryptoIdentity: prng.genBytes(count: 16)]

    }


    deinit {
        try? FileManager.default.removeItem(at: directory)
    }


    // MARK: - What a sender hands over

    /// The keys with or without the admin key; the seeds are always the same two.
    func keys(withAdminKey: Bool) -> GroupV2.BlobKeys {
        GroupV2.BlobKeys(blobMainSeed: mainSeed, blobVersionSeed: versionSeed, groupAdminServerAuthenticationPrivateKey: withAdminKey ? adminKey : nil)
    }


    /// A blob whose members are the owned identity, Alice and Bob, with the group-admin permission on `admins` only. The
    /// details are real so that a pending member can be moved to the members, which decodes them.
    func blob(version: Int, admins: Set<ObvCryptoIdentity>) throws -> GroupV2.ServerBlob {
        let members: Set<GroupV2.IdentityAndPermissionsAndDetails> = Set(try [ownedCryptoIdentity, aliceCryptoIdentity, bobCryptoIdentity].map { identity in
            GroupV2.IdentityAndPermissionsAndDetails(identity: identity,
                                                     rawPermissions: admins.contains(identity) ? [GroupV2.Permission.groupAdmin.rawValue] : [],
                                                     serializedIdentityCoreDetails: try Self.details(firstName: try XCTUnwrap(names[identity])).coreDetails.jsonEncode(),
                                                     groupInvitationNonce: try XCTUnwrap(nonces[identity]))
        })
        return GroupV2.ServerBlob(administratorsChain: administratorsChain,
                                  groupMembers: members,
                                  groupVersion: version,
                                  serializedGroupCoreDetails: Data(),
                                  serverPhotoInfo: nil,
                                  serializedGroupType: nil)
            .withForcedCheckedAdministratorsChainIntegrity()
    }


    /// Joins the group as the receiver does on accepting an invitation, and returns the group as stored.
    func joinGroup(admins: Set<ObvCryptoIdentity>, keys: GroupV2.BlobKeys) throws -> ContactGroupV2 {
        try ContactGroupV2.createContactGroupV2JoinedByOwnedIdentity(ownedIdentity,
                                                                    groupIdentifier: groupIdentifier,
                                                                    serverBlob: try blob(version: 1, admins: admins),
                                                                    blobKeys: keys,
                                                                    createdByMeOnOtherDevice: false,
                                                                    lastModificationTimestamp: .now)
        return try XCTUnwrap(ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity))
    }


    // MARK: - Helpers

    static func rawData(of key: PrivateKeyForAuthentication?) -> Data? {
        key?.obvEncode().rawData
    }


    private static func details(firstName: String) throws -> ObvIdentityDetails {
        ObvIdentityDetails(coreDetails: try ObvIdentityCoreDetails(firstName: firstName, lastName: nil, company: nil, position: nil, signedUserDetails: nil), photoURL: nil)
    }


    /// A one-block chain decoded from hand-made data. The block's signature is empty: nothing here checks the chain's integrity.
    private static func chain(startedBy admin: ObvCryptoIdentity, prng: PRNGService) -> GroupV2.AdministratorsChain? {
        let previousBlockHash = prng.genBytes(count: 32)
        let innerData = [previousBlockHash.obvEncode(), [admin.obvEncode()].obvEncode()].obvEncode()
        let block = [innerData, Data().obvEncode()].obvEncode()
        return GroupV2.AdministratorsChain([block].obvEncode())
    }

}
