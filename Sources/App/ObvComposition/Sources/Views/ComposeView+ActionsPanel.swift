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

import SwiftUI


extension ComposeView {
    
    /// The actions this discussion can actually offer, in the order the card shows them.
    var availableActionsForPanel: [ComposeViewParameters.Action] {
        guard let dataSourceViewModel else { return [] }
        return ComposeViewParameters.Action.orderShownInPanel
            .filter { dataSourceViewModel.isActionAvailable(for: $0) }
    }
    
    
    func panelActionTapped(_ action: ComposeViewParameters.Action) {
        actionAwaitingTheCardsDeparture = action
        showActionsPanel = false
    }
    
    
    /// Carries out the entry chosen in the `+` card, if any, now that the card is no longer presented.
    ///
    /// Almost every entry presents a view controller. Asked for as soon as the card is told to close, that presentation can run before
    /// SwiftUI has begun dismissing the card — as it does on macOS 27 — so it is made either *from* the card, which then takes it down
    /// with it, or from the screen beneath while the card is still up, which UIKit refuses. Waiting for the card's content to disappear
    /// removes the race. A card closed without choosing anything leaves nothing to carry out.
    func theCardHasGone() {
        guard let action = actionAwaitingTheCardsDeparture else { return }
        actionAwaitingTheCardsDeparture = nil
        Task {
            try await actions.actionTapped(self,
                                           for: action,
                                           discussionIdentifier: sharedState.discussionIdentifier,
                                           contactIdentifier: dataSourceViewModel?.contactIdentifier)
        }
    }
    
}
