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
import StoreKit
import SwiftUI
import ObvTypes


public final class SubscriptionPlansViewModel: SubscriptionPlansViewModelProtocol {
    
    public let ownedCryptoId: ObvCryptoId
    public let showFreePlanIfAvailable: Bool
    @Published public private(set) var freePlanIsAvailable: Bool? = nil
    @Published public private(set) var products: [Product]? = nil
    
    public init(ownedCryptoId: ObvCryptoId, showFreePlanIfAvailable: Bool) {
        self.ownedCryptoId = ownedCryptoId
        self.showFreePlanIfAvailable = showFreePlanIfAvailable
    }
    
    @MainActor
    public func setSubscriptionPlans(freePlanIsAvailable: Bool, products: [Product]) async {
        withAnimation(.bouncy) {
            self.freePlanIsAvailable = freePlanIsAvailable
            self.products = products
        }
    }
    
}
