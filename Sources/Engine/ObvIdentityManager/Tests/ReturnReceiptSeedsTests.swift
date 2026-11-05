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

import Foundation
import ObvCrypto
import ObvTypes
import XCTest
@testable import ObvIdentityManager


/// The seeds a batch of return receipts is encrypted with.
///
/// Two things are checked: that each receipt gets the seed of its own owned identity, and that the owned identity is
/// asked for once per distinct one rather than once per receipt. The second is why the code was changed; the first is
/// what the change could have broken.
final class ReturnReceiptSeedsTests: XCTestCase {

    private static let prng = ObvCryptoSuite.sharedInstance.prngService()
    private static let server = URL(string: "https://server.test")!

    /// An owned identity, and the secret MAC key its seeds are derived from.
    private struct Owner {
        let cryptoId: ObvCryptoId
        let secretMACKey: any MACKey
    }

    private func makeOwner() -> Owner {
        let owned = ObvOwnedCryptoIdentity.gen(withServerURL: Self.server, using: Self.prng)
        return .init(cryptoId: ObvCryptoId(cryptoIdentity: owned.getObvCryptoIdentity()), secretMACKey: owned.secretMACKey)
    }

    private func receipt(of owner: Owner) -> ObvReturnReceiptToSend {
        let contact = ObvCryptoId(cryptoIdentity: ObvOwnedCryptoIdentity.gen(withServerURL: Self.server, using: Self.prng).getObvCryptoIdentity())
        return .init(elements: .init(nonce: Self.prng.genBytes(count: 16), key: Data(repeating: 0x2a, count: 32)),
                     status: .delivered,
                     contactIdentifier: .init(contactCryptoId: contact, ownedCryptoId: owner.cryptoId),
                     attachmentNumber: nil)
    }

    /// Counts what it is asked for, so that a test can tell one lookup per identity from one per receipt.
    private final class KeyLookup {
        private let owners: [ObvCryptoId: any MACKey]
        private(set) var asked = [ObvCryptoId]()
        init(_ owners: [Owner]) {
            self.owners = Dictionary(uniqueKeysWithValues: owners.map { ($0.cryptoId, $0.secretMACKey) })
        }
        func key(for ownedCryptoId: ObvCryptoId) -> (any MACKey)? {
            asked.append(ownedCryptoId)
            return owners[ownedCryptoId]
        }
    }

    /// The seed of one receipt, computed on its own — what the code did before, once per receipt.
    private func seedComputedOnItsOwn(for returnReceiptToSend: ObvReturnReceiptToSend, of owner: Owner) throws -> Seed {
        try OwnedIdentity.getDeterministicSeed(
            diversifiedUsing: returnReceiptToSend.elements.nonce,
            secretMACKey: owner.secretMACKey,
            forProtocol: .encryptReturnReceipt)
    }

    // MARK: - The seeds are the same ones

    /// A batch of several owned identities, interleaved. Every receipt must get the seed it would have got when each
    /// was computed on its own — a grouping that handed a receipt its neighbour's seed would encrypt it under a key
    /// the contact cannot recognise, and nothing downstream would notice.
    func testTheSeedsOfAMixedBatchAreTheOnesEachReceiptWouldHaveGotOnItsOwn() throws {

        let first = makeOwner()
        let second = makeOwner()
        let third = makeOwner()
        let receipts = [receipt(of: first), receipt(of: second), receipt(of: first), receipt(of: third), receipt(of: second)]
        let owners = [first, second, first, third, second]
        let lookup = KeyLookup([first, second, third])

        let receiptsAndSeeds = ObvIdentityManagerImplementation.deterministicSeeds(forReturnReceiptsToSend: receipts, secretMACKeyForOwnedIdentity: lookup.key(for:))

        XCTAssertEqual(receiptsAndSeeds.count, receipts.count)
        for (index, receiptAndSeed) in receiptsAndSeeds.enumerated() {
            XCTAssertEqual(receiptAndSeed.returnReceiptToSend.elements.nonce, receipts[index].elements.nonce, "The receipts came back in a different order")
            // Compared as bytes. `Seed` is an `NSObject` that defines `==` but never overrides `isEqual:`, and
            // `XCTAssertEqual` on an `NSObject` goes through `isEqual:` — so comparing two `Seed`s here compares the
            // objects and not the seeds, and every assertion passes or fails for the wrong reason.
            XCTAssertEqual(receiptAndSeed.seed.raw, try seedComputedOnItsOwn(for: receipts[index], of: owners[index]).raw)
        }

    }


    /// Two receipts of one owned identity differ only by their nonce, and must not share a seed: the nonce is what
    /// makes the encryption of each receipt its own.
    func testTwoReceiptsOfOneOwnedIdentityGetDifferentSeeds() throws {
        let owner = makeOwner()
        let receipts = [receipt(of: owner), receipt(of: owner)]
        let lookup = KeyLookup([owner])

        let receiptsAndSeeds = ObvIdentityManagerImplementation.deterministicSeeds(forReturnReceiptsToSend: receipts, secretMACKeyForOwnedIdentity: lookup.key(for:))

        XCTAssertEqual(receiptsAndSeeds.count, 2)
        // As bytes, for the reason given above — and here it is what makes the test mean anything at all: two
        // distinct `Seed` objects are never `isEqual:`, so this would pass whatever the seeds were.
        XCTAssertNotEqual(receiptsAndSeeds[0].seed.raw, receiptsAndSeeds[1].seed.raw)
    }

    // MARK: - The owned identity is looked up once

    /// The reason for the change: a hundred receipts of one owned identity cost one lookup, where they used to cost a
    /// fetch and a decode of that identity's private keys each.
    func testABatchOfOneOwnedIdentityLooksItUpOnce() throws {
        let owner = makeOwner()
        let receipts = (0..<100).map { _ in receipt(of: owner) }
        let lookup = KeyLookup([owner])

        let receiptsAndSeeds = ObvIdentityManagerImplementation.deterministicSeeds(forReturnReceiptsToSend: receipts, secretMACKeyForOwnedIdentity: lookup.key(for:))

        XCTAssertEqual(receiptsAndSeeds.count, 100)
        XCTAssertEqual(lookup.asked, [owner.cryptoId])
    }


    func testAMixedBatchLooksUpEachOwnedIdentityOnce() throws {
        let first = makeOwner()
        let second = makeOwner()
        let receipts = [receipt(of: first), receipt(of: second), receipt(of: first), receipt(of: second), receipt(of: first)]
        let lookup = KeyLookup([first, second])

        _ = ObvIdentityManagerImplementation.deterministicSeeds(forReturnReceiptsToSend: receipts, secretMACKeyForOwnedIdentity: lookup.key(for:))

        XCTAssertEqual(lookup.asked.count, 2)
        XCTAssertEqual(Set(lookup.asked), [first.cryptoId, second.cryptoId])
    }

    // MARK: - An owned identity that cannot be read

    /// A receipt whose owned identity cannot be read is dropped, as it was before. Its identity is asked for once and
    /// not once per receipt, so a profile being deleted mid-batch costs one failed fetch rather than one per receipt,
    /// and the receipts of the other identities are unaffected.
    func testTheReceiptsOfAnOwnedIdentityWithoutAKeyAreDroppedAndItIsAskedForOnce() throws {
        let known = makeOwner()
        let unknown = makeOwner()
        let receipts = [receipt(of: known), receipt(of: unknown), receipt(of: known), receipt(of: unknown)]
        let lookup = KeyLookup([known])

        let receiptsAndSeeds = ObvIdentityManagerImplementation.deterministicSeeds(forReturnReceiptsToSend: receipts, secretMACKeyForOwnedIdentity: lookup.key(for:))

        XCTAssertEqual(receiptsAndSeeds.count, 2, "Only the receipts of the identity that could be read come back")
        XCTAssertEqual(Set(receiptsAndSeeds.map { $0.returnReceiptToSend.contactIdentifier.ownedCryptoId }), [known.cryptoId])
        XCTAssertEqual(lookup.asked.count, 2, "Each identity is asked for once, the one without a key included")
    }


    /// A key that cannot be read *this time* is not an owned identity that is gone, and conflating the two destroys
    /// receipts: the caller deletes the row of every receipt that comes back without a seed. So a failed lookup takes
    /// the whole batch with it — the caller asks again later — rather than dropping anything.
    func testAKeyLookupThatThrowsTakesTheWholeBatchRatherThanDroppingItsReceipts() throws {

        struct TheDatabaseWouldNotAnswer: Error {}
        let owner = makeOwner()
        let receipts = [receipt(of: owner), receipt(of: owner)]

        XCTAssertThrowsError(
            try ObvIdentityManagerImplementation.deterministicSeeds(forReturnReceiptsToSend: receipts) { _ in
                throw TheDatabaseWouldNotAnswer()
            },
            "The batch came back short instead, and every receipt missing from it is a row the caller deletes"
        ) { error in
            XCTAssertTrue(error is TheDatabaseWouldNotAnswer)
        }

    }


    func testAnEmptyBatchAsksForNothing() throws {
        let lookup = KeyLookup([])
        let receiptsAndSeeds = ObvIdentityManagerImplementation.deterministicSeeds(forReturnReceiptsToSend: [], secretMACKeyForOwnedIdentity: lookup.key(for:))
        XCTAssertTrue(receiptsAndSeeds.isEmpty)
        XCTAssertTrue(lookup.asked.isEmpty)
    }

}
