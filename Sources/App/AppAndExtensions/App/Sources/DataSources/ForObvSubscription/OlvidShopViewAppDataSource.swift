/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import ObvSubscription

@MainActor
final class OlvidShopViewAppDataSource {
    
    private var olvidShopViewModelStreamManagerForStreamUUID = [UUID: OlvidShopViewModelStreamManager]()

    
}


extension OlvidShopViewAppDataSource: OlvidShopViewDataSource {
    
    func getAsyncSequenceOfOlvidShopViewModel(_ view: ObvSubscription.OlvidShopView) throws -> (streamUUID: UUID, stream: AsyncStream<ObvSubscription.OlvidShopView.Model>) {
        let streamManager = OlvidShopViewModelStreamManager()
        let (streamUUID, stream) = try streamManager.startStream()
        self.olvidShopViewModelStreamManagerForStreamUUID[streamUUID] = streamManager
        return (streamUUID, stream)
    }
    
    func finishAsyncSequenceOfOlvidShopViewModel(_ view: ObvSubscription.OlvidShopView, streamUUID: UUID) {
        if let streamManager = olvidShopViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) {
            streamManager.finishStream()
        }
    }
    
}


extension OlvidShopViewAppDataSource {
    
    private final class OlvidShopViewModelStreamManager {
        
        private let streamUUID = UUID()
        private var continuation: AsyncStream<OlvidShopView.Model>.Continuation?
        
        func startStream() throws -> (streamUUID: UUID, stream: AsyncStream<OlvidShopView.Model>) {
            let stream = AsyncStream<OlvidShopView.Model> { (continuation: AsyncStream<OlvidShopView.Model>.Continuation) in
                self.continuation = continuation
                let model: OlvidShopView.Model = .init(productIDs: SubscriptionManager.ProductIdentifier.allProductIDs)
                continuation.yield(model)
            }
            return (streamUUID, stream)
        }
        
        func finishStream() {
            continuation?.finish()
            continuation = nil
        }
        
    }
    
}
