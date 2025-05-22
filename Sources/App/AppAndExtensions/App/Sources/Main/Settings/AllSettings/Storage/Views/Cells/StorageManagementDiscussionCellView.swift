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

import SwiftUI
import ObvUIObvCircledInitials

@available(iOS 17.0, *)
struct StorageManagementDiscussionCellView<Model: StorageManagementDiscussionCellViewModelProtocol>: View {
    
    var model: Model
    
    init(model: Model) {
        self.model = model
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 16.0) {
            InitialCircleViewNew(model: model, state: .cornerRadius(diameter: 40.0, cornerRadius: 12.0))
            Text(model.title)
            Spacer()
            Text(model.formattedSize)
                .foregroundStyle(.secondary)
            Image(systemIcon: .chevronRight)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6.0)
    }
}
