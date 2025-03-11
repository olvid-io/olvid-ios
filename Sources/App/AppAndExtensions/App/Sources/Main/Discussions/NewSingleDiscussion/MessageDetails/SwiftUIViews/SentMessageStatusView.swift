/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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


struct SentMessageStatusView: View {
    
    let forStatus: PersistedMessageSent.MessageStatus
    let messageHasMoreThanOneRecipient: Bool
    var dateAsString: String?
    
    private var icon: any SymbolIcon {
        return forStatus.getSymbolIcon(messageHasMoreThanOneRecipient: messageHasMoreThanOneRecipient)
    }
    
    private var title: LocalizedStringKey {
        return forStatus.getLocalizedStringKey(messageHasMoreThanOneRecipient: messageHasMoreThanOneRecipient)
    }
    
    private var dateString: String {
        dateAsString ?? "-"
    }
    
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            
            Label(
                title: {
                    Text(title)
                        .foregroundStyle(.primary)
                },
                icon: {
                    Image(symbolIcon: icon)
                        .foregroundColor(.secondary)
                }
            )
            .font(.body)

            Spacer()

            Text(dateString)
                .font(.body)
                .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
            
        }
    }
    
}



struct SentMessageStatusView_Previews: PreviewProvider {
    
    static var previews: some View {
        Group {
            SentMessageStatusView(forStatus: .fullyDeliveredAndFullyRead, messageHasMoreThanOneRecipient: false, dateAsString: nil)
            SentMessageStatusView(forStatus: .fullyDeliveredAndNotRead, messageHasMoreThanOneRecipient: false, dateAsString: "some date")
            SentMessageStatusView(forStatus: .sent, messageHasMoreThanOneRecipient: false, dateAsString: "another date")
        }
        .padding()
        .previewLayout(.fixed(width: 400, height: 70))
    }
}
