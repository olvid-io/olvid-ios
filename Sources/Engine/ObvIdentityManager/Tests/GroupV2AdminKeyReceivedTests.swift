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
import XCTest
@testable import ObvIdentityManager


/// Checks what a receiver keeps of an admin key it is sent, on joining a group and on an update.
///
/// The key is kept only while the blob gives the owned identity the group-admin permission. The promotion case is the one
/// that decides where the check reads from: the key arrives in the same message as the blob that promotes, so a check against
/// the stored permissions, still the old ones, would drop it.
final class GroupV2AdminKeyReceivedTests: XCTestCase {

    private var store: GroupV2TestStore!


    override func setUpWithError() throws {
        store = try GroupV2TestStore()
    }


    override func tearDownWithError() throws {
        store = nil
    }


    // MARK: - Joining

    func testJoiningAsANonAdminDropsTheKeyItWasSent() throws {
        let group = try store.joinGroup(admins: [store.aliceCryptoIdentity], keys: store.keys(withAdminKey: true))

        let kept = try XCTUnwrap(group.blobKeys)
        XCTAssertNil(kept.groupAdminServerAuthenticationPrivateKey)
        XCTAssertEqual(kept.blobMainSeed?.raw, store.mainSeed.raw)
        XCTAssertEqual(kept.blobVersionSeed.raw, store.versionSeed.raw)
    }


    func testJoiningAsAnAdminKeepsTheKey() throws {
        let group = try store.joinGroup(admins: [store.ownedCryptoIdentity, store.aliceCryptoIdentity], keys: store.keys(withAdminKey: true))

        let kept = try XCTUnwrap(group.blobKeys)
        XCTAssertEqual(GroupV2TestStore.rawData(of: kept.groupAdminServerAuthenticationPrivateKey), GroupV2TestStore.rawData(of: store.adminKey))
    }


    // MARK: - Updating

    func testAPromotionKeepsTheKeySentWithIt() throws {
        let group = try store.joinGroup(admins: [store.aliceCryptoIdentity], keys: store.keys(withAdminKey: false))
        XCTAssertNil(group.blobKeys?.groupAdminServerAuthenticationPrivateKey)

        group.freeze()
        _ = try group.updateGroupV2(newBlobKeys: store.keys(withAdminKey: true),
                                    consolidatedServerBlob: try store.blob(version: 2, admins: [store.ownedCryptoIdentity, store.aliceCryptoIdentity]),
                                    groupUpdatedByOwnedIdentity: false,
                                    lastModificationTimestamp: .now)

        let kept = try XCTUnwrap(group.blobKeys)
        XCTAssertEqual(GroupV2TestStore.rawData(of: kept.groupAdminServerAuthenticationPrivateKey), GroupV2TestStore.rawData(of: store.adminKey))
    }


    func testAnUpdateReceivedAsANonAdminDropsTheKeyItWasSent() throws {
        let group = try store.joinGroup(admins: [store.aliceCryptoIdentity], keys: store.keys(withAdminKey: false))

        group.freeze()
        _ = try group.updateGroupV2(newBlobKeys: store.keys(withAdminKey: true),
                                    consolidatedServerBlob: try store.blob(version: 2, admins: [store.aliceCryptoIdentity]),
                                    groupUpdatedByOwnedIdentity: false,
                                    lastModificationTimestamp: .now)

        let kept = try XCTUnwrap(group.blobKeys)
        XCTAssertNil(kept.groupAdminServerAuthenticationPrivateKey)
        XCTAssertEqual(kept.blobMainSeed?.raw, store.mainSeed.raw)
        XCTAssertEqual(kept.blobVersionSeed.raw, store.versionSeed.raw)
    }


    func testADemotionDropsTheKeyEvenWhenItIsSentAgain() throws {
        let group = try store.joinGroup(admins: [store.ownedCryptoIdentity, store.aliceCryptoIdentity], keys: store.keys(withAdminKey: true))
        XCTAssertNotNil(group.blobKeys?.groupAdminServerAuthenticationPrivateKey)

        group.freeze()
        _ = try group.updateGroupV2(newBlobKeys: store.keys(withAdminKey: true),
                                    consolidatedServerBlob: try store.blob(version: 2, admins: [store.aliceCryptoIdentity]),
                                    groupUpdatedByOwnedIdentity: false,
                                    lastModificationTimestamp: .now)

        XCTAssertNil(try XCTUnwrap(group.blobKeys).groupAdminServerAuthenticationPrivateKey)
    }

}
