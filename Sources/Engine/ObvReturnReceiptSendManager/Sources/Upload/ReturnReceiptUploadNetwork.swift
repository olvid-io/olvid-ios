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


/// The one call to the network made when uploading return receipts, behind a protocol.
///
/// A seam for the tests: what the server answered decides whether a row is deleted or kept, and the answers worth
/// testing — a status other than 200, a body that is not an encoding, a general error, a lost connection — are ones
/// no real server gives on demand.
protocol ReturnReceiptUploadNetwork: Sendable {

    /// - Parameter dataToSend: the body. It travels beside the request rather than in it, because the request of an
    ///   upload task must carry no body and no body stream of its own.
    func upload(_ request: URLRequest, from dataToSend: Data) async throws -> (Data, URLResponse)

}


/// What is used outside the tests.
struct ReturnReceiptUploadNetworkUsingSharedURLSession: ReturnReceiptUploadNetwork {

    func upload(_ request: URLRequest, from dataToSend: Data) async throws -> (Data, URLResponse) {
        try await URLSession.shared.upload(for: request, from: dataToSend)
    }

}
