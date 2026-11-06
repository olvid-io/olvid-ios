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
import ObvEncoder
import ObvMetaManager
@testable import ObvProtocolManager


/// Checks the main-seed candidates a Group v2 invitation collects, on which the blob download depends.
///
/// ``GroupV2Protocol/ProcessInvitationOrMembersUpdateStep`` and ``GroupV2Protocol/InitiateBlobReDownloadStep`` query the server
/// only when ``GroupV2/InvitationCollectedData/inviterIdentityAndBlobMainSeedCandidates`` is not empty. A broadcast is
/// unauthenticated and names the server, so it must never make that set non-empty, while a known group always does.
///
/// No protocol step runs here. The keys are inserted as the steps insert them.
final class GroupV2MainSeedCandidateTests: XCTestCase {

    private let prng = ObvCryptoSuite.sharedInstance.prngService()
    private let serverURL = URL(string: "https://server.olvid.io")!

    private var ownedIdentity: ObvCryptoIdentity!
    private var alice: ObvCryptoIdentity!


    override func setUpWithError() throws {
        ownedIdentity = ObvOwnedCryptoIdentity.gen(withServerURL: serverURL, using: prng).getObvCryptoIdentity()
        alice = ObvOwnedCryptoIdentity.gen(withServerURL: serverURL, using: prng).getObvCryptoIdentity()
    }


    // MARK: - Unknown group

    func testABroadcastGivesNoMainSeedCandidate() throws {
        let broadcastKeys = GroupV2.BlobKeys(blobMainSeed: nil, blobVersionSeed: prng.genSeed(), groupAdminServerAuthenticationPrivateKey: nil)

        let collectedData = GroupV2.InvitationCollectedData()
            .insertingBlobKeysCandidates(broadcastKeys, fromInviter: nil)

        XCTAssertTrue(collectedData.inviterIdentityAndBlobMainSeedCandidates.isEmpty)
        XCTAssertEqual(collectedData.blobVersionSeedCandidates.map(\.raw), [broadcastKeys.blobVersionSeed.raw])
    }


    func testKeysWithoutAnInviterGiveNoMainSeedCandidateEvenWhenTheyCarryOne() throws {
        // A sender may put a main seed in a broadcast. The step passes such keys as they were received, with no inviter.
        let forgedKeys = GroupV2.BlobKeys(blobMainSeed: prng.genSeed(), blobVersionSeed: prng.genSeed(), groupAdminServerAuthenticationPrivateKey: nil)

        let collectedData = GroupV2.InvitationCollectedData()
            .insertingBlobKeysCandidates(forgedKeys, fromInviter: nil)

        XCTAssertTrue(collectedData.inviterIdentityAndBlobMainSeedCandidates.isEmpty)
    }


    func testAContactsKeysGiveAMainSeedCandidate() throws {
        let mainSeed = prng.genSeed()
        let contactKeys = GroupV2.BlobKeys(blobMainSeed: mainSeed, blobVersionSeed: prng.genSeed(), groupAdminServerAuthenticationPrivateKey: nil)

        let collectedData = GroupV2.InvitationCollectedData()
            .insertingBlobKeysCandidates(contactKeys, fromInviter: alice)

        XCTAssertEqual(collectedData.inviterIdentityAndBlobMainSeedCandidates[alice]?.raw, mainSeed.raw)
    }


    func testACandidateCarriedForwardThroughTheStateSurvivesABroadcast() throws {
        // INeedMoreSeedsState is saved between two messages, so the collected data goes through its encoding.
        let mainSeed = prng.genSeed()
        let contactKeys = GroupV2.BlobKeys(blobMainSeed: mainSeed, blobVersionSeed: prng.genSeed(), groupAdminServerAuthenticationPrivateKey: nil)
        let broadcastKeys = GroupV2.BlobKeys(blobMainSeed: nil, blobVersionSeed: prng.genSeed(), groupAdminServerAuthenticationPrivateKey: nil)
        let encoded = try GroupV2.InvitationCollectedData()
            .insertingBlobKeysCandidates(contactKeys, fromInviter: alice)
            .obvEncode()

        let collectedData = try XCTUnwrap(GroupV2.InvitationCollectedData(encoded))
            .insertingBlobKeysCandidates(broadcastKeys, fromInviter: nil)

        XCTAssertEqual(collectedData.inviterIdentityAndBlobMainSeedCandidates[alice]?.raw, mainSeed.raw)
        XCTAssertEqual(collectedData.blobVersionSeedCandidates.count, 2)
    }


    // MARK: - Known group

    func testAKnownGroupKeepsItsMainSeedCandidateAfterABroadcast() throws {
        // The steps credit the keys found in the database to the owned identity.
        let mainSeedInDatabase = prng.genSeed()
        let keysInDatabase = GroupV2.BlobKeys(blobMainSeed: mainSeedInDatabase, blobVersionSeed: prng.genSeed(), groupAdminServerAuthenticationPrivateKey: nil)
        let broadcastKeys = GroupV2.BlobKeys(blobMainSeed: nil, blobVersionSeed: prng.genSeed(), groupAdminServerAuthenticationPrivateKey: nil)

        let collectedData = GroupV2.InvitationCollectedData()
            .insertingBlobKeysCandidates(keysInDatabase, fromInviter: ownedIdentity)
            .insertingBlobKeysCandidates(broadcastKeys, fromInviter: nil)

        XCTAssertEqual(collectedData.inviterIdentityAndBlobMainSeedCandidates.count, 1)
        XCTAssertEqual(collectedData.inviterIdentityAndBlobMainSeedCandidates[ownedIdentity]?.raw, mainSeedInDatabase.raw)
    }

}
