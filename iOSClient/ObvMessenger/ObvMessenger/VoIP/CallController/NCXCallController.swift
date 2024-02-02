/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import CallKit


protocol NCXCallControllerDelegate: AnyObject {
    func process(action: CXAction) async throws
}


actor NCXCallController: CallControllerProtocol {
    
    private weak var delegate: NCXCallControllerDelegate?
    
    func setDelegate(_ delegate: NCXCallControllerDelegate) {
        self.delegate = delegate
    }
    
    
    func request(_ transaction: CXTransaction) async throws {
        try await process(transaction.actions)
    }

    
    func requestTransaction(with action: CXAction) async throws {
        try await process([action])
    }
 
    
    func requestTransaction(with actions: [CXAction]) async throws {
        try await process(actions)
    }

}

// MARK: - Internal methods

extension NCXCallController {
    
    private func process(_ actions: [CXAction]) async throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        for action in actions {
            try await delegate.process(action: action)
        }
    }
    
}


// MARK: - Errors

extension NCXCallController {
    
    enum ObvError: Error {
        case delegateIsNil
    }
    
}
