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

import Foundation

public protocol ObvS3UploadMethod: ObvS3Method {
    
    var fileURL: URL { get }
    var countOfBytesClientExpectsToReceive: Int { get }
    var countOfBytesClientExpectsToSend: Int { get }

}

public extension ObvS3UploadMethod {
    
    static func makeError(message: String) -> Error {
        NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message])
    }

    func uploadTask(within session: URLSession) throws -> URLSessionUploadTask {
        let request = try getURLRequest(httpMethod: "PUT", dataToSend: nil)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            assertionFailure()
            throw Self.makeError(message: "Cannot perform upload task as the file could not be found at the indicated URL")
        }
        let task = session.uploadTask(with: request, fromFile: fileURL)
        task.countOfBytesClientExpectsToReceive = Int64(countOfBytesClientExpectsToReceive)
        task.countOfBytesClientExpectsToSend = Int64(countOfBytesClientExpectsToSend)
        return task
    }
    
}
