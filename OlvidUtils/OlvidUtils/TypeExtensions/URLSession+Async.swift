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


extension URLSession {
    
    public func obvUpload(for request: URLRequest, from bodyData: Data, delegate: URLSessionTaskDelegate? = nil) async throws -> (Data, URLResponse) {
        if #available(iOS 15, *) {
            return try await upload(for: request, from: bodyData, delegate: delegate)
        } else {
            assert(delegate == nil, "The delegate is only supported for iOS 15+")
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
                let task = uploadTask(with: request, from: bodyData) { responseData, response, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        guard let responseData = responseData, let response = response else {
                            assertionFailure()
                            let userInfo = [NSLocalizedFailureReasonErrorKey: "Unexpected error in obvUpload"]
                            let error = NSError(domain: "OlvidUtils", code: 0, userInfo: userInfo)
                            continuation.resume(throwing: error)
                            return
                        }
                        continuation.resume(returning: (responseData, response))
                    }
                }
                task.resume()
            }
        }
    }

    
}
