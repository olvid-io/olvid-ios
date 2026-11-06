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
@testable import ObvReturnReceiptSendManager


/// The engine, as far as this module is concerned: two methods about identities.
///
/// This is the reason the module declares a delegate of its own rather than holding `ObvIdentityDelegate`, which has
/// 194 methods and cannot be stood up without the engine.
final class FakeReturnReceiptSendManagerDelegate: ObvReturnReceiptSendManagerDelegate, @unchecked Sendable {

    /// What the delegate answers when asked for a contact's devices.
    enum DeviceAnswer {
        /// The contact has these devices.
        case theContactHasDevices(Set<UID>)
        /// The contact has no device. The receipt can never be sent.
        case theContactHasNoDevice
        /// This contact could not be looked up, and is left out of the answer.
        case theContactCannotBeLookedUp
    }

    private let lock = NSLock()
    private var deviceAnswers = [ObvContactIdentifier: DeviceAnswer]()
    private var deviceAnswerByDefault: DeviceAnswer = .theContactHasDevices([UID(uid: Data(repeating: 0x01, count: UID.length))!])

    /// Set to make the whole device lookup throw, which must leave every receipt in the batch where it is.
    var errorThrownByTheDeviceLookup: Error?
    /// Set to make the seed lookup throw.
    var errorThrownByTheSeedLookup: Error?
    /// Contacts whose receipts come back from the seed lookup with no seed at all.
    var contactsWithNoSeed = Set<ObvContactIdentifier>()

    private(set) var contactsAskedAbout = [Set<ObvContactIdentifier>]()
    private(set) var sizesOfTheSeedCalls = [Int]()

    func setDeviceAnswer(_ answer: DeviceAnswer, for contactIdentifier: ObvContactIdentifier) {
        lock.withLock { deviceAnswers[contactIdentifier] = answer }
    }

    func setDeviceAnswerByDefault(_ answer: DeviceAnswer) {
        lock.withLock { deviceAnswerByDefault = answer }
    }

    // MARK: - ObvReturnReceiptSendManagerDelegate

    func getDeterministicSeedsForReturnReceiptEncryption(_ manager: ObvReturnReceiptSendManager, returnReceiptsToSend: [ObvReturnReceiptToSend]) async throws -> [(returnReceiptToSend: ObvReturnReceiptToSend, seed: Seed)] {
        lock.withLock { sizesOfTheSeedCalls.append(returnReceiptsToSend.count) }
        if let errorThrownByTheSeedLookup { throw errorThrownByTheSeedLookup }
        // A receipt with no seed is absent from the answer, as the identity manager leaves it absent.
        return returnReceiptsToSend
            .filter { !contactsWithNoSeed.contains($0.contactIdentifier) }
            .map { ($0, ReturnReceiptTestFactory.seed()) }
    }


    func getDeviceUidsOfContacts(_ manager: ObvReturnReceiptSendManager, contactIdentifiers: Set<ObvContactIdentifier>, flowId: FlowIdentifier) async throws -> [ObvContactIdentifier: Set<UID>] {
        lock.withLock { contactsAskedAbout.append(contactIdentifiers) }
        if let errorThrownByTheDeviceLookup { throw errorThrownByTheDeviceLookup }
        var answer = [ObvContactIdentifier: Set<UID>]()
        for contactIdentifier in contactIdentifiers {
            switch lock.withLock({ deviceAnswers[contactIdentifier] ?? deviceAnswerByDefault }) {
            case .theContactHasDevices(let deviceUIDs):
                answer[contactIdentifier] = deviceUIDs
            case .theContactHasNoDevice:
                answer[contactIdentifier] = []
            case .theContactCannotBeLookedUp:
                continue // Left out, which is what says "not answered for"
            }
        }
        return answer
    }

}
