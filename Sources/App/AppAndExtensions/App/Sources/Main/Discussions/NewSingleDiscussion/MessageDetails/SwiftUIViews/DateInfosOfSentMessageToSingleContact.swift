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

import SwiftUI


struct DateInfosOfSentMessageToSingleContact: View {
    
    var dateRead: String?
    var dateDelivered: String?
    var dateSent: String?
    
    var body: some View {
        Section("DATES_AND_TIMES") {
            SentMessageStatusView(forStatus: .fullyDeliveredAndFullyRead, messageHasMoreThanOneRecipient: false, dateAsString: dateRead)
            SentMessageStatusView(forStatus: .fullyDeliveredAndNotRead, messageHasMoreThanOneRecipient: false, dateAsString: dateDelivered)
            SentMessageStatusView(forStatus: .sent, messageHasMoreThanOneRecipient: false, dateAsString: dateSent)
        }
    }
}



struct DateInfosOfSentMessageToSingleContact_Previews: PreviewProvider {
    
    static var dateRead: Date? = nil
    static var dateDelivered: Date? = Date()
    static var dateSent: Date? = Date().advanced(by: -100)
    
    static var previews: some View {
        DateInfosOfSentMessageToSingleContact(dateRead: "some date",
                                              dateDelivered: "another date",
                                              dateSent: "date sent")
    }
}
