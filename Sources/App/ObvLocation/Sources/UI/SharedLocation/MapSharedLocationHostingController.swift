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

@preconcurrency import UIKit
import SwiftUI
import ObvUICoreData
import Combine
import ObvAppTypes

@available(iOS 17.0, *)
public final class MapSharedLocationHostingController: KeyboardHostingController<MapSharedLocationView> {
    
    // MARK: Attributes - Private - Notifications
    private var isRegisteredToNotifications = false
    private var observationTokens = [NSObjectProtocol]()
    public override var canBecomeFirstResponder: Bool { true }
    
    public init(ownedIdentity: PersistedObvOwnedIdentity,
                currentUserCanUseLocation: Bool,
                locationsPublisher: AnyPublisher<[PersistedLocationContinuous], Never>,
                centeredMessageId: TypeSafeManagedObjectID<PersistedMessage>? = nil) {
        let viewModel = MapSharedLocationViewModel(ownedIdentity: ownedIdentity,
                                                   currentUserCanUseLocation: currentUserCanUseLocation,
                                                   locationsPublisher: locationsPublisher,
                                                   centeredMessageId: centeredMessageId)
        let view = MapSharedLocationView(viewModel: viewModel)
        super.init(rootView: view)
    }
    
    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        registerForNotification()
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .systemGroupedBackground
    }
}

@available(iOS 17, *)
extension MapSharedLocationHostingController {

    private func registerForNotification() {
        guard !isRegisteredToNotifications else { return }
        isRegisteredToNotifications = true
        
        observationTokens.append(contentsOf: [
            KeyboardNotification.observeKeyboardDidInputEscapeKeyNotification { [weak self] in
                guard let self else { return }
                Task {
                    self.dismiss(animated: true, completion: nil)
                }
            },
        ])
    }
}


@available(iOS 17, *)
extension MapSharedLocationHostingController: UISheetPresentationControllerDelegate { }
