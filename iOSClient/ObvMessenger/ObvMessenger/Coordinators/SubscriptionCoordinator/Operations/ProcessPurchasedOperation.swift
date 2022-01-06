/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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
import StoreKit
import os.log
import OlvidUtils

final class ProcessPurchasedOperation: OperationWithSpecificReasonForCancel<ProcessPurchasedOperationReasonForCancel> {
        
    private let transaction: SKPaymentTransaction
    private weak var delegate: PaymentOperationsDelegate?
    
    
    init(transaction: SKPaymentTransaction, delegate: PaymentOperationsDelegate) {
        self.transaction = transaction
        self.delegate = delegate
        super.init()
    }
    
    override func main() {
        
        guard let transactionIdentifier = transaction.transactionIdentifier else { return cancel(withReason: .paymentTransactionHasNoIdentifier) }
        guard let appStoreReceiptURL = Bundle.main.appStoreReceiptURL else { return cancel(withReason: .noAppStoreReceiptURL) }
        guard FileManager.default.fileExists(atPath: appStoreReceiptURL.path) else { return cancel(withReason: .noFileAtAppStoreReceiptURL) }
        let rawReceiptData: Data
        do {
            rawReceiptData = try Data(contentsOf: appStoreReceiptURL, options: .alwaysMapped)
        } catch {
            return cancel(withReason: .couldNotReadReceipt(error: error))
        }
        let receiptData = rawReceiptData.base64EncodedString(options: [])
        delegate?.processAppStorePurchase(receiptData: receiptData, transactionIdentifier: transactionIdentifier, transaction: transaction)
    }
    
}

enum ProcessPurchasedOperationReasonForCancel: LocalizedErrorWithLogType {
    case noAppStoreReceiptURL
    case noFileAtAppStoreReceiptURL
    case couldNotReadReceipt(error: Error)
    case paymentTransactionHasNoIdentifier
    
    var logType: OSLogType {
        switch self {
        case .noAppStoreReceiptURL, .noFileAtAppStoreReceiptURL, .couldNotReadReceipt, .paymentTransactionHasNoIdentifier:
            return .fault
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .noAppStoreReceiptURL: return "The AppStoreReceiptURL is nil"
        case .noFileAtAppStoreReceiptURL: return "Could not find receipt file at the AppStoreReceiptURL"
        case .couldNotReadReceipt(error: let error): return "Could not read receipt data: \(error.localizedDescription)"
        case .paymentTransactionHasNoIdentifier: return "The Payment transaction has no identifier, which is unexpected for a purchase"
        }
    }
    
}
