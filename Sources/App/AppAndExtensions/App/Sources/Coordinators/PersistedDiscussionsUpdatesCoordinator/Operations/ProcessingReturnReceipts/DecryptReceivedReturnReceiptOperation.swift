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
import ObvEngine
import ObvUICoreData
import ObvTypes


final class DecryptReceivedReturnReceiptOperation: AsyncOperationWithSpecificReasonForCancel<DecryptReceivedReturnReceiptOperation.ReasonForCancel>, @unchecked Sendable {
    
    private let encryptedReceivedReturnReceipt: ObvEncryptedReceivedReturnReceipt
    private let obvEngine: ObvEngine

    init(encryptedReceivedReturnReceipt: ObvEncryptedReceivedReturnReceipt, obvEngine: ObvEngine) {
        self.encryptedReceivedReturnReceipt = encryptedReceivedReturnReceipt
        self.obvEngine = obvEngine
        super.init()
    }

    private(set) var decryptedReceivedReturnReceipt: ObvDecryptedReceivedReturnReceipt?
    
    override func main() async {
        
        do {
            
            let decryptionKeyCandidates = try await Self.getDecryptionKeyCandidatesForReceivedReturnReceipt(encryptedReceivedReturnReceipt: encryptedReceivedReturnReceipt)
            
            decryptedReceivedReturnReceipt = try obvEngine.decryptPayloadOfObvReturnReceipt(encryptedReceivedReturnReceipt, decryptionKeyCandidates: decryptionKeyCandidates)
            
            return finish()
            
        } catch {
            assertionFailure()
            return cancel(withReason: .error(error: error))
        }
        
    }
    
    
    private static func getDecryptionKeyCandidatesForReceivedReturnReceipt(encryptedReceivedReturnReceipt: ObvEncryptedReceivedReturnReceipt) async throws -> Set<Data> {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Set<Data>, any Error>) in
            ObvStack.shared.performBackgroundTask { context in
                do {
                    let decryptionKeyCandidates = try PersistedMessageSentRecipientInfos.getDecryptionKeyCandidatesForReceivedReturnReceipt(
                        nonce: encryptedReceivedReturnReceipt.nonce,
                        ownedCryptoId: encryptedReceivedReturnReceipt.ownedCryptoId,
                        within: context)
                    return continuation.resume(returning: decryptionKeyCandidates)
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
