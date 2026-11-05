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
import ObvTypes
import ObvDesignSystem
import ObvAppTypes

public struct DiscussionChooserView: View {

    let currentOwnedCryptoId: ObvCryptoId
    let dataSources: DataSources
    @Binding public var selectedDiscussionIdentifiers: [ObvDiscussionIdentifier]

    public init(currentOwnedCryptoId: ObvCryptoId,
                dataSources: DataSources,
                selectedDiscussionIdentifiers: Binding<[ObvDiscussionIdentifier]>) {
        self.currentOwnedCryptoId = currentOwnedCryptoId
        self.dataSources = dataSources
        _selectedDiscussionIdentifiers = selectedDiscussionIdentifiers
    }

    public struct DataSources {
        /// Provides the (search-filtered) list of discussion identifiers to display.
        let discussionChooserViewDataSource: any DiscussionChooserViewDataSource
        /// Resolves a discussion identifier into a `DiscussionItemView.Model` (rows, chips, and the "To:" row).
        let discussionItemViewDataSource: any DiscussionItemViewDataSource
        let avatarViewDataSource: any ObvAvatarViewDataSource
        public init(discussionChooserViewDataSource: any DiscussionChooserViewDataSource,
                    discussionItemViewDataSource: any DiscussionItemViewDataSource,
                    avatarViewDataSource: any ObvAvatarViewDataSource) {
            self.discussionChooserViewDataSource = discussionChooserViewDataSource
            self.discussionItemViewDataSource = discussionItemViewDataSource
            self.avatarViewDataSource = avatarViewDataSource
        }
    }

    public var body: some View {
        DiscussionChooserSearchableView(currentOwnedCryptoId: currentOwnedCryptoId,
                                        dataSources: dataSources,
                                        selectedDiscussionIdentifiers: $selectedDiscussionIdentifiers)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}
