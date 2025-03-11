/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import OSLog
import OlvidUtils
import ObvTypes
import ObvUICoreData


/// When handling an encrypted return receipt, we first decrypt it and then execute this operation aiming at identifying necessary database modifications for accurate processing of the receipt.
/// This operation can run on a separate queue from the coordinator's, as it does not alter the database. However, it provides instructions by returning an instance of
/// `HintsForProcessingDecryptedRecievedReturnReceipt`. This object will be utilized in another operation to effectively manage the received return receipt and update the database.
final class ComputeHintsForGivenDecryptedReceivedReturnReceiptOperation: AsyncOperationWithSpecificReasonForCancel<ComputeHintsForGivenDecryptedReceivedReturnReceiptOperation.ReasonForCancel>, @unchecked Sendable {
    
    private let decryptedReceivedReturnReceipt: ObvDecryptedReceivedReturnReceipt
    
    init(decryptedReceivedReturnReceipt: ObvDecryptedReceivedReturnReceipt) {
        self.decryptedReceivedReturnReceipt = decryptedReceivedReturnReceipt
        super.init()
    }
    
    private(set) var hintsForProcessingDecryptedReceivedReturnReceipt: HintsForProcessingDecryptedReceivedReturnReceipt?
    
    override func main() async {
        
        do {
            hintsForProcessingDecryptedReceivedReturnReceipt = try await Self.processDecryptedReceivedReturnReceipt(decryptedReceivedReturnReceipt: decryptedReceivedReturnReceipt)
        } catch {
            assertionFailure()
        }
        
        return finish()
        
    }
    
    
    private static func processDecryptedReceivedReturnReceipt(decryptedReceivedReturnReceipt: ObvDecryptedReceivedReturnReceipt) async throws -> HintsForProcessingDecryptedReceivedReturnReceipt {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HintsForProcessingDecryptedReceivedReturnReceipt, any Error>) in
            ObvStack.shared.performBackgroundTask { context in
                do {
                    let hints = try PersistedMessageSentRecipientInfos.computeHintsForProcessingDecryptedReceivedReturnReceipt(decryptedReceivedReturnReceipt: decryptedReceivedReturnReceipt, within: context)
                    return continuation.resume(returning: hints)
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }
    }
    
    
    
    // MARK: - ReasonForCancel
    
    enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case error(error: Error)

        public var logType: OSLogType {
            switch self {
            case .error:
                return .fault
            }
        }

        public var errorDescription: String? {
            switch self {
            case .error(error: let error):
                return "error: \(error.localizedDescription)"
            }
        }

    }
    
}
