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
import ObvDesignSystem
import ObvTypes

@available(iOS 17.0, *)
@MainActor
public protocol ObvMapViewControllerDataSource: AnyObject {
    func getAsyncStreamOfObvMapViewModel(_ vc: ObvMapViewController) throws -> AsyncStream<ObvMapViewModel>
    func fetchAvatar(_ vc: ObvMapViewController, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage?
}


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
    
    fileprivate let dataSource: ObvMapViewControllerDataSource
    fileprivate weak var actions: ObvMapViewControllerActionsProtocol?
    private let dataSourceForView = DataSourceForView()
    private let actionsForView = ActionsForView()
    
    public init(dataSource: ObvMapViewControllerDataSource, actions: ObvMapViewControllerActionsProtocol, initialDeviceIdentifierToSelect: ObvDeviceIdentifier? = nil) {
        self.dataSource = dataSource
        self.actions = actions
        let rootView = ObvMapView(dataSource: dataSourceForView, actions: actionsForView, initialDeviceIdentifierToSelect: initialDeviceIdentifierToSelect)
        super.init(rootView: rootView)
        self.dataSourceForView.viewController = self
        self.actionsForView.viewController = self
    }
    
    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}


@available(iOS 17, *)
extension ObvMapViewController: UISheetPresentationControllerDelegate { }


@available(iOS 17.0, *)
private final class DataSourceForView: ObvMapViewDataSource {
    
    weak var viewController: ObvMapViewController?
    
    func getAsyncStreamOfObvMapViewModel() throws -> AsyncStream<ObvMapViewModel> {
        guard let viewController else { assertionFailure(); throw ObvError.viewControllerNotSet }
        let dataSource = viewController.dataSource
        return try dataSource.getAsyncStreamOfObvMapViewModel(viewController)
    }
    
    func fetchAvatar(photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        guard let viewController else { throw ObvError.viewControllerNotSet } // This can happen when dismissing the view controller
        let dataSource = viewController.dataSource
        return try await dataSource.fetchAvatar(viewController, photoURL: photoURL, avatarSize: avatarSize)
    }
    
    enum ObvError: Error {
        case viewControllerNotSet
        case dataSourceNotSet
    }
    
}


@available(iOS 17.0, *)
private final class ActionsForView: ObvMapViewActionsProtocol {
    
    weak var viewController: ObvMapViewController?

    func userWantsToDismissObvMapView() {
        guard let viewController else { assertionFailure(); return }
        let actions = viewController.actions
        actions?.userWantsToDismissObvMapView(viewController)
    }
    
}
