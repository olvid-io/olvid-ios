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
import CoreData
import ObvAppTypes
import ObvTypes
import ObvDesignSystem

@available(iOS 17, *)
public final class PollHostingController: KeyboardHostingController<PollRouterView> {
    
    // MARK: Attributes - Private - Notifications
    private let pollIdentifier: PollIdentifier
    private var isRegisteredToNotifications = false
    private var observationTokens = [NSObjectProtocol]()
    public override var canBecomeFirstResponder: Bool { true }
    
    public init(pollIdentifier: PollIdentifier, pollDataSource: any PollViewDataSourceProtocol, avatarViewDataSource: any ObvAvatarViewDataSource) {
        self.pollIdentifier = pollIdentifier
        
        let routerView = PollRouterView(pollIdentifier: pollIdentifier,
                                        pollDataSource: pollDataSource,
                                        avatarViewDataSource: avatarViewDataSource)
        super.init(rootView: routerView)
    }
    
    @MainActor required init?(coder aDecoder: NSCoder) {
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
extension PollHostingController {

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
