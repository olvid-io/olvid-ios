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

import XCTest
import ObvCrypto
import ObvTypes
@testable import ObvUICoreData


/// Checks what the app refuses a transferred or backed-up app node on: the owned identity the node names, decoded from its JSON and
/// compared with ``ObvCryptoId`` `==`. Restoring the node updates the owned identity it names, so a node naming another
/// profile on this device would update that profile.
///
/// The identities must differ on their full bytes: the same keys under another server URL are another identity.
///
/// The node is hand-made JSON holding the owned identity and an empty domain. The refusal itself is in the app target's
/// snapshot coordinator, which has no test target, and is not covered here.
final class AppSyncSnapshotNodeIdentityTests: XCTestCase {

    private let prng = ObvCryptoSuite.sharedInstance.prngService()
    private let serverURL = URL(string: "https://server.olvid.io")!


    func testTheDecodedIdentityIsTheOneTheNodeNames() throws {
        let ownedCryptoId = makeCryptoId()
        let node = try decodeNode(of: ownedCryptoId)
        XCTAssertTrue(node.ownedCryptoId == ownedCryptoId)
    }


    func testTheDecodedIdentityIsNotAnotherIdentity() throws {
        let node = try decodeNode(of: makeCryptoId())
        XCTAssertFalse(node.ownedCryptoId == makeCryptoId())
    }


    func testTheDecodedIdentityIsNotTheSameKeysUnderAnotherServer() throws {
        let ownedCryptoId = makeCryptoId()
        let sameKeysElsewhere = ObvCryptoId(cryptoIdentity: ObvCryptoIdentity(serverURL: URL(string: "https://elsewhere.example")!,
                                                                              publicKeyForAuthentication: ownedCryptoId.cryptoIdentity.publicKeyForAuthentication,
                                                                              publicKeyForPublicKeyEncryption: ownedCryptoId.cryptoIdentity.publicKeyForPublicKeyEncryption))
        let node = try decodeNode(of: ownedCryptoId)
        XCTAssertFalse(node.ownedCryptoId == sameKeysElsewhere)
    }


    // MARK: - Helpers

    private func makeCryptoId() -> ObvCryptoId {
        ObvCryptoId(cryptoIdentity: ObvOwnedCryptoIdentity.gen(withServerURL: serverURL, using: prng).getObvCryptoIdentity())
    }


    /// Decodes, as the app does, an app node naming `ownedCryptoId` and holding nothing else. The keys are the ones
    /// ``AppSyncSnapshotNode`` encodes, and the identity is Base64, as `JSONEncoder` writes `Data`.
    private func decodeNode(of ownedCryptoId: ObvCryptoId) throws -> AppSyncSnapshotNode {
        let json: [String: Any] = [
            "domain": [String](),
            "owned_identity": ownedCryptoId.getIdentity().base64EncodedString(),
        ]
        let serializedNode = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(AppSyncSnapshotNode.self, from: serializedNode)
    }

}
