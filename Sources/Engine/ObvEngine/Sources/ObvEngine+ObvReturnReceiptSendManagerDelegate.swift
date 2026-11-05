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
import ObvReturnReceiptSendManager
import ObvTypes
import OlvidUtils


extension ObvEngine: ObvReturnReceiptSendManagerDelegate {

    /// Everything this module asks of the engine is about identities, so each call is answered by the identity
    /// manager, which is the authority on them.
    public func getDeterministicSeedsForReturnReceiptEncryption(_ manager: ObvReturnReceiptSendManager, returnReceiptsToSend: [ObvReturnReceiptToSend]) async throws -> [(returnReceiptToSend: ObvReturnReceiptToSend, seed: Seed)] {

        // A throw, rather than an empty answer: no seed means nothing can be encrypted, and the module must hear that
        // as *ask again later* and not as *these receipts have no seed*. The second would drop them.
        guard let identityDelegate else { assertionFailure(); throw ObvError.identityDelegateIsNil }

        return try await identityDelegate.getDeterministicSeedForReturnReceiptToSendEncryption(returnReceiptsToSend: returnReceiptsToSend)

    }


    public func getDeviceUidsOfContacts(_ manager: ObvReturnReceiptSendManager, contactIdentifiers: Set<ObvContactIdentifier>, flowId: FlowIdentifier) async throws -> [ObvContactIdentifier: Set<UID>] {

        guard let createContextDelegate else { assertionFailure(); throw ObvError.createContextDelegateIsNil }
        guard let identityDelegate else { assertionFailure(); throw ObvError.identityDelegateIsNil }

        // A context is taken without waiting for one. The blocking form would hold a thread of the cooperative pool
        // for the whole of these fetches, and this is called from an actor on the path of every received message.
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[ObvContactIdentifier: Set<UID>], any Error>) in

            createContextDelegate.performBackgroundTask(flowId: flowId) { obvContext in

                var deviceUIDsOfContacts = [ObvContactIdentifier: Set<UID>]()
                var errorOfAContactThatCouldNotBeLookedUp: Error?

                for contactIdentifier in contactIdentifiers {
                    do {
                        guard let deviceUIDs = try identityDelegate.getDeviceUidsOfContactIdentityIfThisContactExists(
                            contactIdentifier.contactCryptoId.cryptoIdentity,
                            ofOwnedIdentity: contactIdentifier.ownedCryptoId.cryptoIdentity,
                            within: obvContext) else {
                            // The contact was deleted since the receipt was posted. No entry, so the module keeps the
                            // receipts until they are old enough to be given up on — and no error, because this is an
                            // answer about this contact. Counting it as a lookup failure would make a page whose
                            // contacts have all been deleted read as a database that would not answer, and the module
                            // keeps a receipt whatever its age when it hears that: the rows would outlive the install.
                            continue
                        }
                        deviceUIDsOfContacts[contactIdentifier] = deviceUIDs
                    } catch {
                        // This contact gets no entry at all, which is what tells the module to keep its receipts.
                        // Writing an empty set here would say the contact has no device, and would delete them.
                        self.logger.error("🧾 Could not get the devices of a contact, so its return receipts are kept: \(error.localizedDescription, privacy: .public)")
                        errorOfAContactThatCouldNotBeLookedUp = error
                    }
                }

                // Answering for nobody is not an answer about these contacts, it is a database that would not answer.
                // The module eventually gives up on a receipt whose contact is missing from the answer, so a failure
                // that happens to be total must reach it as a throw and not as a batch of contacts that all read as
                // deleted. A throw keeps every receipt, whatever its age. Deleted contacts do not bring this about:
                // they set no error, so a page of nothing but deleted contacts is an empty answer rather than a throw.
                if deviceUIDsOfContacts.isEmpty, let errorOfAContactThatCouldNotBeLookedUp {
                    self.logger.fault("🧾 Not one of \(contactIdentifiers.count) contacts could be looked up, so their return receipts are kept rather than being treated as contacts that no longer exist")
                    continuation.resume(throwing: errorOfAContactThatCouldNotBeLookedUp)
                    return
                }

                continuation.resume(returning: deviceUIDsOfContacts)

            }

        }

    }

}
