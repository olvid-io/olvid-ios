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
import OlvidUtils


/// What this module needs from the engine, and the whole of it.
///
/// Everything here is about identities, and the engine answers each call by forwarding it to the identity manager.
/// The reason the module declares a protocol of its own rather than holding the identity delegate is that the latter
/// has 194 methods: a module holding one cannot be exercised without the engine, and being exercisable on its own is
/// most of the reason this is a module. A fake in a test implements this instead.
public protocol ObvReturnReceiptSendManagerDelegate: AnyObject {

    /// The seed each receipt's payload is encrypted with, so that the encryption is deterministic and the server can
    /// recognise a duplicate.
    ///
    /// A receipt for which no seed can be found is **absent from the answer**, rather than reported: that is the
    /// existing behaviour, kept. The answer is therefore not necessarily as long as the question.
    ///
    /// Throwing and answering nothing are not the same thing, and the difference decides what happens to a receipt.
    /// A throw means *ask again later*. Do not turn one into an empty answer.
    func getDeterministicSeedsForReturnReceiptEncryption(_ manager: ObvReturnReceiptSendManager, returnReceiptsToSend: [ObvReturnReceiptToSend]) async throws -> [(returnReceiptToSend: ObvReturnReceiptToSend, seed: Seed)]

    /// The devices of each contact, as the identity database has them now.
    ///
    /// Asked when a receipt is about to leave rather than when it is taken on, so a receipt that waited overnight goes
    /// to the devices the contact has this morning.
    ///
    /// Three answers, and they mean different things:
    /// - an entry with devices: send to those;
    /// - an entry with **no** devices: the contact has none, and the receipt can never be sent. Its row is deleted;
    /// - **no entry at all**: this contact could not be looked up. Its row is kept and asked about again later, until
    ///   it is old enough to be given up on — a contact that has not been answerable for thirty days is not one this
    ///   receipt is going to reach, and nothing else would ever delete the row.
    ///
    /// So a contact must be left out rather than given an empty set when the answer is not known. The empty set is the
    /// one answer that destroys a receipt nothing has tried to send, and it has to be an authoritative one. Throwing
    /// keeps every receipt in the batch, whatever its age.
    ///
    /// Because a missing contact is eventually given up on, an implementation that catches per contact must tell a
    /// contact it cannot answer for from a database that will not answer at all: a total failure reported as a batch
    /// of missing contacts reads here as a batch of contacts that no longer exist. Throw in that case.
    func getDeviceUidsOfContacts(_ manager: ObvReturnReceiptSendManager, contactIdentifiers: Set<ObvContactIdentifier>, flowId: FlowIdentifier) async throws -> [ObvContactIdentifier: Set<UID>]

}
