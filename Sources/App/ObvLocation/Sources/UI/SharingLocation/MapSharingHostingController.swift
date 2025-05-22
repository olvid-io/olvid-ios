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

@preconcurrency import UIKit
import SwiftUI
import ObvAppTypes


@available(iOS 17.0, *)
@MainActor
public protocol MapSharingHostingControllerDelegate: AnyObject {
    func userWantsToSendLocation(_ vc: MapSharingHostingController, locationData: ObvLocationData, discussionIdentifier: ObvDiscussionIdentifier)
    func userWantsToShareLocationContinuously(_ vc: MapSharingHostingController, initialLocationData: ObvLocationData, expirationDate: ObvLocationSharingExpirationDate, discussionIdentifier: ObvDiscussionIdentifier) async throws
}

/// This `UIHostingController` is presented when the user taps on the location button in a discussion's composition view (and after performing the necessary checks to make sure we have the appropriate permissions).
@available(iOS 17.0, *)
public final class MapSharingHostingController: KeyboardHostingController<ObvSharingMapView> {

    
    private weak var internalDelegate: MapSharingHostingControllerDelegate?
    
    // MARK: Attributes - Private - Notifications
    private var isRegisteredToNotifications = false
    private var observationTokens = [NSObjectProtocol]()
    public override var canBecomeFirstResponder: Bool { true }
    
    public init(discussionIdentifier: ObvDiscussionIdentifier,
                isAlreadyContinouslySharingLocationFromCurrentDevice: Bool,
                delegate: MapSharingHostingControllerDelegate) throws {
        self.internalDelegate = delegate
        
        let actions = Actions()
        let model = ObvSharingMapViewModel(isAlreadyContinouslySharingLocationFromCurrentDevice: isAlreadyContinouslySharingLocationFromCurrentDevice,
                                           discussionIdentifier: discussionIdentifier)
        let view = ObvSharingMapView(model: model, actions: actions)
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
    
    
    enum ObvError: Error {
        case delegateIsNil
    }
    
}


@available(iOS 17, *)
extension MapSharingHostingController: ObvSharingMapViewActionsProtocol {
    
    func userWantsToSendLocation(_ locationData: ObvLocationData, discussionIdentifier: ObvDiscussionIdentifier) {
        internalDelegate?.userWantsToSendLocation(self, locationData: locationData, discussionIdentifier: discussionIdentifier)
        self.dismiss(animated: true , completion: nil)
    }

    
    func userWantsToShareLocationContinuously(initialLocationData: ObvLocationData, expirationMode: SharingLocationExpirationMode, discussionIdentifier: ObvDiscussionIdentifier) async throws {
        guard let internalDelegate else { assertionFailure(); throw ObvError.delegateIsNil }
        try await internalDelegate.userWantsToShareLocationContinuously(self, initialLocationData: initialLocationData, expirationDate: expirationMode.expirationDate, discussionIdentifier: discussionIdentifier)
        // Because we start sharing location before dismissing, the location sharing will not stop automatically.
        self.dismiss(animated: true , completion: nil)
    }

    func userWantsToDismissObvSharingMapView() {
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

private final class Actions: ObvSharingMapViewActionsProtocol {
    
    weak var delegate: ObvSharingMapViewActionsProtocol?
    
    func userWantsToSendLocation(_ locationData: ObvLocationData, discussionIdentifier: ObvDiscussionIdentifier) {
        delegate?.userWantsToSendLocation(locationData, discussionIdentifier: discussionIdentifier)
    }
    
    
    func userWantsToShareLocationContinuously(initialLocationData: ObvLocationData, expirationMode: SharingLocationExpirationMode, discussionIdentifier: ObvDiscussionIdentifier) async throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateInNil }
        try await delegate.userWantsToShareLocationContinuously(initialLocationData: initialLocationData, expirationMode: expirationMode, discussionIdentifier: discussionIdentifier)
    }
 
    func userWantsToDismissObvSharingMapView() {
        delegate?.userWantsToDismissObvSharingMapView()
    }
    
    enum ObvError: Error {
        case delegateInNil
    }
    
}

@available(iOS 17, *)
extension MapSharingHostingController: UISheetPresentationControllerDelegate { }
