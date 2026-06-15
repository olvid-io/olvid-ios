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


/// Shown below the progress bar when exporting/importing messages or attachments.
struct ProgressAndETATextsView: View {
    
    let etaString: String?
    let progressPercentage: String?
    
    var body: some View {
        if let etaString, let progressPercentage {
            HStack(alignment: .firstTextBaseline) {
                Text(etaString)
                Spacer()
                Text(progressPercentage)
            }
            .font(.caption)
        } else if let progressPercentage {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "")
                Spacer(minLength: 0)
                Text(progressPercentage)
                    .font(.caption)
            }
        } else {
            EmptyView()
        }
    }
}
