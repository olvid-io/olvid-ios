/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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

@available(iOS 13, *)
struct SentMessageStatusView: View {
    
    let forStatus: PersistedMessageSent.MessageStatus
    var dateAsString: String?
    
    private var image: Image {
        switch forStatus {
        case .unprocessed:
            return Image(systemIcon: .hourglass)
        case .processing:
            return Image(systemIcon: .hare)
        case .sent:
            return Image(systemIcon: .checkmarkCircle)
        case .delivered:
            return Image(systemIcon: .checkmarkCircleFill)
        case .read:
            return Image(systemIcon: .eyeFill)
        }
    }
    
    private var title: String {
        switch forStatus {
        case .unprocessed: return NSLocalizedString("Unprocessed", comment: "")
        case .processing: return NSLocalizedString("Processing", comment: "")
        case .sent: return NSLocalizedString("Sent", comment: "")
        case .delivered: return NSLocalizedString("Delivered", comment: "")
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


@available(iOS 13, *)
struct SentMessageStatusView_Previews: PreviewProvider {
    
    static var previews: some View {
        Group {
            SentMessageStatusView(forStatus: .read, dateAsString: nil)
            SentMessageStatusView(forStatus: .delivered, dateAsString: "some date")
            SentMessageStatusView(forStatus: .sent, dateAsString: "another date")
        }
        .padding()
        .previewLayout(.fixed(width: 400, height: 70))
    }
}
