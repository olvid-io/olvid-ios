/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import ObvDesignSystem
import ObvTypes


@available(iOS 17.0, *)
@MainActor
public protocol ObvMapViewControllerActionsProtocol: AnyObject {
    func userWantsToDismissObvMapView(_ vc: ObvMapViewController)
}


/// This `UIHostingController` displays a map allowing to consult the locations shared with the current device.
/// It is up to the `ObvMapViewControllerDataSource` to decide which locations are actually shown on the map.
/// For example, depending on the data source, we can restrict to showing locations shared by the participants of a discussion,
/// or to restrict to all the contacts of the current owned identity.
@available(iOS 17.0, *)
public final class ObvMapViewController: UIHostingController<ObvMapView> {
    
    fileprivate weak var actions: ObvMapViewControllerActionsProtocol?
    private let actionsForView = ActionsForView()
    
    public init(kind: ObvMapViewKind,
                dataSource: ObvMapViewDataSource,
                avatarViewDataSource: ObvAvatarViewDataSource,
                actions: ObvMapViewControllerActionsProtocol,
                initialDeviceIdentifierToSelect: ObvDeviceIdentifier? = nil) {
        self.actions = actions
        let rootView = ObvMapView(kind: kind,
                                  dataSource: dataSource,
                                  avatarViewDataSource: avatarViewDataSource,
                                  actions: actionsForView,
                                  initialDeviceIdentifierToSelect: initialDeviceIdentifierToSelect)
        super.init(rootView: rootView)
        self.actionsForView.viewController = self
    }
    
    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}


@available(iOS 17, *)
extension ObvMapViewController: UISheetPresentationControllerDelegate { }


@available(iOS 17.0, *)
private final class ActionsForView: ObvMapViewActionsProtocol {
    
    weak var viewController: ObvMapViewController?

    func userWantsToDismissObvMapView() {
        guard let viewController else { assertionFailure(); return }
        let actions = viewController.actions
        actions?.userWantsToDismissObvMapView(viewController)
    }
    
}
