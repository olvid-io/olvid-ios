/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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
import CoreData
import ObvMetaManager
import ObvTypes
import ObvCrypto
import OlvidUtils

public struct ObvAttachment: Hashable {
    
    public enum Status: Int, CustomDebugStringConvertible {
        case paused = 0
        case resumed = 1
        case downloaded = 2
        case cancelledByServer = 3
        case markedForDeletion = 4
        
        public var debugDescription: String {
            switch self {
            case .paused: return "Paused"
            case .resumed: return "Resumed"
            case .downloaded: return "Downloaded"
            case .cancelledByServer: return "Cancelled by server"
            case .markedForDeletion: return "Marked for deletion"
            }
        }
    }

    public let fromContactIdentity: ObvContactIdentity
    public let metadata: Data
    public let totalUnitCount: Int64
    public let url: URL
    public let status: Status
    internal let attachmentId: AttachmentIdentifier
    public let messageUploadTimestampFromServer: Date

    public var messageIdentifier: Data {
        return attachmentId.messageId.uid.raw
    }
    public var number: Int {
        return attachmentId.attachmentNumber
    }

    var toIdentity: ObvOwnedIdentity {
        return fromContactIdentity.ownedIdentity
    }
    
    public var ownedCryptoId: ObvCryptoId {
        return fromContactIdentity.ownedIdentity.cryptoId
    }
    
    public var downloadPaused: Bool {
        return self.status == .paused
    }
    
    private static let errorDomain = String(describing: ObvAttachment.self)

    init(attachmentId: AttachmentIdentifier, networkFetchDelegate: ObvNetworkFetchDelegate, identityDelegate: ObvIdentityDelegate, within obvContext: ObvContext) throws {
        guard let networkReceivedAttachment = networkFetchDelegate.getAttachment(withId: attachmentId, flowId: obvContext.flowId) else { throw NSError() }
        try self.init(networkReceivedAttachment: networkReceivedAttachment, identityDelegate: identityDelegate, within: obvContext)
    }
    
    init(attachmentId: AttachmentIdentifier, fromContactIdentity: ObvContactIdentity, networkFetchDelegate: ObvNetworkFetchDelegate, flowId: FlowIdentifier) throws {
        guard let networkReceivedAttachment = networkFetchDelegate.getAttachment(withId: attachmentId, flowId: flowId) else { throw NSError() }
        self.fromContactIdentity = fromContactIdentity
        self.attachmentId = networkReceivedAttachment.attachmentId
        metadata = networkReceivedAttachment.metadata
        url = networkReceivedAttachment.url
        status = networkReceivedAttachment.status.toObvAttachmentStatus
        self.messageUploadTimestampFromServer = networkReceivedAttachment.messageUploadTimestampFromServer
        self.totalUnitCount = networkReceivedAttachment.totalUnitCount
    }
    
    private init(networkReceivedAttachment: ObvNetworkFetchReceivedAttachment, identityDelegate: ObvIdentityDelegate, within obvContext: ObvContext) throws {
        
        guard let obvContact = ObvContactIdentity(contactCryptoIdentity: networkReceivedAttachment.fromCryptoIdentity,
                                                  ownedCryptoIdentity: networkReceivedAttachment.attachmentId.messageId.ownedCryptoIdentity,
                                                  identityDelegate: identityDelegate,
                                                  within: obvContext) else { throw NSError() }
        self.fromContactIdentity = obvContact
        self.attachmentId = networkReceivedAttachment.attachmentId
        metadata = networkReceivedAttachment.metadata
        url = networkReceivedAttachment.url
        status = networkReceivedAttachment.status.toObvAttachmentStatus
        self.messageUploadTimestampFromServer = networkReceivedAttachment.messageUploadTimestampFromServer
        self.totalUnitCount = networkReceivedAttachment.totalUnitCount
    }
    
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(attachmentId)
    }
}


fileprivate extension ObvNetworkFetchReceivedAttachment.Status {
    
    var toObvAttachmentStatus: ObvAttachment.Status {
        switch self {
        case .paused: return .paused
        case .resumed: return .resumed
        case .downloaded: return .downloaded
        case .cancelledByServer: return .cancelledByServer
        case .markedForDeletion: return .markedForDeletion
        }
    }
    
}

// MARK: - Codable

extension ObvAttachment: Codable {
    
    /// ObvAttachment is codable so as to be able to transfer a message from the notification service to the main app.
    /// This serialization should **not** be used within long term storage since we may change it regularly.
    /// Si also `ObvMessage` and  `ObvContactIdentity`.

    enum CodingKeys: String, CodingKey {
        case fromContactIdentity = "from_contact_identity"
        case metadata = "metadata"
        case progressTotalUnitCount = "progress_total_unit_count"
        case url = "url"
        case status = "status"
        case attachmentId = "attachment_id"
        case messageUploadTimestampFromServer = "timestamp"
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fromContactIdentity, forKey: .fromContactIdentity)
        try container.encode(metadata, forKey: .metadata)
        try container.encode(totalUnitCount, forKey: .progressTotalUnitCount)
        try container.encode(url, forKey: .url)
        try container.encode(status.rawValue, forKey: .status)
        try container.encode(attachmentId, forKey: .attachmentId)
        try container.encode(messageUploadTimestampFromServer, forKey: .messageUploadTimestampFromServer)
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.fromContactIdentity = try values.decode(ObvContactIdentity.self, forKey: .fromContactIdentity)
        self.metadata = try values.decode(Data.self, forKey: .metadata)
        self.totalUnitCount = try values.decode(Int64.self, forKey: .progressTotalUnitCount)
        self.url = try values.decode(URL.self, forKey: .url)
        let rawStatus = try values.decode(Int.self, forKey: .status)
        guard let status = Status(rawValue: rawStatus) else {
            let message = "Could not decode status"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: ObvAttachment.errorDomain, code: 0, userInfo: userInfo)
        }
        self.status = status
        self.attachmentId = try values.decode(AttachmentIdentifier.self, forKey: .attachmentId)
        self.messageUploadTimestampFromServer = try values.decode(Date.self, forKey: .messageUploadTimestampFromServer)
    }

}
