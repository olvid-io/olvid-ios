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

import ObvUI
import ObvUICoreData
import SwiftUI
import ObvSystemIcon
import ObvDesignSystem


struct ReceivedMessageStatusView: View {
    
    private let icon: any SymbolIcon
    private let title: LocalizedStringKey
    private let dateString: String
    
    init(forStatus: PersistedMessageReceived.MessageStatus, dateAsString: String?) {
        switch forStatus {
        case .new:
            self.icon = SystemIcon.arrowDownCircleFill
            self.title = "Received"
        case .unread:
            self.icon = CustomIcon.checkmarkCircle
            self.title = "Unread"
        case .read:
            self.icon = CustomIcon.checkmarkCircleFill
            self.title = "Read"
        }
        self.dateString = dateAsString ?? "-"
    }
    
    init(title: LocalizedStringKey, icon: any SymbolIcon, dateAsString: String?) {
        self.title = title
        self.icon = icon
        self.dateString = dateAsString ?? "-"
    }
    
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            ObvLabel(title, symbolIcon: icon)
            Spacer()
            Text(dateString)
                .font(.body)
                .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
        }
    }
    
}



struct ReceivedMessageStatusView_Previews: PreviewProvider {
    
    static var previews: some View {
        Group {
            ReceivedMessageStatusView(forStatus: .read, dateAsString: nil)
        }
        .padding()
        .previewLayout(.fixed(width: 400, height: 70))
    }
}
