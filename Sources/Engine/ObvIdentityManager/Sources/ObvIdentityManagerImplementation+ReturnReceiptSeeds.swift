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
import CoreData
import ObvCrypto
import ObvMetaManager
import ObvTypes
import OSLog


extension ObvIdentityManagerImplementation {

    private static let loggerForReturnReceiptSeeds = Logger(subsystem: "io.olvid.identityManager", category: "ReturnReceiptSeeds")


    /// The seeds a batch of return receipts is encrypted with, one per receipt.
    ///
    /// The seed of a receipt depends on the owned identity and on the receipt's nonce, and a batch is nearly always
    /// one owned identity, so the owned identity is looked up once per distinct one rather than once per receipt.
    /// That lookup is a fetch plus a decode of the identity's encoded private keys, and it was most of what a receipt
    /// cost.
    ///
    /// A receipt whose owned identity is **not in the database** is absent from the answer, as it was before: it can
    /// never be encrypted, so the caller gives up on it. The answer is therefore not necessarily as long as the
    /// question.
    ///
    /// A lookup that fails for any other reason throws instead, and the whole batch is left for the caller to ask
    /// about again. The two must not be conflated: the caller reads an absent receipt as one it can delete, so a
    /// Core Data failure — on a store four processes write to — reported as an absence destroys receipts for good.
    public func getDeterministicSeedForReturnReceiptToSendEncryption(returnReceiptsToSend: [ObvReturnReceiptToSend]) async throws -> [(returnReceiptToSend: ObvReturnReceiptToSend, seed: Seed)] {

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[(returnReceiptToSend: ObvReturnReceiptToSend, seed: Seed)], any Error>) in

            delegateManager.contextCreator.performBackgroundTask { context in

                do {
                    let receiptsAndSeeds = try Self.deterministicSeeds(forReturnReceiptsToSend: returnReceiptsToSend) { ownedCryptoId in
                        guard let ownedIdentity = try OwnedIdentity.get(ownedCryptoId.cryptoIdentity, within: context) else {
                            // The profile is gone. Nothing can be encrypted for it, now or ever, and a deleted
                            // profile is an ordinary thing rather than a fault.
                            Self.loggerForReturnReceiptSeeds.error("An owned identity is not in the database, so its return receipts have no seed and can never be sent")
                            return nil
                        }
                        return try ownedIdentity.ownedCryptoIdentity.secretMACKey
                    }
                    continuation.resume(returning: receiptsAndSeeds)
                } catch {
                    Self.loggerForReturnReceiptSeeds.fault("Could not get the secret MAC key of an owned identity, so a batch of return receipts has no seed and is left where it is: \(error.localizedDescription, privacy: .public)")
                    assertionFailure()
                    continuation.resume(throwing: error)
                }

            }

        }

    }


    /// Computes one seed per receipt, asking for each owned identity's secret MAC key once.
    ///
    /// Takes the key lookup as a closure so that this holds no context and can be tested: what the tests check is
    /// that a receipt is given the seed of *its own* owned identity, and that a batch of a hundred receipts for one
    /// identity asks for that key once.
    ///
    /// - Parameter secretMACKeyForOwnedIdentity: nil when the identity is not there, which is permanent and drops its
    ///   receipts, the reason having been reported by the closure. A throw means the key could not be read this time,
    ///   and takes the whole batch with it rather than dropping anything. Nothing here asserts, so that a test can
    ///   reach both paths.
    static func deterministicSeeds(forReturnReceiptsToSend returnReceiptsToSend: [ObvReturnReceiptToSend], secretMACKeyForOwnedIdentity: (ObvCryptoId) throws -> (any MACKey)?) rethrows -> [(returnReceiptToSend: ObvReturnReceiptToSend, seed: Seed)] {

        // A key of nil is an identity that was asked about and is not there, which is why one dictionary answers both
        // "already asked" and "what the answer was". Two collections would be one memo kept in step by hand.
        var secretMACKeys = [ObvCryptoId: (any MACKey)?]()

        return try returnReceiptsToSend.compactMap { returnReceiptToSend in

            let ownedCryptoId = returnReceiptToSend.contactIdentifier.ownedCryptoId

            let alreadyAsked: (any MACKey)?
            if let answer = secretMACKeys[ownedCryptoId] {
                alreadyAsked = answer
            } else {
                alreadyAsked = try secretMACKeyForOwnedIdentity(ownedCryptoId)
                secretMACKeys[ownedCryptoId] = alreadyAsked
            }
            guard let secretMACKey = alreadyAsked else { return nil }

            guard let seed = try? OwnedIdentity.getDeterministicSeed(
                diversifiedUsing: returnReceiptToSend.elements.nonce,
                secretMACKey: secretMACKey,
                forProtocol: .encryptReturnReceipt) else {
                loggerForReturnReceiptSeeds.fault("Could not compute the seed of a return receipt, which is therefore dropped")
                return nil
            }

            return (returnReceiptToSend, seed)

        }

    }

}
