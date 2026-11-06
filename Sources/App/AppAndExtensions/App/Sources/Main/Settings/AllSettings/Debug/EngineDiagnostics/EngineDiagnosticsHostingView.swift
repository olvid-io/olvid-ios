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
import ObvTypes


protocol EngineDiagnosticsHostingViewDelegate: AnyObject {
    @MainActor func getAsyncStreamOfEngineDiagnostics(_ vc: EngineDiagnosticsHostingView) throws -> AsyncStream<ObvEngineDiagnostic>
    /// What the last drain of the engine's inbox achieved, or nil if none has ever run here. App-side, so it does not come through the stream above.
    @MainActor func getLastInboxDrainReport(_ vc: EngineDiagnosticsHostingView) -> ObvInboxDrainReport?
}


final class EngineDiagnosticsHostingView: UIHostingController<EngineDiagnosticsView> {

    private let actions = ViewsActions()
    private weak var internalDelegate: EngineDiagnosticsHostingViewDelegate?

    init(delegate: EngineDiagnosticsHostingViewDelegate) {
        let rootView = EngineDiagnosticsView(actions: actions)
        super.init(rootView: rootView)
        self.internalDelegate = delegate
        actions.delegate = self
        self.title = String(localized: "Engine diagnostics")
    }

    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

}


// MARK: - Implementing EngineDiagnosticsViewActionsDelegate

extension EngineDiagnosticsHostingView: EngineDiagnosticsViewActionsDelegate {

    func getAsyncStreamOfEngineDiagnostics() throws -> AsyncStream<ObvEngineDiagnostic> {
        guard let internalDelegate else { throw ObvError.delegateIsNil }
        return try internalDelegate.getAsyncStreamOfEngineDiagnostics(self)
    }

    func getLastInboxDrainReport() -> ObvInboxDrainReport? {
        internalDelegate?.getLastInboxDrainReport(self)
    }

}


// MARK: - Errors

extension EngineDiagnosticsHostingView {

    enum ObvError: Error {
        case delegateIsNil
    }

}


// MARK: - View's actions

private final class ViewsActions: EngineDiagnosticsViewActionsDelegate {

    weak var delegate: EngineDiagnosticsViewActionsDelegate?

    func getAsyncStreamOfEngineDiagnostics() throws -> AsyncStream<ObvEngineDiagnostic> {
        guard let delegate else { throw ObvError.delegateIsNil }
        return try delegate.getAsyncStreamOfEngineDiagnostics()
    }

    func getLastInboxDrainReport() -> ObvInboxDrainReport? {
        delegate?.getLastInboxDrainReport()
    }

    enum ObvError: Error {
        case delegateIsNil
    }

}
