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

    @ViewBuilder
    var menuContent: some View {

        if let dataSourceViewModel {
            
            Section {
                ForEach(self.sharedState.parameters.sortableActions) { action in
                    if dataSourceViewModel.isActionAvailable(for: action) {
                        Button {
                            Task {
                                try await actions.actionTapped(self,
                                                               for: action,
                                                               discussionIdentifier: self.sharedState.discussionIdentifier,
                                                               contactIdentifier: dataSourceViewModel.contactIdentifier)
                            }
                        } label: {
                            HStack {
                                Text(dataSourceViewModel.actionTitle(for: action))
                                Image(systemIcon: action.icon)
                            }
                        }
                        
                    }
                }
            }
            
            Section {
                ForEach(self.sharedState.parameters.unsortableActions) { action in
                    if dataSourceViewModel.isActionAvailable(for: action) {
                        Button {
                            Task {
                                try await actions.actionTapped(self,
                                                               for: action,
                                                               discussionIdentifier: self.sharedState.discussionIdentifier)
                            }
                        } label: {
                            HStack {
                                Text(action.title)
                                Image(systemIcon: action.icon)
                            }
                        }
                    }
                }
            }
            
        }
    }
    
}
