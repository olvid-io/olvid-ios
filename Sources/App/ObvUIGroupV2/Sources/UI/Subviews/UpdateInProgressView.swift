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
import ObvDesignSystem


// MARK: - Subview: Update in progress

struct UpdateInProgressView: View {

    var body: some View {
        ObvCardView(padding: 0) {
            HStack(alignment: .top, spacing: 8) {
                ProgressView()
                    .progressViewStyle(.circular)
                VStack(alignment: .leading, spacing: 6) {
                    Text("GROUP_UPDATE_IN_PROGRESS_EXPLANATION_TITLE")
                        .font(.system(.headline, design: .rounded))
                        .lineLimit(1)
                    Text("GROUP_UPDATE_IN_PROGRESS_EXPLANATION_BODY")
                        .font(.footnote)
                        .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                        .lineLimit(nil)
                }
                Spacer(minLength: 0)
            }
            .padding()
        }
    }
    
}
