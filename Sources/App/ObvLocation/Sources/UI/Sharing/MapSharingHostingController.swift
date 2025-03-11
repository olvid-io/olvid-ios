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
import CoreData
import SwiftUI
import ObvUICoreData
import ObvAppTypes

public protocol MapSharingHostingControllerDelegate: AnyObject {
    @MainActor func userWantsToSendLocation(_ locationData: ObvLocationData, discussionIdentifier: ObvDiscussionIdentifier)
    @MainActor func userWantsToShareLocationContinuously(expirationDate: Date?, discussionIdentifier: ObvDiscussionIdentifier)
}

@available(iOS 17.0, *)
public final class MapSharingHostingController: KeyboardHostingController<MapSharingView>, MapSharingViewActionsProtocol {

    
    private weak var delegate: MapSharingHostingControllerDelegate?
    
    // MARK: Attributes - Private - Notifications
    private var isRegisteredToNotifications = false
    private var observationTokens = [NSObjectProtocol]()
    public override var canBecomeFirstResponder: Bool { true }
    
    public init(discussionIdentifier: ObvDiscussionIdentifier, viewContext: NSManagedObjectContext, delegate: MapSharingHostingControllerDelegate) throws {
        self.delegate = delegate
        let viewModel = try MapSharingViewModel(discussionIdentifier: discussionIdentifier, viewContext: viewContext)
        let actions = Actions()
        let view = MapSharingView(viewModel: viewModel, actions: actions)
        super.init(rootView: view)
        actions.delegate = self
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
    
    func userWantsToSendLocation(_ locationData: ObvLocationData, discussionIdentifier: ObvDiscussionIdentifier) {
        
        delegate?.userWantsToSendLocation(locationData, discussionIdentifier: discussionIdentifier)
        
        self.dismiss(animated: true , completion: nil)
    }
    
    func userWantsToShareLocationContinuously(expirationMode: SharingLocationExpirationMode, discussionIdentifier: ObvDiscussionIdentifier) {
        delegate?.userWantsToShareLocationContinuously(expirationDate: expirationMode.expirationDate, discussionIdentifier: discussionIdentifier)
        
        // Because we start sharing location before dismissing, the location sharing will not stop automatically.
        
        self.dismiss(animated: true , completion: nil)
    }
    
    func userWantsToDismissMapView() {
        self.dismiss(animated: true , completion: nil)
    }
    
}

@available(iOS 17, *)
extension MapSharingHostingController {

    private func registerForNotification() {
        guard !isRegisteredToNotifications else { return }
        isRegisteredToNotifications = true
        
        observationTokens.append(contentsOf: [
            KeyboardNotification.observeKeyboardDidInputEscapeKeyNotification(queue: OperationQueue.main) { [weak self] in
                self?.dismiss(animated: true, completion: nil)
            },
        ])
    }
}

private final class Actions: MapSharingViewActionsProtocol {
    
    weak var delegate: MapSharingViewActionsProtocol?
    
    func userWantsToSendLocation(_ locationData: ObvLocationData, discussionIdentifier: ObvDiscussionIdentifier) {
        delegate?.userWantsToSendLocation(locationData, discussionIdentifier: discussionIdentifier)
    }
    
    
    func userWantsToShareLocationContinuously(expirationMode: SharingLocationExpirationMode, discussionIdentifier: ObvDiscussionIdentifier) {
        delegate?.userWantsToShareLocationContinuously(expirationMode: expirationMode, discussionIdentifier: discussionIdentifier)
    }
 
    func userWantsToDismissMapView() {
        delegate?.userWantsToDismissMapView()
    }
    
}

@available(iOS 17, *)
extension MapSharingHostingController: UISheetPresentationControllerDelegate { }
