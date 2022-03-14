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


struct ReceivedMessageStatusView: View {
    
    let forStatus: PersistedMessageReceived.MessageStatus
    var dateAsString: String?
    
    private var image: Image {
        switch forStatus {
        case .new:
            return Image(systemName: "arrow.down.circle.fill")
        case .unread:
            assertionFailure()
            return Image(systemName: "eye.fill")
        case .read:
            return Image(systemName: "eye.fill")
        }
    }
    
    private var title: String {
        switch forStatus {
        case .new: return NSLocalizedString("Received", comment: "")
        case .unread: return NSLocalizedString("Unread", comment: "")
        case .read: return NSLocalizedString("Read", comment: "")
        }
    }
    
    private var dateString: String {
        dateAsString ?? "-"
    }
    
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            self.image
            Text(self.title)
                .font(.body)
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
