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
import CallKit
import AVFoundation


protocol NCXProviderDelegate: AnyObject {
    
    // Handling Call Actions
    func provider(_ provider: NCXProvider, perform action: CXStartCallAction)
    func provider(_ provider: NCXProvider, perform action: CXAnswerCallAction)
    func provider(_ provider: NCXProvider, perform action: CXEndCallAction)
    func provider(_ provider: NCXProvider, perform action: CXSetMutedCallAction)

    // Handling Changes to Audio Session Activation State (only used in the CallKit case)
    func provider(_ provider: NCXProvider, didActivate audioSession: AVAudioSession)
    func provider(_ provider: NCXProvider, didDeactivate audioSession: AVAudioSession)

}





final class NCXProvider: CallProviderProtocol {
    
    private weak var delegate: NCXProviderDelegate?
    
    func setDelegate(_ delegate: NCXProviderDelegate) {
        self.delegate = delegate
    }


    func reportNewIncomingCall(with UUID: UUID, update: CXCallUpdate, completion: @escaping (Error?) -> Void) {
        // We do nothing
    }
    

    func reportOutgoingCall(with: UUID, startedConnectingAt: Date?) {
        // We do nothing
    }
    
    
    func reportOutgoingCall(with: UUID, connectedAt: Date?) {
        // We do nothing
    }
    
    
    func reportCall(with: UUID, updated: CXCallUpdate) {
        // We do nothing
    }
    
    
    func reportCall(with: UUID, endedAt: Date?, reason: CXCallEndedReason) {
        // We do nothing
    }
    
}


// MARK: - Implementing NCXCallControllerDelegate

extension NCXProvider: NCXCallControllerDelegate {
    
    func process(action: CXAction) async throws {
        
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        
        switch action {
        case let action as CXStartCallAction:
            delegate.provider(self, perform: action)
        case let action as CXAnswerCallAction:
            delegate.provider(self, perform: action)
        case let action as CXEndCallAction:
            delegate.provider(self, perform: action)
        case let action as CXSetMutedCallAction:
            delegate.provider(self, perform: action)
        default:
            assertionFailure("Not implemented (yet)")
        }

    }
    
}


// MARK: - Errors

extension NCXProvider {
    
    enum ObvError: Error {
        case delegateIsNil
    }
    
}
