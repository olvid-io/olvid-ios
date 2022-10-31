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
import ObvCrypto
import ObvEncoder


/// This type is used for a specific type of response of a server query, namely for the `getGroupBlob` response.
public enum GetGroupBlobResult: ObvCodable {
    
    case blobWasDeletedFromServer
    case blobDownloaded(encryptedServerBlob: EncryptedData, logEntries: Set<Data>, groupAdminPublicKey: PublicKeyForAuthentication)
    case blobCouldNotBeDownloaded
    
    private var rawValue: Int {
        switch self {
        case .blobWasDeletedFromServer:
            return 0
        case .blobDownloaded:
            return 1
        case .blobCouldNotBeDownloaded:
            return 2
        }
    }
    
    public func obvEncode() -> ObvEncoded {
        switch self {
        case .blobWasDeletedFromServer:
            return [rawValue.obvEncode()].obvEncode()
        case .blobDownloaded(let encryptedServerBlob, let logEntries, let groupAdminPublicKey):
            return [rawValue.obvEncode(), encryptedServerBlob.obvEncode(), logEntries.map({ $0.obvEncode() }).obvEncode(), groupAdminPublicKey.obvEncode()].obvEncode()
        case .blobCouldNotBeDownloaded:
            return [rawValue.obvEncode()].obvEncode()
        }
    }
    
    public init?(_ obvEncoded: ObvEncoded) {
        guard let listOfEncoded = [ObvEncoded](obvEncoded) else { return nil }
        guard let encodedRawValue = listOfEncoded.first else { return nil }
        guard let rawValue = Int(encodedRawValue) else { return nil }
        switch rawValue {
        case 0:
            self = .blobWasDeletedFromServer
        case 1:
            guard listOfEncoded.count == 4 else { assertionFailure(); return nil }
            guard let encryptedServerBlob = EncryptedData(listOfEncoded[1]) else { return nil }
            guard let listOfEncodedLogItems = [ObvEncoded](listOfEncoded[2]) else { return nil }
            let logEntries = Set(listOfEncodedLogItems.compactMap({ Data($0) }))
            guard let groupAdminPublicKey = PublicKeyForAuthenticationDecoder.obvDecode(listOfEncoded[3]) else { return nil }
            self = .blobDownloaded(encryptedServerBlob: encryptedServerBlob, logEntries: logEntries, groupAdminPublicKey: groupAdminPublicKey)
        case 2:
            self = .blobCouldNotBeDownloaded
        default:
            assertionFailure()
            return nil
        }
    }

}
