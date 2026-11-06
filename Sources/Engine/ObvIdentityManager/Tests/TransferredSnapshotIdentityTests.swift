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
import ObvTypes
import OlvidUtils
import XCTest
@testable import ObvIdentityManager


/// Checks that the identity node of a transferred snapshot is refused unless it is the snapshot of the identity the target
/// expects, the one bound by the commitment and the SAS.
///
/// The node is the real one the source would send for the store's owned identity, serialized as the identity manager does.
/// The identities are compared on their full bytes: the same keys under another server URL are another identity.
///
/// These tests check the identity manager's decoding only. That the transfer protocol's target step names the transferred
/// identity when it decodes the snapshot is not covered: nothing here runs a protocol step.
final class TransferredSnapshotIdentityTests: XCTestCase {

    private var store: GroupV2TestStore!


    override func setUpWithError() throws {
        store = try GroupV2TestStore()
    }


    override func tearDownWithError() throws {
        store = nil
    }


    func testTheSnapshotOfTheExpectedIdentityIsAccepted() throws {
        let node = try decode(serializedNode(), expecting: store.ownedCryptoIdentity)
        let identityNode = try XCTUnwrap(node as? ObvIdentityManagerSyncSnapshotNode)
        XCTAssertEqual(identityNode.ownedCryptoIdentity.getIdentity(), store.ownedCryptoIdentity.getIdentity())
    }


    func testTheSnapshotOfAnotherIdentityIsRefused() throws {
        let other = ObvOwnedCryptoIdentity.gen(withServerURL: store.serverURL, using: store.prng).getObvCryptoIdentity()
        XCTAssertThrowsError(try decode(serializedNode(), expecting: other)) { error in
            guard case ObvIdentityManagerError.unexpectedOwnedIdentity = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }


    func testTheSnapshotOfTheSameKeysUnderAnotherServerIsRefused() throws {
        let sameKeysElsewhere = ObvCryptoIdentity(serverURL: URL(string: "https://elsewhere.example")!,
                                                  publicKeyForAuthentication: store.ownedCryptoIdentity.publicKeyForAuthentication,
                                                  publicKeyForPublicKeyEncryption: store.ownedCryptoIdentity.publicKeyForPublicKeyEncryption)
        XCTAssertNotEqual(sameKeysElsewhere.getIdentity(), store.ownedCryptoIdentity.getIdentity())
        XCTAssertThrowsError(try decode(serializedNode(), expecting: sameKeysElsewhere)) { error in
            guard case ObvIdentityManagerError.unexpectedOwnedIdentity = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }


    // MARK: - Helpers

    /// The identity node the source sends for the store's owned identity.
    private func serializedNode() throws -> Data {
        let obvContext = ObvContext(context: store.context, flowId: UUID(), file: #file, line: #line, function: #function)
        let node = try ObvIdentityManagerSyncSnapshotNode(ownedCryptoIdentity: store.ownedCryptoIdentity, within: obvContext)
        return try store.identityManager.serializeObvSyncSnapshotNode(node)
    }


    /// Decodes the node as the target of a transfer does, expecting the snapshot of `expectedIdentity`.
    private func decode(_ serializedNode: Data, expecting expectedIdentity: ObvCryptoIdentity) throws -> any ObvSyncSnapshotNode {
        try store.identityManager.deserializeObvSyncSnapshotNode(serializedNode, context: .transfer(ownedCryptoId: ObvCryptoId(cryptoIdentity: expectedIdentity)))
    }

}
