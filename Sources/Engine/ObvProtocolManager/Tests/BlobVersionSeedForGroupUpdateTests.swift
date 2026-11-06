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


/// Checks the version seed an admin encrypts an updated group blob with, once the server's log entries are applied.
///
/// A member who left or declined signs a log entry with their invitation nonce, and the consolidation removes them from the
/// blob. They still hold the version seed of the blob they left. So an update that reuses that seed must not happen when the log
/// entries removed somebody, even when the changeset removes nobody.
///
/// No protocol step runs here. The decision is a static function of the step, fed a blob built in the test and the member set the
/// identity manager would answer. The administrators chain is decoded from a hand-made block: nothing checks its signature, and
/// the decision does not read it.
final class BlobVersionSeedForGroupUpdateTests: XCTestCase {

    private let prng = ObvCryptoSuite.sharedInstance.prngService()
    private let serverURL = URL(string: "https://server.olvid.io")!

    private var admin: ObvOwnedCryptoIdentity!
    private var alice: ObvOwnedCryptoIdentity!
    private var bob: ObvOwnedCryptoIdentity!

    private var groupIdentifier: GroupV2.Identifier!
    private var administratorsChain: GroupV2.AdministratorsChain!

    private var aliceNonce: Data!
    private var bobNonce: Data!

    private var currentSeed: Seed!


    override func setUpWithError() throws {
        admin = ObvOwnedCryptoIdentity.gen(withServerURL: serverURL, using: prng)
        alice = ObvOwnedCryptoIdentity.gen(withServerURL: serverURL, using: prng)
        bob = ObvOwnedCryptoIdentity.gen(withServerURL: serverURL, using: prng)
        administratorsChain = try XCTUnwrap(Self.chain(startedBy: admin.getObvCryptoIdentity(), prng: prng))
        groupIdentifier = GroupV2.Identifier(groupUID: administratorsChain.groupUID, serverURL: serverURL, category: .server)
        aliceNonce = prng.genBytes(count: 16)
        bobNonce = prng.genBytes(count: 16)
        currentSeed = prng.genSeed()
    }


    // MARK: - The decision

    func testALeaverInTheLogEntriesGivesAFreshSeedWhenTheChangesetRemovesNobody() throws {
        let serverBlob = blob(with: [alice, bob])
        let logEntries: Set<Data> = [try leaveEntry(signedBy: bob, nonce: bobNonce)]

        let decision = decide(serverBlob: serverBlob, logEntries: logEntries, strategy: .keepCurrentBlobVersionSeed)

        guard case .freshBecauseMembersLeftOrDeclined(let seed) = decision else {
            return XCTFail("The current seed was kept although Bob left")
        }
        XCTAssertNotEqual(seed.raw, currentSeed.raw)
    }


    func testNoLogEntryKeepsTheCurrentSeed() throws {
        let serverBlob = blob(with: [alice, bob])

        let decision = decide(serverBlob: serverBlob, logEntries: [], strategy: .keepCurrentBlobVersionSeed)

        guard case .chosenWhenTheUpdateStarted(let seed) = decision else {
            return XCTFail("A fresh seed was drawn although nobody left")
        }
        XCTAssertEqual(seed.raw, currentSeed.raw)
    }


    func testALeaverInTheLogEntriesGivesAFreshSeedEvenWhenOneWasPreShot() throws {
        // The pre-shot seed was sent to the members in the identity manager, Bob included: it is not safe either.
        let preShotSeed = prng.genSeed()
        let serverBlob = blob(with: [alice, bob])
        let logEntries: Set<Data> = [try leaveEntry(signedBy: bob, nonce: bobNonce)]

        let decision = decide(serverBlob: serverBlob, logEntries: logEntries, strategy: .preShotBlobVersionSeed(seed: preShotSeed))

        guard case .freshBecauseMembersLeftOrDeclined(let seed) = decision else {
            return XCTFail("The pre-shot seed was kept although Bob left after receiving it")
        }
        XCTAssertNotEqual(seed.raw, preShotSeed.raw)
        XCTAssertNotEqual(seed.raw, currentSeed.raw)
    }


    func testAMemberRemovedByTheChangesetIsNotALeaver() throws {
        // The blob compared is the one before the changeset, so Bob is still in it. The pre-shot seed was not sent to him and stays valid.
        let preShotSeed = prng.genSeed()
        let serverBlob = blob(with: [alice, bob])

        let decision = decide(serverBlob: serverBlob, logEntries: [], strategy: .preShotBlobVersionSeed(seed: preShotSeed))

        guard case .chosenWhenTheUpdateStarted(let seed) = decision else {
            return XCTFail("A second seed was drawn for a member the changeset removes")
        }
        XCTAssertEqual(seed.raw, preShotSeed.raw)
    }


    func testALeaverAlreadyDroppedLocallyGivesAFreshSeed() throws {
        // The admin processed Bob's departure before this update: Bob is out of the identity manager, but he is still in the server
        // blob next to his entry, and he holds the seed that decrypts that blob.
        let serverBlob = blob(with: [alice, bob])
        let logEntries: Set<Data> = [try leaveEntry(signedBy: bob, nonce: bobNonce)]

        let decision = decide(serverBlob: serverBlob, logEntries: logEntries, strategy: .keepCurrentBlobVersionSeed, membersInLocalBlob: [alice])

        guard case .freshBecauseMembersLeftOrDeclined(let seed) = decision else {
            return XCTFail("The current seed was kept although Bob, who holds it, left")
        }
        XCTAssertNotEqual(seed.raw, currentSeed.raw)
    }


    func testALeaverAlreadyDroppedLocallyKeepsAPreShotSeedHeNeverReceived() throws {
        // Same departure, but this update removes a member: the pre-shot went to the identity manager's members, so not to Bob.
        let preShotSeed = prng.genSeed()
        let serverBlob = blob(with: [alice, bob])
        let logEntries: Set<Data> = [try leaveEntry(signedBy: bob, nonce: bobNonce)]

        let decision = decide(serverBlob: serverBlob, logEntries: logEntries, strategy: .preShotBlobVersionSeed(seed: preShotSeed), membersInLocalBlob: [alice])

        guard case .chosenWhenTheUpdateStarted(let seed) = decision else {
            return XCTFail("A second seed was drawn although Bob never received the pre-shot")
        }
        XCTAssertEqual(seed.raw, preShotSeed.raw)
    }


    func testALogEntrySignedWithAnotherNonceRemovesNobody() throws {
        let serverBlob = blob(with: [alice, bob])
        let logEntries: Set<Data> = [try leaveEntry(signedBy: bob, nonce: prng.genBytes(count: 16))]

        let decision = decide(serverBlob: serverBlob, logEntries: logEntries, strategy: .keepCurrentBlobVersionSeed)

        guard case .chosenWhenTheUpdateStarted(let seed) = decision else {
            return XCTFail("An entry that matches no member's nonce removed somebody")
        }
        XCTAssertEqual(seed.raw, currentSeed.raw)
    }


    // MARK: - Helpers

    /// Applies the log entries as the step does, then asks the decision. Unless said otherwise, the identity manager holds Alice and
    /// Bob, as it does for an admin who has not yet learnt that one of them left.
    private func decide(serverBlob: GroupV2.ServerBlob, logEntries: Set<Data>, strategy: GroupV2Protocol.EncryptionSeedStrategy, membersInLocalBlob: [ObvOwnedCryptoIdentity]? = nil) -> GroupV2Protocol.PrepareBlobForGroupUpdateStep.BlobVersionSeedForUpload {
        let previousServerBlob = serverBlob.consolidateWithLogEntries(groupIdentifier: groupIdentifier, logEntries)
        return GroupV2Protocol.PrepareBlobForGroupUpdateStep.blobVersionSeedForUpload(
            encryptionSeedStrategy: strategy,
            versionSeedThatAllowedToDecryptTheBlob: currentSeed,
            membersInLocalBlob: Set((membersInLocalBlob ?? [alice, bob]).map({ $0.getObvCryptoIdentity() })),
            serverBlobAsDownloaded: serverBlob,
            serverBlobAfterLogEntries: previousServerBlob,
            ownedIdentity: admin.getObvCryptoIdentity(),
            prng: prng)
    }


    private func blob(with members: [ObvOwnedCryptoIdentity]) -> GroupV2.ServerBlob {
        var groupMembers: Set<GroupV2.IdentityAndPermissionsAndDetails> = [
            .init(identity: admin.getObvCryptoIdentity(), rawPermissions: ["ga"], serializedIdentityCoreDetails: Data(), groupInvitationNonce: prng.genBytes(count: 16)),
        ]
        for member in members {
            let nonce: Data = (member === alice) ? aliceNonce : bobNonce
            groupMembers.insert(.init(identity: member.getObvCryptoIdentity(), rawPermissions: [], serializedIdentityCoreDetails: Data(), groupInvitationNonce: nonce))
        }
        return GroupV2.ServerBlob(administratorsChain: administratorsChain,
                                  groupMembers: groupMembers,
                                  groupVersion: 1,
                                  serializedGroupCoreDetails: Data(),
                                  serverPhotoInfo: nil,
                                  serializedGroupType: nil)
    }


    /// The entry a member puts on the server when leaving or declining: their invitation nonce, signed with their authentication key.
    private func leaveEntry(signedBy member: ObvOwnedCryptoIdentity, nonce: Data) throws -> Data {
        let challenge = ChallengeType.groupLeaveNonce(groupIdentifier: groupIdentifier, groupInvitationNonce: nonce)
        return try XCTUnwrap(ObvSolveChallengeStruct.solveChallenge(challenge, with: member.privateKeyForAuthentication, using: prng))
    }


    /// A one-block chain decoded from hand-made data. The block's signature is empty: nothing here checks the chain's integrity.
    private static func chain(startedBy admin: ObvCryptoIdentity, prng: PRNGService) -> GroupV2.AdministratorsChain? {
        let previousBlockHash = prng.genBytes(count: 32)
        let innerData = [previousBlockHash.obvEncode(), [admin.obvEncode()].obvEncode()].obvEncode()
        let block = [innerData, Data().obvEncode()].obvEncode()
        return GroupV2.AdministratorsChain([block].obvEncode())
    }

}
