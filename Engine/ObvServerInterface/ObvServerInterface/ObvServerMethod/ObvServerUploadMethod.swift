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
import os.log
import ObvEncoder
import ObvCrypto

public protocol ObvServerUploadMethod: ObvServerMethod {
    
    var fileURL: URL { get }
    var countOfBytesClientExpectsToReceive: Int { get }
    var countOfBytesClientExpectsToSend: Int { get }
    
}

public extension ObvServerUploadMethod {

    func uploadTask(within session: URLSession) throws -> URLSessionUploadTask {
        let request = try getURLRequest(dataToSend: nil)
        let task = session.uploadTask(with: request, fromFile: fileURL)
        task.countOfBytesClientExpectsToReceive = Int64(countOfBytesClientExpectsToReceive)
        task.countOfBytesClientExpectsToSend = Int64(countOfBytesClientExpectsToSend)
        return task
    }
    
}
