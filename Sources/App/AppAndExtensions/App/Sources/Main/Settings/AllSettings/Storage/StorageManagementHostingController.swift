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

import UIKit
import SwiftUI
import ObvUICoreData
import ObvAppTypes
import ObvTypes

@available(iOS 17.0, *)
final class StorageManagementHostingController: KeyboardHostingController<StorageManagerRouterView> {
    
    private var isRegisteredToNotifications = false
    private var observationTokens = [NSObjectProtocol]()
    override var canBecomeFirstResponder: Bool { true }
    
    init(currentOwnedCryptoId: ObvCryptoId) {
        let routerView = StorageManagerRouterView(currentOwnedCryptoId: currentOwnedCryptoId)
        super.init(rootView: routerView)
    }
    
    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        registerForNotification()
    }
    
    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }
}

@available(iOS 17.0, *)
extension StorageManagementHostingController {

    private func registerForNotification() {
        guard !isRegisteredToNotifications else { return }
        isRegisteredToNotifications = true
        
        observationTokens.append(contentsOf: [
            KeyboardNotification.observeKeyboardDidInputEscapeKeyNotification { [weak self] in
                OperationQueue.main.addOperation { [weak self] in
                    guard let self else { return }
                    self.dismiss(animated: true)
                }
            },
        ])
    }
}
