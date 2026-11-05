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

import ObvCrypto
import ObvMetaManager
import OlvidUtils
import XCTest
@testable import ObvIdentityManager


/// Checks which contact is given the admin key by the keys sent to a contact after a channel creation.
///
/// The helper walks two tables, the members and the pending members, so each test has one admin and one non-admin and puts
/// them in different tables; the second test swaps them. The owned identity is an admin in both: a sender that is not one
/// holds no key to send.
final class GroupV2AdminKeyForContactTests: XCTestCase {

    private var store: GroupV2TestStore!


    override func setUpWithError() throws {
        store = try GroupV2TestStore()
    }


    override func tearDownWithError() throws {
        store = nil
    }


    func testAnAdminMemberGetsTheKeyAndANonAdminPendingMemberDoesNot() throws {
        let group = try store.joinGroup(admins: [store.ownedCryptoIdentity, store.aliceCryptoIdentity], keys: store.keys(withAdminKey: true))
        try group.movePendingMemberToOtherMembers(pendingMemberCryptoIdentity: store.aliceCryptoIdentity)

        let toAlice = try keysSent(to: store.aliceCryptoIdentity)
        XCTAssertEqual(GroupV2TestStore.rawData(of: toAlice.groupAdminServerAuthenticationPrivateKey), GroupV2TestStore.rawData(of: store.adminKey))

        let toBob = try keysSent(to: store.bobCryptoIdentity)
        XCTAssertNil(toBob.groupAdminServerAuthenticationPrivateKey)
        XCTAssertEqual(toBob.blobMainSeed?.raw, store.mainSeed.raw)
        XCTAssertEqual(toBob.blobVersionSeed.raw, store.versionSeed.raw)
    }


    func testAnAdminPendingMemberGetsTheKeyAndANonAdminMemberDoesNot() throws {
        let group = try store.joinGroup(admins: [store.ownedCryptoIdentity, store.bobCryptoIdentity], keys: store.keys(withAdminKey: true))
        try group.movePendingMemberToOtherMembers(pendingMemberCryptoIdentity: store.aliceCryptoIdentity)

        let toAlice = try keysSent(to: store.aliceCryptoIdentity)
        XCTAssertNil(toAlice.groupAdminServerAuthenticationPrivateKey)
        XCTAssertEqual(toAlice.blobMainSeed?.raw, store.mainSeed.raw)
        XCTAssertEqual(toAlice.blobVersionSeed.raw, store.versionSeed.raw)

        let toBob = try keysSent(to: store.bobCryptoIdentity)
        XCTAssertEqual(GroupV2TestStore.rawData(of: toBob.groupAdminServerAuthenticationPrivateKey), GroupV2TestStore.rawData(of: store.adminKey))
    }


    // MARK: - Helpers

    /// What the batch keys message would carry for this contact. There is one group, so one entry.
    private func keysSent(to contact: ObvCryptoIdentity) throws -> GroupV2.BlobKeys {
        let obvContext = ObvContext(context: store.context, flowId: UUID(), file: #file, line: #line, function: #function)
        let entries = try store.identityManager.getAllGroupsV2IdentifierVersionAndKeysForContact(contact, ofOwnedIdentity: store.ownedCryptoIdentity, within: obvContext)
        XCTAssertEqual(entries.count, 1)
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.groupIdentifier, store.groupIdentifier)
        return entry.blobKeys
    }

}
