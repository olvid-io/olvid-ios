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


import ObvEngine
import ObvUI
import SwiftUI


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
    let failed: [Recipient]
    
    var body: some View {
        if !read.isEmpty {
            Section(header: Label("Read", systemIcon: .eyeFill), content: {
                ForEach(read) { info in
                    HorizontalTitleAndSubtitle(title: info.recipientName,
                                               subtitle: info.timestampAsString)
                }
            })
        }
        if !delivered.isEmpty {
            Section(header: Label("Delivered", systemIcon: .checkmarkCircleFill), content: {
                ForEach(delivered) { info in
                    HorizontalTitleAndSubtitle(title: info.recipientName,
                                               subtitle: info.timestampAsString)
                }
            })
        }
        if !sent.isEmpty {
            Section(header: Label("Sent", systemIcon: .checkmarkCircle), content: {
                ForEach(sent) { info in
                    HorizontalTitleAndSubtitle(title: info.recipientName,
                                               subtitle: info.timestampAsString)
                }
            })
        }
        if !pending.isEmpty {
            Section(header: Label("Pending", systemIcon: .hourglass), content: {
                ForEach(pending) { info in
                    HorizontalTitleAndSubtitle(title: info.recipientName,
                                               subtitle: "")
                }
            })
        }
        if !failed.isEmpty {
            Section(header: Label("Failed", systemIcon: .exclamationmarkCircle), content: {
                ForEach(failed) { info in
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

    private static let failed = [
        Recipient(id: Data(), recipientName: "Tim Cooks"),
    ]

    static var previews: some View {
        DateInfosOfSentMessageToManyContactsInnerView(read: read,
                                                      delivered: delivered,
                                                      sent: sent,
                                                      pending: pending,
                                                      failed: failed)
    }
}
