/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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

@available(iOS 13.0, *)
struct MessageRetentionInfoSectionView: View {
    
    let timeBasedDeletionDateString: String?
    let numberOfNewMessagesBeforeSuppression: Int?
    
    var body: some View {
        Section(header: Text("RETENTION_INFO_LABEL")) {
            if let dateString = timeBasedDeletionDateString {
                HStack(alignment: .firstTextBaseline) {
                    ObvLabel("EXPECTED_DELETION_DATE", systemImage: "calendar.badge.clock")
                    Spacer()
                    Text(dateString)
                        .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                }
            }
            if let number = numberOfNewMessagesBeforeSuppression {
                if number >= 0 {
                    HStack(alignment: .firstTextBaseline) {
                        ObvLabel("NUMBER_OF_MESSAGES_BEFORE_DELETION", systemImage: "number")
                        Spacer()
                        Text("\(number)")
                            .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                    }
                } else {
                    ObvLabel("WILL_SOON_BE_DELETED", systemImage: "number")
                }
            }
        }
    }
}




@available(iOS 13.0, *)
struct MessageRetentionInfoView_Previews: PreviewProvider {
    
    static var previews: some View {
        Group {
            List {
                MessageRetentionInfoSectionView(timeBasedDeletionDateString: "October 1st, 2021", numberOfNewMessagesBeforeSuppression: 10)
            }
            List {
                MessageRetentionInfoSectionView(timeBasedDeletionDateString: "October 1st, 2021", numberOfNewMessagesBeforeSuppression: 10)
            }
            .environment(\.colorScheme, .dark)
            .environment(\.locale, .init(identifier: "fr"))
        }.listStyle(GroupedListStyle())
    }
}
