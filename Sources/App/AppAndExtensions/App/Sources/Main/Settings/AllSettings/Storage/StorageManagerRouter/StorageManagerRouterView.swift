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
import SwiftUI
import ObvTypes

/// View containing the necessary SwiftUI
/// code to utilize a NavigationStack for
/// navigation accross our views.
@available(iOS 17.0, *)
struct StorageManagerRouterView: View {
    
    @State var router: StorageManagerRouter = StorageManagerRouter()
    
    private let currentOwnedCryptoId: ObvCryptoId
    
    private let rootViewModel: StorageManagementViewModel
    
    init(currentOwnedCryptoId: ObvCryptoId) {
        self.currentOwnedCryptoId = currentOwnedCryptoId
        self.rootViewModel = StorageManagementViewModel(ownedCryptoId: currentOwnedCryptoId, cacheManager: DiscussionCacheManager())
    }
    
    var body: some View {
        
//        let _ = Self._printChanges() // Use to print changes to observable
        
        NavigationStack(path: $router.path) {
            router.view(for: .root(model: rootViewModel))
                .navigationDestination(for: StorageManagerRouter.Route.self) { route in
                    router.view(for: route)
                }
        }
        .sheet(item: $router.presentingSheet) { route in
            router.view(for: route, type: .sheet)
        }
        .fullScreenCover(item: $router.presentingFullScreenCover) { route in
            router.view(for: route, type: .fullScreenCover)
        }
    }
    
    public func dismiss() -> Bool {
        return router.dismiss()
    }
}
