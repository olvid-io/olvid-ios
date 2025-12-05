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

@MainActor
public protocol PollFlowControllerDelegate: AnyObject {
    
    func userWantsToCreatePoll(for discussionIdentifier: ObvDiscussionIdentifier, poll: ObvPoll)
    
}

@available(iOS 17, *)
public final class PollCreationFlowHostingController: KeyboardHostingController<PollCreationFlowView> {
    
    private weak var internalDelegate: PollFlowControllerDelegate?
    
    // MARK: Attributes - Private - Notifications
    private let discussionIdentifier: ObvDiscussionIdentifier
    private var isRegisteredToNotifications = false
    private var observationTokens = [NSObjectProtocol]()
    public override var canBecomeFirstResponder: Bool { true }
    
    public init(discussionIdentifier: ObvDiscussionIdentifier, delegate: PollFlowControllerDelegate) {
        self.internalDelegate = delegate
        self.discussionIdentifier = discussionIdentifier
        let actions = Actions()
        super.init(rootView: PollCreationFlowView(actions: actions))
        actions.delegate = self
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
extension PollCreationFlowHostingController: PollFlowViewActionsProtocol {

    func userWantsToDismissPollFlowView() {
        self.dismiss(animated: true, completion: nil)
    }
    
    func userWantsToCreatePoll(poll: ObvPoll) {
        internalDelegate?.userWantsToCreatePoll(for: self.discussionIdentifier, poll: poll)
        self.dismiss(animated: true, completion: nil)
    }
}

private final class Actions: PollFlowViewActionsProtocol {
    
    weak var delegate: PollFlowViewActionsProtocol?

    func userWantsToDismissPollFlowView() {
        delegate?.userWantsToDismissPollFlowView()
    }
    
    func userWantsToCreatePoll(poll: ObvPoll) {
        delegate?.userWantsToCreatePoll(poll: poll)
    }
}

@available(iOS 17, *)
extension PollCreationFlowHostingController {

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
