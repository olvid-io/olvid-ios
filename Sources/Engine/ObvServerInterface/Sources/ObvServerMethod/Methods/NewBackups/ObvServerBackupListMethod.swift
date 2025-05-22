/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import OSLog
import ObvCrypto
import OlvidUtils
import ObvMetaManager
import ObvEncoder


public final class ObvServerBackupListMethod: ObvServerDataMethod {
    
    public let pathComponent = "/backupList"

    public let serverURL: URL
    private let backupKeyUID: UID
    public let flowId: FlowIdentifier

    weak public var identityDelegate: ObvIdentityDelegate? = nil
    public let isActiveOwnedIdentityRequired = false
    public let ownedIdentity: ObvCryptoIdentity? = nil

    
    public init(serverURL: URL, backupKeyUID: UID, flowId: FlowIdentifier) {
        self.serverURL = serverURL
        self.backupKeyUID = backupKeyUID
        self.flowId = flowId
    }
    
    
    private enum PossibleReturnStatusRaw: UInt8 {
        case ok = 0x00
        case unknownBackupKeyUID = 0x1b
        case parsingError = 0xfe
        case generalError = 0xff
    }

    
    public enum PossibleReturnStatus {
        case ok(backupsToDownloadAndDecrypt: [BackupToDownloadAndDecrypt])
        case unknownBackupKeyUID
        case parsingError
        case generalError
    }

    
    lazy public var dataToSend: Data? = {
        dataToSendNonNil
    }()
    
    
    public var dataToSendNonNil: Data {
        let encoded = [backupKeyUID.obvEncode()].obvEncode()
        return encoded.rawData
    }
    
    public static func parseObvServerResponse(responseData: Data, using log: OSLog) throws(ObvError) -> PossibleReturnStatus {
                
        guard let (rawServerReturnedStatus, listOfReturnedDatas) = genericParseObvServerResponse(responseData: responseData, using: log) else {
            throw .couldNotParseServerResponse
        }

        guard let serverReturnedStatus = PossibleReturnStatusRaw(rawValue: rawServerReturnedStatus) else {
            throw .invalidReturnedServerStatus
        }

        switch serverReturnedStatus {
        case .unknownBackupKeyUID:
            return .unknownBackupKeyUID
        case .parsingError:
            return .parsingError
        case .generalError:
            return .generalError
        case .ok:
            assert(listOfReturnedDatas.count == 1)
            guard listOfReturnedDatas.count >= 1 else {
                assertionFailure()
                throw .unexpectedCountOfReturnedDatas
            }
            let encodedListOfEncodedBackupsV2ListItem = listOfReturnedDatas[0]
            guard let listOfEncodedBackupsV2ListItem = [ObvEncoded](encodedListOfEncodedBackupsV2ListItem) else {
                assertionFailure()
                throw .couldNotParseEncodedList
            }
            let backupsToDownloadAndDecrypt = listOfEncodedBackupsV2ListItem.compactMap({ BackupToDownloadAndDecrypt($0) })
            guard backupsToDownloadAndDecrypt.count == listOfEncodedBackupsV2ListItem.count else {
                assertionFailure()
                throw .backupsV2ListItemsDecodingFailed
            }
            return .ok(backupsToDownloadAndDecrypt: backupsToDownloadAndDecrypt)
        }

    }
    
    
    public enum ObvError: Error {
        case couldNotParseServerResponse
        case invalidReturnedServerStatus
        case backupsV2ListItemsDecodingFailed
        case unexpectedCountOfReturnedDatas
        case couldNotParseEncodedList
    }

}


/// Public as it is used by the `ObvServerBackupListMethod`
public struct BackupToDownloadAndDecrypt: ObvDecodable, Hashable {
        
    public let threadUID: UID
    public let version: Int
    public let downloadURL: URL

    
    init(threadUID: UID, version: Int, downloadURL: URL) {
        self.threadUID = threadUID
        self.version = version
        self.downloadURL = downloadURL
    }
    
    
    public init?(_ obvEncoded: ObvEncoder.ObvEncoded) {
        guard let listOfEncoded = [ObvEncoded](obvEncoded, expectedCount: 3) else { assertionFailure(); return nil }
        do {
            let threadUID: UID = try listOfEncoded[0].obvDecode()
            let version: Int = try listOfEncoded[1].obvDecode()
            let downloadURL: URL = try listOfEncoded[2].obvDecode()
            self.init(threadUID: threadUID, version: version, downloadURL: downloadURL)
        } catch {
            assertionFailure()
            return nil
        }
    }

}
