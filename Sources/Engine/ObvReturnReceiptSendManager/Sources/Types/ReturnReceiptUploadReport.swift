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

import Foundation


/// What became of every receipt handed to the uploader.
///
/// Each identifier that went in comes back exactly once, in an outcome or in `identifiersThatCanNeverBeSent`. The
/// caller deletes a row only when an upload carrying it succeeded or when the receipt can never be sent, and keeps
/// everything else for the next attempt — so a receipt reported nowhere is a row nothing ever deletes, uploaded
/// again on every drain.
struct ReturnReceiptUploadReport: Sendable {

    /// One per request made. A request carries the receipts owed to one server, and no more than a request may hold.
    let outcomes: [ReturnReceiptUploadOutcome]

    /// The receipts that reached no request and never will: no contact device to send to, a key that cannot be
    /// decoded, a payload that cannot be encrypted. Their rows are to be deleted.
    let identifiersThatCanNeverBeSent: [ReturnReceiptIdentifier]

    init(outcomes: [ReturnReceiptUploadOutcome], identifiersThatCanNeverBeSent: [ReturnReceiptIdentifier]) {
        self.outcomes = outcomes
        self.identifiersThatCanNeverBeSent = identifiersThatCanNeverBeSent
    }

}


/// One request to one server: what it carried, and how it ended.
struct ReturnReceiptUploadOutcome: Sendable {

    let serverURL: URL
    let identifiers: [ReturnReceiptIdentifier]
    let outcome: Outcome

    enum Outcome: Sendable, Equatable {

        /// The server took them. These rows are to be deleted.
        case theUploadSucceeded

        /// No server ever saw the request. These rows are to be kept.
        ///
        /// Kept apart from the failure below because a receipt old enough to be given up on is deleted once an
        /// attempt has been made, and an attempt means one a server answered. Conflating the two would let a single
        /// launch with no network destroy a backlog that was about to be delivered.
        case theRequestNeverLeftTheDevice

        /// It left the device and came back wrong: a status other than 200, a response that cannot be read, or a
        /// general error from the server. These rows are to be kept.
        case theUploadFailed

    }

    init(serverURL: URL, identifiers: [ReturnReceiptIdentifier], outcome: Outcome) {
        self.serverURL = serverURL
        self.identifiers = identifiers
        self.outcome = outcome
    }

}
