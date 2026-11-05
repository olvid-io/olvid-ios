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
import ObvEngine
import ObvTypes


protocol InboxMaintenanceHostingViewDelegate: AnyObject {
    /// Runs one drain of the engine's inbox and answers what it achieved. Long-running by nature — minutes, on the device this exists for — and the `run` is
    /// how the screen asks it to stop without waiting for it to come back.
    @MainActor func userRequestedDrainOfTheEngineInbox(_ vc: InboxMaintenanceHostingView, run: ObvInboxDrainInProgress) async -> ObvInboxDrainReport
}


/// Hosts ``InboxMaintenanceView``.
///
/// Thin, as a hosting controller should be: the title UIKit insists on, the model built once, and the one thing SwiftUI cannot see — the app going to the
/// background. `onDisappear` does not fire for that, so a reader who locks their phone mid-run would otherwise have the work suspended with nothing written
/// down. The run holds the screen awake rather than taking a continued processing task, so the only way the app reaches the background during one is the
/// reader putting it there deliberately, and standing down is then the right answer.
final class InboxMaintenanceHostingView: UIHostingController<InboxMaintenanceView> {

    private let model: InboxMaintenanceModel
    private weak var internalDelegate: InboxMaintenanceHostingViewDelegate?
    private var observationTokens = [NSObjectProtocol]()

    init(delegate: InboxMaintenanceHostingViewDelegate) {
        let model = InboxMaintenanceModel()
        self.model = model
        super.init(rootView: InboxMaintenanceView(model: model))
        self.internalDelegate = delegate
        model.delegate = self
        self.title = String(localized: "Catch up on messages")
        observeTheAppGoingToTheBackground()
    }

    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        // A screen can be deallocated without its view ever disappearing — the settings flow going away while something else is popped — and the run holds
        // this screen weakly, so nothing here would otherwise end it — which would also leave the idle timer held open by a screen that no longer exists.
        model.stopTheRunInProgress()
    }

    private func observeTheAppGoingToTheBackground() {
        observationTokens.append(
            NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.model.stopTheRunInProgress()
                }
            })
    }

}


// MARK: - Implementing InboxMaintenanceModelDelegate

extension InboxMaintenanceHostingView: InboxMaintenanceModelDelegate {

    func userRequestedDrainOfTheEngineInbox(_ model: InboxMaintenanceModel, run: ObvInboxDrainInProgress) async -> ObvInboxDrainReport {
        guard let internalDelegate else {
            assertionFailure("The inbox maintenance screen has no delegate, so the drain cannot be run")
            return .couldNotBeRun(trigger: .userRequestedItInTheSettings)
        }
        return await internalDelegate.userRequestedDrainOfTheEngineInbox(self, run: run)
    }

}
