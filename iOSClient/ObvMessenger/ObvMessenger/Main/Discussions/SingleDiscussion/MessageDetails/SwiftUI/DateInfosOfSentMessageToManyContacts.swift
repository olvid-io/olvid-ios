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
import ObvEngine


struct RecipientAndTimestamp: Identifiable, Hashable {
    let id: Data
    let recipientName: String
    let timestampAsString: String
}

struct Recipient: Identifiable, Hashable {
    let id: Data
    let recipientName: String
}


struct DateInfosOfSentMessageToManyContactsInnerView: View {
    
    let read: [RecipientAndTimestamp]
    let delivered: [RecipientAndTimestamp]
    let sent: [RecipientAndTimestamp]
    let pending: [Recipient]
    
    var body: some View {
        if !read.isEmpty {
            Section(header: ObvLabel("Read", systemImage: "eye.fill"), content: {
                ForEach(read) { info in
                    HorizontalTitleAndSubtitle(title: info.recipientName,
                                               subtitle: info.timestampAsString)
                }
            })
        }
        if !delivered.isEmpty {
            Section(header: ObvLabel("Delivered", systemImage: "checkmark.circle.fill"), content: {
                ForEach(delivered) { info in
                    HorizontalTitleAndSubtitle(title: info.recipientName,
                                               subtitle: info.timestampAsString)
                }
            })
        }
        if !sent.isEmpty {
            Section(header: ObvLabel("Sent", systemImage: "checkmark.circle"), content: {
                ForEach(sent) { info in
                    HorizontalTitleAndSubtitle(title: info.recipientName,
                                               subtitle: info.timestampAsString)
                }
            })
        }
        if !pending.isEmpty {
            Section(header: Text("Pending"), content: {
                ForEach(pending) { info in
                    HorizontalTitleAndSubtitle(title: info.recipientName,
                                               subtitle: "")
                }
            })
        }
    }
}




fileprivate struct DateInfosOfSentMessageToManyContactsInnerView_Previews: PreviewProvider {
    
    private static let read = [
        RecipientAndTimestamp(id: Data(), recipientName: "Steve Read", timestampAsString: "date here"),
        RecipientAndTimestamp(id: Data(), recipientName: "Alice Read", timestampAsString: "date here"),
    ]
    
    private static let delivered = [
        RecipientAndTimestamp(id: Data(), recipientName: "Steve Delivered", timestampAsString: "date here"),
    ]
    
    private static let sent = [
        RecipientAndTimestamp(id: Data(), recipientName: "Steve Sent", timestampAsString: "date here"),
    ]
    
    private static let pending = [
        Recipient(id: Data(), recipientName: "Steve Jobs"),
    ]
    
    static var previews: some View {
        DateInfosOfSentMessageToManyContactsInnerView(read: read,
                                                      delivered: delivered,
                                                      sent: sent,
                                                      pending: pending)
    }
}
