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

import Foundation
import os.log
import ObvEngine
import ObvTypes
import ObvCrypto
import OlvidUtils
import ObvSettings
import ObvTypes
import ObvAppTypes


public struct PersistedItemJSON: Codable {
    
    public let message: MessageJSON?
    public let returnReceipt: ReturnReceiptJSON?
    public let webrtcMessage: WebRTCMessageJSON?
    public let discussionSharedConfiguration: DiscussionSharedConfigurationJSON?
    public let deleteMessagesJSON: DeleteMessagesJSON?
    public let deleteDiscussionJSON: DeleteDiscussionJSON?
    public let querySharedSettingsJSON: QuerySharedSettingsJSON?
    public let updateMessageJSON: UpdateMessageJSON?
    public let reactionJSON: ReactionJSON?
    public let screenCaptureDetectionJSON: ScreenCaptureDetectionJSON?
    public let limitedVisibilityMessageOpenedJSON: LimitedVisibilityMessageOpenedJSON?
    public let discussionRead: DiscussionReadJSON?

    enum CodingKeys: String, CodingKey {
        case message = "message"
        case returnReceipt = "rr"
        case webrtcMessage = "rtc"
        case discussionSharedConfiguration = "settings"
        case deleteMessagesJSON = "delm"
        case deleteDiscussionJSON = "deld"
        case querySharedSettingsJSON = "qss"
        case updateMessageJSON = "upm"
        case reactionJSON = "reacm"
        case screenCaptureDetectionJSON = "scd"
        case limitedVisibilityMessageOpenedJSON = "lvo"
        case discussionRead = "dr"
    }
    
    public init(messageJSON: MessageJSON) {
        self.message = messageJSON
        self.returnReceipt = nil
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = nil
        self.querySharedSettingsJSON = nil
        self.updateMessageJSON = nil
        self.reactionJSON = nil
        self.screenCaptureDetectionJSON = nil
        self.limitedVisibilityMessageOpenedJSON = nil
        self.discussionRead = nil
    }
    
    public init(returnReceiptJSON: ReturnReceiptJSON) {
        self.message = nil
        self.returnReceipt = returnReceiptJSON
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = nil
        self.querySharedSettingsJSON = nil
        self.updateMessageJSON = nil
        self.reactionJSON = nil
        self.screenCaptureDetectionJSON = nil
        self.limitedVisibilityMessageOpenedJSON = nil
        self.discussionRead = nil
    }
    
    public init(messageJSON: MessageJSON, returnReceiptJSON: ReturnReceiptJSON) {
        self.message = messageJSON
        self.returnReceipt = returnReceiptJSON
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = nil
        self.querySharedSettingsJSON = nil
        self.updateMessageJSON = nil
        self.reactionJSON = nil
        self.screenCaptureDetectionJSON = nil
        self.limitedVisibilityMessageOpenedJSON = nil
        self.discussionRead = nil
    }
    
    public init(webrtcMessage: WebRTCMessageJSON) {
        self.message = nil
        self.returnReceipt = nil
        self.webrtcMessage = webrtcMessage
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = nil
        self.querySharedSettingsJSON = nil
        self.updateMessageJSON = nil
        self.reactionJSON = nil
        self.screenCaptureDetectionJSON = nil
        self.limitedVisibilityMessageOpenedJSON = nil
        self.discussionRead = nil
    }
    
    public init(discussionSharedConfiguration: DiscussionSharedConfigurationJSON) {
        self.message = nil
        self.returnReceipt = nil
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = discussionSharedConfiguration
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = nil
        self.querySharedSettingsJSON = nil
        self.updateMessageJSON = nil
        self.reactionJSON = nil
        self.screenCaptureDetectionJSON = nil
        self.limitedVisibilityMessageOpenedJSON = nil
        self.discussionRead = nil
    }
    
    public init(deleteMessagesJSON: DeleteMessagesJSON) {
        self.message = nil
        self.returnReceipt = nil
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = deleteMessagesJSON
        self.deleteDiscussionJSON = nil
        self.querySharedSettingsJSON = nil
        self.updateMessageJSON = nil
        self.reactionJSON = nil
        self.screenCaptureDetectionJSON = nil
        self.limitedVisibilityMessageOpenedJSON = nil
        self.discussionRead = nil
    }

    public init(deleteDiscussionJSON: DeleteDiscussionJSON) {
        self.message = nil
        self.returnReceipt = nil
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = deleteDiscussionJSON
        self.querySharedSettingsJSON = nil
        self.updateMessageJSON = nil
        self.reactionJSON = nil
        self.screenCaptureDetectionJSON = nil
        self.limitedVisibilityMessageOpenedJSON = nil
        self.discussionRead = nil
    }
    
    public init(querySharedSettingsJSON: QuerySharedSettingsJSON) {
        self.message = nil
        self.returnReceipt = nil
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = nil
        self.querySharedSettingsJSON = querySharedSettingsJSON
        self.updateMessageJSON = nil
        self.reactionJSON = nil
        self.screenCaptureDetectionJSON = nil
        self.limitedVisibilityMessageOpenedJSON = nil
        self.discussionRead = nil
    }

    public init(updateMessageJSON: UpdateMessageJSON) {
        self.message = nil
        self.returnReceipt = nil
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = nil
        self.querySharedSettingsJSON = nil
        self.updateMessageJSON = updateMessageJSON
        self.reactionJSON = nil
        self.screenCaptureDetectionJSON = nil
        self.limitedVisibilityMessageOpenedJSON = nil
        self.discussionRead = nil
    }

    public init(reactionJSON: ReactionJSON) {
        self.message = nil
        self.returnReceipt = nil
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = nil
        self.querySharedSettingsJSON = nil
        self.updateMessageJSON = nil
        self.reactionJSON = reactionJSON
        self.screenCaptureDetectionJSON = nil
        self.limitedVisibilityMessageOpenedJSON = nil
        self.discussionRead = nil
    }

    public init(screenCaptureDetectionJSON: ScreenCaptureDetectionJSON) {
        self.message = nil
        self.returnReceipt = nil
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = nil
        self.querySharedSettingsJSON = nil
        self.updateMessageJSON = nil
        self.reactionJSON = nil
        self.screenCaptureDetectionJSON = screenCaptureDetectionJSON
        self.limitedVisibilityMessageOpenedJSON = nil
        self.discussionRead = nil
    }

    public init(limitedVisibilityMessageOpenedJSON: LimitedVisibilityMessageOpenedJSON) {
        self.message = nil
        self.returnReceipt = nil
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = nil
        self.querySharedSettingsJSON = nil
        self.updateMessageJSON = nil
        self.reactionJSON = nil
        self.screenCaptureDetectionJSON = nil
        self.limitedVisibilityMessageOpenedJSON = limitedVisibilityMessageOpenedJSON
        self.discussionRead = nil
    }

    public init(discussionRead: DiscussionReadJSON) {
        self.message = nil
        self.returnReceipt = nil
        self.webrtcMessage = nil
        self.discussionSharedConfiguration = nil
        self.deleteMessagesJSON = nil
        self.deleteDiscussionJSON = nil
        self.querySharedSettingsJSON = nil
        self.updateMessageJSON = nil
        self.reactionJSON = nil
        self.screenCaptureDetectionJSON = nil
        self.limitedVisibilityMessageOpenedJSON = nil
        self.discussionRead = discussionRead
    }

    public func jsonEncode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }

    public static func jsonDecode(_ data: Data) throws -> PersistedItemJSON {
        let decoder = JSONDecoder()
        return try decoder.decode(PersistedItemJSON.self, from: data)
    }

}


public struct DiscussionSharedConfigurationJSON: Codable {
    
    private let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: "DiscussionSharedConfigurationJSON")
    private static func makeError(message: String) -> Error { NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { DiscussionSharedConfigurationJSON.makeError(message: message) }

    let version: Int
    let expiration: ExpirationJSON
    let oneToOneIdentifier: OneToOneIdentifierJSON?
    let groupV1Identifier: GroupV1Identifier?
    let groupV2Identifier: GroupV2Identifier?

    public var groupIdentifier: GroupIdentifier? {
        if let groupV1Identifier = groupV1Identifier {
            return .groupV1(groupV1Identifier: groupV1Identifier)
        } else if let groupV2Identifier = groupV2Identifier {
            return .groupV2(groupV2Identifier: groupV2Identifier)
        } else {
            return nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case version = "version"
        case expiration = "exp"
        case groupUid = "guid" // For group V1
        case groupOwner = "go" // For group V1
        case groupV2Identifier = "gid2"
        case oneToOneIdentifier = "o2oi" // For one-to-one discussions
    }

    init(version: Int, expiration: ExpirationJSON, oneToOneIdentifier: OneToOneIdentifierJSON) {
        self.version = version
        self.expiration = expiration
        self.oneToOneIdentifier = oneToOneIdentifier
        self.groupV1Identifier = nil
        self.groupV2Identifier = nil
    }

    init(version: Int, expiration: ExpirationJSON, groupV1Identifier: GroupV1Identifier) {
        self.version = version
        self.expiration = expiration
        self.oneToOneIdentifier = nil
        self.groupV1Identifier = groupV1Identifier
        self.groupV2Identifier = nil
    }

    init(version: Int, expiration: ExpirationJSON, groupV2Identifier: GroupV2Identifier) {
        self.version = version
        self.expiration = expiration
        self.oneToOneIdentifier = nil
        self.groupV1Identifier = nil
        self.groupV2Identifier = groupV2Identifier
    }

    func jsonEncode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }

    static func jsonDecode(_ data: Data) throws -> DiscussionSharedConfigurationJSON {
        let decoder = JSONDecoder()
        return try decoder.decode(DiscussionSharedConfigurationJSON.self, from: data)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(oneToOneIdentifier, forKey: .oneToOneIdentifier)
        if let groupV1Identifier = groupV1Identifier {
            try container.encode(groupV1Identifier.groupUid.raw, forKey: .groupUid)
            try container.encode(groupV1Identifier.groupOwner.getIdentity(), forKey: .groupOwner)
        }
        if let groupV2Identifier = groupV2Identifier {
            try container.encode(groupV2Identifier, forKey: .groupV2Identifier)
        }
        try container.encode(version, forKey: .version)
        try container.encode(expiration, forKey: .expiration)
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try values.decode(Int.self, forKey: .version)
        if let expiration = try values.decodeIfPresent(ExpirationJSON.self, forKey: .expiration) {
            self.expiration = expiration
        } else {
            self.expiration = ExpirationJSON(readOnce: false, visibilityDuration: nil, existenceDuration: nil)
        }
        
        let oneToOneIdentifier = try values.decodeIfPresent(OneToOneIdentifierJSON.self, forKey: .oneToOneIdentifier)

        let groupUidRaw = try values.decodeIfPresent(Data.self, forKey: .groupUid)
        let groupOwnerIdentity = try values.decodeIfPresent(Data.self, forKey: .groupOwner)
        
        let groupV2Identifier = try values.decodeIfPresent(Data.self, forKey: .groupV2Identifier)
        
        if let oneToOneIdentifier {
            self.oneToOneIdentifier = oneToOneIdentifier
            self.groupV1Identifier = nil
            self.groupV2Identifier = nil
        } else if let groupUidRaw = groupUidRaw,
            let groupOwnerIdentity = groupOwnerIdentity,
            let groupUid = UID(uid: groupUidRaw),
            let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) {
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = GroupV1Identifier(groupUid: groupUid, groupOwner: groupOwner)
            self.groupV2Identifier = nil
        } else if let groupV2Identifier = groupV2Identifier {
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = nil
            self.groupV2Identifier = groupV2Identifier
        } else {
            // This happens when receiving a message for a one2one discussion from a device running an old version of Olvid, which didn't use to send the oneToOneIdentifier)
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = nil
            self.groupV2Identifier = nil
        }
    }

}


struct DiscussionSharedConfigurationForKeycloakGroupJSON: Decodable {
    
    private static func makeError(message: String) -> Error { NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { DiscussionSharedConfigurationForKeycloakGroupJSON.makeError(message: message) }

    let expiration: ExpirationJSON?

    enum CodingKeys: String, CodingKey {
        case expiration = "exp"
    }

    private init(expiration: ExpirationJSON) {
        self.expiration = expiration
    }

    static func jsonDecode(_ data: Data) throws -> DiscussionSharedConfigurationForKeycloakGroupJSON {
        let decoder = JSONDecoder()
        return try decoder.decode(DiscussionSharedConfigurationForKeycloakGroupJSON.self, from: data)
    }
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.expiration = try values.decodeIfPresent(ExpirationJSON.self, forKey: .expiration)
    }

}


public struct ReturnReceiptJSON: Codable {
    
    private let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: "ReturnReceiptJSON")
    
    private let nonce: Data
    private let key: Data
    
    public var elements: ObvReturnReceiptElements {
        return ObvReturnReceiptElements(nonce: nonce, key: key)
    }

    enum CodingKeys: String, CodingKey {
        case nonce = "nonce"
        case key = "key"
    }
    
    public init(returnReceiptElements: ObvReturnReceiptElements) {
        self.nonce = returnReceiptElements.nonce
        self.key = returnReceiptElements.key
    }
    
    private init(nonce: Data, key: Data) {
        self.nonce = nonce
        self.key = key
    }
        
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.nonce = try values.decode(Data.self, forKey: .nonce)
        self.key = try values.decode(Data.self, forKey: .key)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(nonce, forKey: .nonce)
        try container.encode(key, forKey: .key)
    }
    
    func jsonEncode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }
    
    static func jsonDecode(_ data: Data) throws -> ReturnReceiptJSON {
        let decoder = JSONDecoder()
        return try decoder.decode(ReturnReceiptJSON.self, from: data)
    }
}


public struct OneToOneIdentifierJSON: Codable, Equatable, Hashable {
    
    private let identity1: ObvCryptoId
    private let identity2: ObvCryptoId
    
    var identities: Set<ObvCryptoId> {
        return Set([identity1, identity2])
    }
    
    public func getContactIdentity(ownedIdentity: ObvCryptoId) -> ObvCryptoId? {
        if identity1 == ownedIdentity {
            return identity2
        } else if identity2 == ownedIdentity {
            return identity1
        } else {
            assertionFailure()
            return nil
        }
    }

    public init(ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId) {
        self.identity1 = ownedCryptoId
        self.identity2 = contactCryptoId
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(self.identity1.getIdentity())
        try container.encode(self.identity2.getIdentity())
    }
    
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let rawIdentity1 = try container.decode(Data.self)
        let rawIdentity2 = try container.decode(Data.self)
        self.identity1 = try ObvCryptoId(identity: rawIdentity1)
        self.identity2 = try ObvCryptoId(identity: rawIdentity2)
    }
    
}


public struct ExpirationJSON: Codable, Equatable, Hashable {

    public let readOnce: Bool
    public let visibilityDuration: TimeInterval?
    public let existenceDuration: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case readOnce = "ro"
        case visibilityDuration = "vis"
        case existenceDuration = "ex"
    }

    enum ExpirationJSONCodingError: Error {
        case decoding(String)
    }

    init(readOnce: Bool, visibilityDuration: TimeInterval?, existenceDuration: TimeInterval?) {
        self.readOnce = readOnce
        self.visibilityDuration = visibilityDuration
        self.existenceDuration = existenceDuration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let readOnce = try container.decodeIfPresent(Bool.self, forKey: .readOnce) {
            self.readOnce = readOnce
        } else {
            self.readOnce = false
        }
        if let visibilityDuration = try container.decodeIfPresent(Int.self, forKey: .visibilityDuration) {
            self.visibilityDuration = TimeInterval(visibilityDuration)
        } else {
            self.visibilityDuration = nil
        }
        if let existenceDuration = try container.decodeIfPresent(Int.self, forKey: .existenceDuration) {
            self.existenceDuration = TimeInterval(existenceDuration)
        } else {
            self.existenceDuration = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if readOnce {
            try container.encodeIfPresent(readOnce, forKey: .readOnce)
        }
        if let visibilityDuration = self.visibilityDuration {
            try container.encodeIfPresent(Int(visibilityDuration), forKey: .visibilityDuration)
        }
        if let existenceDuration = self.existenceDuration {
            try container.encodeIfPresent(Int(existenceDuration), forKey: .existenceDuration)
        }
    }

    func jsonEncode() throws -> Data {
        let encoder = JSONEncoder()
        let data = try encoder.encode(self)
        return data
    }

    static func jsonDecode(_ data: Data) throws -> ExpirationJSON {
        let decoder = JSONDecoder()
        return try decoder.decode(ExpirationJSON.self, from: data)
    }

}

public struct LocationJSON: Codable, Equatable, Hashable {

    public enum LocationSharingType: Int {
        case SEND = 1
        case SHARING = 2
        case END_SHARING = 3
    }
    
    public enum LocationQuality: Int {
        case QUALITY_PRECISE = 1
        case QUALITY_BALANCED = 2
        case QUALITY_POWER_SAVE = 3
    }
    public let type: LocationJSON.LocationSharingType
    public let timeIntervalSince1970: TimeInterval? // location timestamp
    public let count: Int? // null if not sharing
    public let quality: Int? // one of QUALITY_PRECISE, QUALITY_BALANCED, or QUALITY_POWER_SAVE for sharing. Null for TYPE_SEND. Not used in the Swift version of the app.
    public let sharingExpiration: TimeInterval? // can be null if endless sharing (else in ms)
    public let latitude: Double
    public let longitude: Double
    
    public let altitude: Double? // meters (default value null)
    public let precision: Double? // meters (default value null)
    public let address: String? // (default value empty string or null)
    
    var locationData: ObvLocationData {
        ObvLocationData(timestamp: timestamp,
                        latitude: latitude,
                        longitude: longitude,
                        altitude: altitude,
                        precision: precision,
                        address: address)
    }
    
    var timestamp: Date? {
        guard let timeIntervalSince1970 else { return nil }
        return Date(timeIntervalSince1970: timeIntervalSince1970)
    }
    
    var expirationDate: Date? {
        guard let sharingExpiration else { return nil }
        return Date(timeIntervalSince1970: sharingExpiration)
    }
    
    enum CodingKeys: String, CodingKey {
        case count = "c"
        case sharingExpiration = "se"
        case quality = "q"
        case type = "t"
        case timeIntervalSince1970 = "ts"
        case longitude = "long"
        case latitude = "lat"
        case altitude = "alt"
        case precision = "prec"
        case address = "add"
    }

    enum ExpirationJSONCodingError: Error {
        case decoding(String)
    }
    
    public init(type: LocationJSON.LocationSharingType,
                timestamp: Date?,
                count: Int?,
                quality: Int?,
                sharingExpiration: TimeInterval?,
                latitude: Double,
                longitude: Double,
                altitude: Double?,
                precision: Double?,
                address: String?) {
        self.type = type
        self.timeIntervalSince1970 = timestamp?.timeIntervalSince1970
        self.count = count
        self.quality = quality
        self.sharingExpiration = sharingExpiration
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.precision = precision
        self.address = address
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        let typeRawValue = try container.decode(Int.self, forKey: .type)
        self.type = LocationJSON.LocationSharingType(rawValue: typeRawValue) ?? .SEND
        
        self.longitude = try container.decode(Double.self, forKey: .longitude)
        self.latitude = try container.decode(Double.self, forKey: .latitude)
        
        if let timeIntervalSince1970InMilliseconds = try container.decodeIfPresent(Int.self, forKey: .timeIntervalSince1970) {
            self.timeIntervalSince1970 = TimeInterval(milliseconds: timeIntervalSince1970InMilliseconds)
        } else {
            self.timeIntervalSince1970 = nil
        }
        
        if let count = try container.decodeIfPresent(Int.self, forKey: .count) {
            self.count = count
        } else {
            self.count = nil
        }
        
        if let quality = try container.decodeIfPresent(Int.self, forKey: .quality) {
            self.quality = quality
        } else {
            self.quality = nil
        }
        
        if let sharingExpiration = try container.decodeIfPresent(Int.self, forKey: .sharingExpiration) {
            self.sharingExpiration = TimeInterval(milliseconds: sharingExpiration)
        } else {
            self.sharingExpiration = nil
        }
        
        if let altitude = try container.decodeIfPresent(Double.self, forKey: .altitude) {
            self.altitude = altitude
        } else {
            self.altitude = nil
        }
        
        if let precision = try container.decodeIfPresent(Double.self, forKey: .precision) {
            self.precision = precision
        } else {
            self.precision = nil
        }
        
        if let address = try container.decodeIfPresent(String.self, forKey: .address) {
            self.address = address
        } else {
            self.address = nil
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.type.rawValue, forKey: .type)
        if let timestamp = timeIntervalSince1970?.toMilliseconds {
            try container.encodeIfPresent(timestamp, forKey: .timeIntervalSince1970)
        }
        try container.encode(self.longitude, forKey: .longitude)
        try container.encode(self.latitude, forKey: .latitude)

        try container.encodeIfPresent(self.count, forKey: .count)
        try container.encodeIfPresent(self.quality, forKey: .quality)
        if let sharingExpiration = sharingExpiration?.toMilliseconds {
            try container.encodeIfPresent(sharingExpiration, forKey: .sharingExpiration)
        }
        try container.encodeIfPresent(self.altitude, forKey: .altitude)
        try container.encodeIfPresent(self.precision, forKey: .precision)
        try container.encodeIfPresent(self.address, forKey: .address)
    }

    public func jsonEncode() throws -> Data {
        let encoder = JSONEncoder()
        let data = try encoder.encode(self)
        return data
    }

    static func jsonDecode(_ data: Data) throws -> LocationJSON {
        let decoder = JSONDecoder()
        return try decoder.decode(LocationJSON.self, from: data)
    }

    static func defaultLocation(with type: LocationSharingType) -> LocationJSON {
        return LocationJSON(type: type,
                            timestamp: Date.now,
                            count: nil,
                            quality: nil,
                            sharingExpiration: nil,
                            latitude: 0,
                            longitude: 0,
                            altitude: nil,
                            precision: nil,
                            address: nil)
    }
}

public struct MessageJSON: Codable, Equatable, Hashable {
    
    private let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: "MessageJSON")
    private static func makeError(message: String) -> Error { NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { MessageJSON.makeError(message: message) }

    public let senderSequenceNumber: Int
    public let senderThreadIdentifier: UUID
    private let rawBody: String?
    public let oneToOneIdentifier: OneToOneIdentifierJSON?
    public let groupV1Identifier: GroupV1Identifier?
    public let groupV2Identifier: GroupV2Identifier?
    public let replyTo: MessageReferenceJSON?
    public let expiration: ExpirationJSON?
    public let location: LocationJSON?
    
    let forwarded: Bool
    /// This is the server timestamp received the first time the sender sent infos about this message.
    /// It is used to properly sort messages in Group V2 discussions.
    public let originalServerTimestamp: Date?
    public let userMentions: [UserMention]

    public var body: String? {
        rawBody?.replacingOccurrences(of: "\0", with: "")
    }

    public var groupIdentifier: GroupIdentifier? {
        if let groupV1Identifier = groupV1Identifier {
            return .groupV1(groupV1Identifier: groupV1Identifier)
        } else if let groupV2Identifier = groupV2Identifier {
            return .groupV2(groupV2Identifier: groupV2Identifier)
        } else {
            return nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case senderSequenceNumber = "ssn"
        case senderThreadIdentifier = "sti"
        case groupUid = "guid" // For group v1
        case groupOwner = "go" // For group v1
        case groupV2Identifier = "gid2" // For group v2
        case oneToOneIdentifier = "o2oi" // For one-to-one discussions
        case body = "body"
        case replyTo = "re"
        case expiration = "exp"
        case location = "loc"
        case forwarded = "fw"
        case originalServerTimestamp = "ost"
        case userMentions = "um"
    }
    
    public init(senderSequenceNumber: Int, senderThreadIdentifier: UUID, body: String?, oneToOneIdentifier: OneToOneIdentifierJSON, replyTo: MessageReferenceJSON?, expiration: ExpirationJSON?, location: LocationJSON?, forwarded: Bool, userMentions: [UserMention]) {
        self.senderSequenceNumber = senderSequenceNumber
        self.senderThreadIdentifier = senderThreadIdentifier
        self.rawBody = body
        self.oneToOneIdentifier = oneToOneIdentifier
        self.groupV1Identifier = nil
        self.groupV2Identifier = nil
        self.replyTo = replyTo
        self.expiration = expiration
        self.location = location
        self.forwarded = forwarded
        self.originalServerTimestamp = nil // Never set for oneToOne discussions
        self.userMentions = userMentions
    }

    public init(senderSequenceNumber: Int, senderThreadIdentifier: UUID, body: String?, groupV1Identifier: GroupV1Identifier, replyTo: MessageReferenceJSON?, expiration: ExpirationJSON?, location: LocationJSON?, forwarded: Bool, userMentions: [UserMention]) {
        self.senderSequenceNumber = senderSequenceNumber
        self.senderThreadIdentifier = senderThreadIdentifier
        self.rawBody = body
        self.oneToOneIdentifier = nil
        self.groupV1Identifier = groupV1Identifier
        self.groupV2Identifier = nil
        self.replyTo = replyTo
        self.expiration = expiration
        self.location = location
        self.forwarded = forwarded
        self.originalServerTimestamp = nil // Never set for Group V1 discussions
        self.userMentions = userMentions
    }

    public init(senderSequenceNumber: Int, senderThreadIdentifier: UUID, body: String?, groupV2Identifier: GroupV2Identifier, replyTo: MessageReferenceJSON?, expiration: ExpirationJSON?, location: LocationJSON?, forwarded: Bool, originalServerTimestamp: Date?, userMentions: [UserMention]) {
        self.senderSequenceNumber = senderSequenceNumber
        self.senderThreadIdentifier = senderThreadIdentifier
        self.rawBody = body
        self.oneToOneIdentifier = nil
        self.groupV1Identifier = nil
        self.groupV2Identifier = groupV2Identifier
        self.replyTo = replyTo
        self.expiration = expiration
        self.location = location
        self.forwarded = forwarded
        self.originalServerTimestamp = originalServerTimestamp
        self.userMentions = userMentions
    }


    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.senderSequenceNumber = try values.decode(Int.self, forKey: .senderSequenceNumber)
        self.senderThreadIdentifier = try values.decode(UUID.self, forKey: .senderThreadIdentifier)
        let body = try values.decodeIfPresent(String.self, forKey: .body)

        self.rawBody = body

        let oneToOneIdentifier = try values.decodeIfPresent(OneToOneIdentifierJSON.self, forKey: .oneToOneIdentifier)
        
        let groupUidRaw = try values.decodeIfPresent(Data.self, forKey: .groupUid)
        let groupOwnerIdentity = try values.decodeIfPresent(Data.self, forKey: .groupOwner)
        
        let groupV2Identifier = try values.decodeIfPresent(Data.self, forKey: .groupV2Identifier)
        
        if let oneToOneIdentifier {
            self.oneToOneIdentifier = oneToOneIdentifier
            self.groupV1Identifier = nil
            self.groupV2Identifier = nil
        } else if let groupUidRaw = groupUidRaw,
            let groupOwnerIdentity = groupOwnerIdentity,
            let groupUid = UID(uid: groupUidRaw),
            let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) {
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = GroupV1Identifier(groupUid: groupUid, groupOwner: groupOwner)
            self.groupV2Identifier = nil
        } else if let groupV2Identifier = groupV2Identifier {
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = nil
            self.groupV2Identifier = groupV2Identifier
        } else {
            // This happens when receiving a message for a one2one discussion from a device running an old version of Olvid, which didn't use to send the oneToOneIdentifier)
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = nil
            self.groupV2Identifier = nil
        }
                
        self.replyTo = try values.decodeIfPresent(MessageReferenceJSON.self, forKey: .replyTo)
        self.expiration = try values.decodeIfPresent(ExpirationJSON.self, forKey: .expiration)
        self.location = try values.decodeIfPresent(LocationJSON.self, forKey: .location)
        self.forwarded = try values.decodeIfPresent(Bool.self, forKey: .forwarded) ?? false
        
        let originalServerTimestampInMilliseconds = try values.decodeIfPresent(Int64.self, forKey: .originalServerTimestamp)
        if groupV2Identifier != nil, let originalServerTimestampInMilliseconds = originalServerTimestampInMilliseconds {
            self.originalServerTimestamp = Date(epochInMs: originalServerTimestampInMilliseconds)
        } else {
            self.originalServerTimestamp = nil
        }

        if let body,
           values.contains(.userMentions),
           try values.decodeNil(forKey: .userMentions) == false {
            let decodingBlock: (Decoder) throws -> UserMention?

            let configuration = UserMention.Configuration(message: body)
            
            decodingBlock = { decoder -> UserMention? in
                do {
                    return try UserMention(from: decoder, configuration: configuration)
                } catch let error as UserMention.MentionError.DecodingError {
                    assertionFailure("failed to decode with error: \(error)") //used for debugging
                    return nil
                }
            }

            var _storage: [UserMention] = []

            var container = try values.nestedUnkeyedContainer(forKey: .userMentions)

            while !container.isAtEnd {
                if let decodedMention = try decodingBlock(container.superDecoder()) {
                    _storage.append(decodedMention)
                }
            }

            userMentions = _storage
        } else {
            userMentions = []
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(oneToOneIdentifier, forKey: .oneToOneIdentifier)
        if let groupV1Identifier = groupV1Identifier {
            try container.encode(groupV1Identifier.groupUid.raw, forKey: .groupUid)
            try container.encode(groupV1Identifier.groupOwner.getIdentity(), forKey: .groupOwner)
        }
        if let groupV2Identifier = groupV2Identifier {
            try container.encode(groupV2Identifier, forKey: .groupV2Identifier)
            try container.encodeIfPresent(originalServerTimestamp?.epochInMs, forKey: .originalServerTimestamp)
        }
        try container.encode(senderSequenceNumber, forKey: .senderSequenceNumber)
        try container.encode(senderThreadIdentifier, forKey: .senderThreadIdentifier)
        if let body = body {
            try container.encode(body, forKey: .body)
        }
        if let replyTo = replyTo {
            try container.encode(replyTo, forKey: .replyTo)
        }
        if let expiration = expiration {
            try container.encode(expiration, forKey: .expiration)
        }
        if let location = location {
            try container.encode(location, forKey: .location)
        }
        try container.encode(forwarded, forKey: .forwarded)

        if let body, userMentions.isEmpty == false {
            let configuration = UserMention.Configuration(message: body)
            try container.encode(userMentions, forKey: .userMentions, configuration: configuration)
        }
    }
    
    func jsonEncode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }
    
    static func jsonDecode(_ data: Data) throws -> MessageJSON {
        let decoder = JSONDecoder()
        return try decoder.decode(MessageJSON.self, from: data)
    }
}

extension MessageJSON {
    /// Denotes a mention object
    /// - Attention: Ranges are half-open, from a lower-bound and up-to, but **NOT** including, an upper-bound
    /// - Attention: Mentions are only to be used with the mentioned contact's *real name*, not the nickname defined by the sender.
    /// - Important: **Ranges are calculated based on UTF-16 code units offset**
    ///
    ///
    /// For each mention, the JSON API has the following structure:
    ///
    /// ```json
    /// {
    ///   "mentions": [
    ///     {
    ///       "uid": <crypto_identity> (``ObvDataTypes/ObvCryptoId``)
    ///       "rs": 4,
    ///       "re": 2
    ///     }
    ///   ]
    /// }
    /// ```
    public struct UserMention: Hashable {
        /// The mentioned user's crypto ID
        public let mentionedCryptoId: ObvCryptoId

        /// The range of the mentioned user's name, within ``MessageJSON/body``
        public let range: Range<String.Index>

        public init(mentionedCryptoId: ObvCryptoId, range: Range<String.Index>) {
            self.mentionedCryptoId = mentionedCryptoId
            self.range = range
        }
    }
}

// @available(iOS, deprecated: 15, message: "Please use `CodableWithConfiguration` conformance now")
//extension MessageJSON.UserMention: Codable {
//    @available(*, deprecated, renamed: "init(from:messageBody:)")
//    public init(from decoder: Decoder) throws {
//        fatalError("init(from:) has not been implemented, please use init(from:messageBody:)")
//    }
//
//    @available(*, deprecated, renamed: "encode(to:messageBody:)")
//    public func encode(to encoder: Encoder) throws {
//        fatalError("encode(to:) has not been implemented, please use encode(to:messageBody:)")
//    }
//
//    public init(from decoder: Decoder, messageBody: String) throws {
//        let container = try decoder.container(keyedBy: CodingKeys.self)
//
//        let data = try container.decode(Data.self, forKey: .mentionedCryptoId)
//
//        mentionedCryptoId = try ObvCryptoId(identity: data)
//
//        let rangeStart = try container.decode(Int.self, forKey: .rangeStart)
//
//        let rangeEnd = try container.decode(Int.self, forKey: .rangeEnd)
//
//        let startIndex = String.Index(utf16Offset: rangeStart, in: messageBody)
//
//        let endIndex = String.Index(utf16Offset: rangeEnd, in: messageBody)
//
//        let messageBodyRange = messageBody.startIndex..<messageBody.endIndex
//
//        guard endIndex >= startIndex else {
//            throw MentionError.DecodingError.mentionRangeInvalid(lower: startIndex, upper: endIndex)
//        }
//
//        if endIndex > messageBody.startIndex {
//            guard messageBodyRange.contains(startIndex),
//                  messageBodyRange.contains(messageBody.index(before: endIndex)) else {
//                throw MentionError.DecodingError.mentionRangeNotWithinMessageRange(mentionRange: startIndex..<endIndex, message: messageBody)
//            }
//        }
//
//        range = startIndex..<endIndex
//    }
//
//    public func encode(to encoder: Encoder, messageBody: String) throws {
//        var container = encoder.container(keyedBy: CodingKeys.self)
//
//        try container.encode(mentionedCryptoId.cryptoIdentity.getIdentity(), forKey: .mentionedCryptoId)
//
//        try container.encode(range.lowerBound.utf16Offset(in: messageBody), forKey: .rangeStart)
//
//        try container.encode(range.upperBound.utf16Offset(in: messageBody), forKey: .rangeEnd)
//    }
//
//    private enum CodingKeys: String, CodingKey {
//        case mentionedCryptoId = "uid"
//        case rangeStart = "rs"
//        case rangeEnd = "re"
//    }
//}

extension MessageJSON.UserMention {
    /// A namespace for encoding/decoding ``MessageJSON/UserMention``s
    enum MentionError {
        /// Possible decoding errors
        ///
        /// - mentionRangeInvalid: Denotes an inconsistent state within the string indices, more generally the lower is higher then the upper bound or vice-versa
        /// - mentionRangeNotWithinMessageRange: Denotes an error where the mention range is not contained within the actual message
        enum DecodingError: Error {
            /// Denotes an inconsistent state within the string indices, more generally the lower is higher then the upper bound or vice-versa
            case mentionRangeInvalid(lower: String.Index, upper: String.Index)
            /// Denotes an error where the mention range is not contained within the actual message
            // case mentionRangeNotWithinMessageRange(mentionRange: Range<String.Index>, message: String)
        }
    }
}

extension MessageJSON.UserMention: CodableWithConfiguration {
    public typealias DecodingConfiguration = Configuration
    public typealias EncodingConfiguration = Configuration

    /// The configuration object for serializing a user mention
    public struct Configuration {
        /// The raw message body containing the mention
        let message: String
    }

    private enum CodingKeys: String, CodingKey {
        case mentionedCryptoId = "uid"
        case rangeStart = "rs"
        case rangeEnd = "re"
    }

    public init(from decoder: Decoder, configuration: DecodingConfiguration) throws {
        
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let data = try container.decode(Data.self, forKey: .mentionedCryptoId)

        self.mentionedCryptoId = try ObvCryptoId(identity: data)

        let rangeStart = try container.decode(Int.self, forKey: .rangeStart)

        let rangeEnd = try container.decode(Int.self, forKey: .rangeEnd)

        let messageBody = configuration.message

        let startIndex = String.Index(utf16Offset: rangeStart, in: messageBody)

        let endIndex = String.Index(utf16Offset: rangeEnd, in: messageBody)

        // let messageBodyRange = messageBody.startIndex..<messageBody.endIndex

        guard endIndex > startIndex, startIndex >= messageBody.startIndex, endIndex <= messageBody.endIndex else {
            throw MentionError.DecodingError.mentionRangeInvalid(lower: startIndex, upper: endIndex)
        }

//        if endIndex > messageBody.startIndex {
//            guard messageBodyRange.contains(startIndex),
//                  messageBodyRange.contains(messageBody.index(before: endIndex)) else {
//                throw MentionError.DecodingError.mentionRangeNotWithinMessageRange(mentionRange: startIndex..<endIndex, message: messageBody)
//            }
//        }

        range = startIndex..<endIndex
    }

    public func encode(to encoder: Encoder, configuration: Configuration) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(mentionedCryptoId.getIdentity(), forKey: .mentionedCryptoId)

        let messageBody = configuration.message

        try container.encode(range.lowerBound.utf16Offset(in: messageBody), forKey: .rangeStart)

        try container.encode(range.upperBound.utf16Offset(in: messageBody), forKey: .rangeEnd)
    }
}

public struct MessageReferenceJSON: Codable, Equatable, Hashable {
    
    public let senderSequenceNumber: Int
    public let senderThreadIdentifier: UUID
    public let senderIdentifier: Data
    
    enum CodingKeys: String, CodingKey {
        case senderSequenceNumber = "ssn"
        case senderThreadIdentifier = "sti"
        case senderIdentifier = "si"
    }

    
    init(senderSequenceNumber: Int, senderThreadIdentifier: UUID, senderIdentifier: Data) {
        self.senderSequenceNumber = senderSequenceNumber
        self.senderThreadIdentifier = senderThreadIdentifier
        self.senderIdentifier = senderIdentifier
    }
    
    
    public func getMessageId(ownedCryptoId: ObvCryptoId) -> MessageIdentifier {
        let authorIdentifier = MessageWriterIdentifier(
            senderSequenceNumber: senderSequenceNumber,
            senderThreadIdentifier: senderThreadIdentifier,
            senderIdentifier: senderIdentifier)
        if senderIdentifier == ownedCryptoId.getIdentity() {
            return .sent(id: .authorIdentifier(writerIdentifier: authorIdentifier))
        } else {
            return .received(id: .authorIdentifier(writerIdentifier: authorIdentifier))
        }
    }
    
    
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.senderSequenceNumber = try values.decode(Int.self, forKey: .senderSequenceNumber)
        self.senderThreadIdentifier = try values.decode(UUID.self, forKey: .senderThreadIdentifier)
        self.senderIdentifier = try values.decode(Data.self, forKey: .senderIdentifier)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(senderSequenceNumber, forKey: .senderSequenceNumber)
        try container.encode(senderThreadIdentifier, forKey: .senderThreadIdentifier)
        try container.encode(senderIdentifier, forKey: .senderIdentifier)
    }
    
}


public struct DeleteMessagesJSON: Codable {
    
    private let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: "deleteMessagesJSON")

    private static func makeError(message: String) -> Error { NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { DeleteMessagesJSON.makeError(message: message) }

    public let oneToOneIdentifier: OneToOneIdentifierJSON?
    public let groupV1Identifier: GroupV1Identifier?
    public let groupV2Identifier: GroupV2Identifier?
    public let messagesToDelete: [MessageReferenceJSON]
    
    public var groupIdentifier: GroupIdentifier? {
        if let groupV1Identifier = groupV1Identifier {
            return .groupV1(groupV1Identifier: groupV1Identifier)
        } else if let groupV2Identifier = groupV2Identifier {
            return .groupV2(groupV2Identifier: groupV2Identifier)
        } else {
            return nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case groupUid = "guid" // For group V1
        case groupOwner = "go" // For group V1
        case groupV2Identifier = "gid2" // For group V2
        case messagesToDelete = "refs"
        case oneToOneIdentifier = "o2oi" // For one-to-one discussions
    }
    
    public init(persistedMessagesToDelete: [PersistedMessage]) throws {
        
        guard !persistedMessagesToDelete.isEmpty else { throw DeleteMessagesJSON.makeError(message: "No message to delete") }
        
        let discussion: PersistedDiscussion
        do {
            let discussions = Set(persistedMessagesToDelete.compactMap { $0.discussion })
            guard discussions.count == 1 else {
                throw DeleteMessagesJSON.makeError(message: "Could not construct DeleteMessagesJSON. Expecting one discussion, got \(discussions.count)")
            }
            guard let _discussion = discussions.first else {
                throw DeleteMessagesJSON.makeError(message: "Could not construct DeleteMessagesJSON. Expecting one discussion")
            }
            discussion = _discussion
        }

        self.messagesToDelete = persistedMessagesToDelete.compactMap { $0.toMessageReferenceJSON() }
        switch try discussion.kind {
        case .oneToOne:
            guard let ownedCryptoId = discussion.ownedIdentity?.cryptoId, let contactCryptoId = (discussion as? PersistedOneToOneDiscussion)?.contactIdentity?.cryptoId else {
                throw DeleteMessagesJSON.makeError(message: "Could not determine OneToOneIdentifierJSON")
            }
            self.oneToOneIdentifier = OneToOneIdentifierJSON(ownedCryptoId: ownedCryptoId, contactCryptoId: contactCryptoId)
            self.groupV1Identifier = nil
            self.groupV2Identifier = nil
        case .groupV1(withContactGroup: let contactGroup):
            guard let groupUid = contactGroup?.groupUid,
                  let groupOwnerIdentity = contactGroup?.ownerIdentity,
                  let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) else {
                throw DeleteMessagesJSON.makeError(message: "Could not determine group v1 id")
            }
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = GroupV1Identifier(groupUid: groupUid, groupOwner: groupOwner)
            self.groupV2Identifier = nil
        case .groupV2(withGroup: let group):
            guard let groupV2Identifier = group?.groupIdentifier else {
                throw DeleteMessagesJSON.makeError(message: "Could not determine group v2 id")
            }
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = nil
            self.groupV2Identifier = groupV2Identifier
        }
        
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(oneToOneIdentifier, forKey: .oneToOneIdentifier)
        if let groupV1Identifier = groupV1Identifier {
            try container.encode(groupV1Identifier.groupUid.raw, forKey: .groupUid)
            try container.encode(groupV1Identifier.groupOwner.getIdentity(), forKey: .groupOwner)
        }
        if let groupV2Identifier = groupV2Identifier {
            try container.encode(groupV2Identifier, forKey: .groupV2Identifier)
        }
        try container.encode(messagesToDelete, forKey: .messagesToDelete)
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        let groupUidRaw = try values.decodeIfPresent(Data.self, forKey: .groupUid)
        let groupOwnerIdentity = try values.decodeIfPresent(Data.self, forKey: .groupOwner)
        
        let oneToOneIdentifier = try values.decodeIfPresent(OneToOneIdentifierJSON.self, forKey: .oneToOneIdentifier)
        let groupV2Identifier = try values.decodeIfPresent(Data.self, forKey: .groupV2Identifier)
        
        if let oneToOneIdentifier {
            self.oneToOneIdentifier = oneToOneIdentifier
            self.groupV1Identifier = nil
            self.groupV2Identifier = nil
        } else if let groupUidRaw = groupUidRaw,
            let groupOwnerIdentity = groupOwnerIdentity,
            let groupUid = UID(uid: groupUidRaw),
            let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) {
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = GroupV1Identifier(groupUid: groupUid, groupOwner: groupOwner)
            self.groupV2Identifier = nil
        } else if let groupV2Identifier = groupV2Identifier {
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = nil
            self.groupV2Identifier = groupV2Identifier
        } else {
            // This happens when receiving a message for a one2one discussion from a device running an old version of Olvid, which didn't use to send the oneToOneIdentifier)
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = nil
            self.groupV2Identifier = nil
        }

        self.messagesToDelete = try values.decode([MessageReferenceJSON].self, forKey: .messagesToDelete)
        
    }

    
    public func getDiscussionId(ownedCryptoId: ObvCryptoId) throws -> DiscussionIdentifier {
        if let groupV1Identifier {
            return .groupV1(id: .groupV1Identifier(groupV1Identifier: groupV1Identifier))
        } else if let groupV2Identifier {
            return .groupV2(id: .groupV2Identifier(groupV2Identifier: groupV2Identifier))
        } else if let oneToOneIdentifier {
            guard let contactCryptoId = oneToOneIdentifier.getContactIdentity(ownedIdentity: ownedCryptoId) else {
                assertionFailure()
                throw ObvUICoreDataError.couldNotDetermineDiscussionIdentifier
            }
            return .oneToOne(id: .contactCryptoId(contactCryptoId: contactCryptoId))
        } else {
            throw ObvUICoreDataError.noDiscussionWasSpecified
        }
    }

}


public struct DeleteDiscussionJSON: Codable {
    
    private let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: "DeleteDiscussionJSON")

    private static func makeError(message: String) -> Error { NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { DeleteDiscussionJSON.makeError(message: message) }

    public let oneToOneIdentifier: OneToOneIdentifierJSON?
    public let groupV1Identifier: GroupV1Identifier?
    public let groupV2Identifier: GroupV2Identifier?

    public var groupIdentifier: GroupIdentifier? {
        if let groupV1Identifier = groupV1Identifier {
            return .groupV1(groupV1Identifier: groupV1Identifier)
        } else if let groupV2Identifier = groupV2Identifier {
            return .groupV2(groupV2Identifier: groupV2Identifier)
        } else {
            return nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case groupUid = "guid" // For group V1
        case groupOwner = "go" // For group V1
        case groupV2Identifier = "gid2"
        case oneToOneIdentifier = "o2oi" // For one-to-one discussions
    }
    
    public init(persistedDiscussionToDelete discussion: PersistedDiscussion) throws {
        switch try discussion.kind {
        case .oneToOne:
            guard let oneToOneDiscussion = discussion as? PersistedOneToOneDiscussion else {
                assertionFailure()
                throw DeleteDiscussionJSON.makeError(message: "Could not cast discussion into a one2one discussion. Unexpected, this is a bug")
            }
            self.oneToOneIdentifier = try oneToOneDiscussion.oneToOneIdentifier
            self.groupV1Identifier = nil
            self.groupV2Identifier = nil
        case .groupV1(withContactGroup: let contactGroup):
            guard let groupUid = contactGroup?.groupUid ?? (discussion as? PersistedGroupDiscussion)?.rawGroupUID?.toUID(),
                  let groupOwnerIdentity = contactGroup?.ownerIdentity ?? (discussion as? PersistedGroupDiscussion)?.rawOwnerIdentityIdentity,
                  let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) else {
                throw DeleteDiscussionJSON.makeError(message: "Could not determine group v1 id")
            }
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = GroupV1Identifier(groupUid: groupUid, groupOwner: groupOwner)
            self.groupV2Identifier = nil
        case .groupV2(withGroup: let group):
            guard let groupV2Identifier = group?.groupIdentifier ?? (discussion as? PersistedGroupV2Discussion)?.groupIdentifier else {
                throw DeleteDiscussionJSON.makeError(message: "Could not determine group v2 id")
            }
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = nil
            self.groupV2Identifier = groupV2Identifier
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(oneToOneIdentifier, forKey: .oneToOneIdentifier)
        if let groupV1Identifier = groupV1Identifier {
            try container.encode(groupV1Identifier.groupUid.raw, forKey: .groupUid)
            try container.encode(groupV1Identifier.groupOwner.getIdentity(), forKey: .groupOwner)
        }
        if let groupV2Identifier = groupV2Identifier {
            try container.encode(groupV2Identifier, forKey: .groupV2Identifier)
        }
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        let groupUidRaw = try values.decodeIfPresent(Data.self, forKey: .groupUid)
        let groupOwnerIdentity = try values.decodeIfPresent(Data.self, forKey: .groupOwner)
        
        let oneToOneIdentifier = try values.decodeIfPresent(OneToOneIdentifierJSON.self, forKey: .oneToOneIdentifier)
        let groupV2Identifier = try values.decodeIfPresent(Data.self, forKey: .groupV2Identifier)
        
        if let oneToOneIdentifier {
            self.oneToOneIdentifier = oneToOneIdentifier
            self.groupV1Identifier = nil
            self.groupV2Identifier = nil
        } else if let groupUidRaw = groupUidRaw,
            let groupOwnerIdentity = groupOwnerIdentity,
            let groupUid = UID(uid: groupUidRaw),
            let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) {
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = GroupV1Identifier(groupUid: groupUid, groupOwner: groupOwner)
            self.groupV2Identifier = nil
        } else if let groupV2Identifier = groupV2Identifier {
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = nil
            self.groupV2Identifier = groupV2Identifier
        } else {
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = nil
            self.groupV2Identifier = nil
        }

    }

    public func getDiscussionId(ownedCryptoId: ObvCryptoId) throws -> DiscussionIdentifier {
        if let groupV1Identifier {
            return .groupV1(id: .groupV1Identifier(groupV1Identifier: groupV1Identifier))
        } else if let groupV2Identifier {
            return .groupV2(id: .groupV2Identifier(groupV2Identifier: groupV2Identifier))
        } else if let oneToOneIdentifier {
            guard let contactCryptoId = oneToOneIdentifier.getContactIdentity(ownedIdentity: ownedCryptoId) else {
                assertionFailure()
                throw ObvUICoreDataError.couldNotDetermineDiscussionIdentifier
            }
            return .oneToOne(id: .contactCryptoId(contactCryptoId: contactCryptoId))
        } else {
            throw ObvUICoreDataError.noDiscussionWasSpecified
        }
    }

}


public struct QuerySharedSettingsJSON: Codable, ObvErrorMaker {
    
    public static let errorDomain = "QuerySharedSettingsJSON"

    public let oneToOneIdentifier: OneToOneIdentifierJSON?
    public let groupV1Identifier: GroupV1Identifier?
    public let groupV2Identifier: GroupV2Identifier?
    public let knownSharedSettingsVersion: Int?
    public let knownSharedExpiration: ExpirationJSON?

    public init(oneToOneIdentifier: OneToOneIdentifierJSON, knownSharedSettingsVersion: Int?, knownSharedExpiration: ExpirationJSON?) {
        self.knownSharedSettingsVersion = knownSharedSettingsVersion
        self.knownSharedExpiration = knownSharedExpiration
        self.oneToOneIdentifier = oneToOneIdentifier
        self.groupV1Identifier = nil
        self.groupV2Identifier = nil
    }

    public init(groupV1Identifier: GroupV1Identifier, knownSharedSettingsVersion: Int?, knownSharedExpiration: ExpirationJSON?) {
        self.knownSharedSettingsVersion = knownSharedSettingsVersion
        self.knownSharedExpiration = knownSharedExpiration
        self.oneToOneIdentifier = nil
        self.groupV1Identifier = groupV1Identifier
        self.groupV2Identifier = nil
    }

    public init(groupV2Identifier: GroupV2Identifier, knownSharedSettingsVersion: Int?, knownSharedExpiration: ExpirationJSON?) {
        self.knownSharedSettingsVersion = knownSharedSettingsVersion
        self.knownSharedExpiration = knownSharedExpiration
        self.oneToOneIdentifier = nil
        self.groupV1Identifier = nil
        self.groupV2Identifier = groupV2Identifier
    }

    enum CodingKeys: String, CodingKey {
        case groupUid = "guid" // For group V1
        case groupOwner = "go" // For group V1
        case groupV2Identifier = "gid2"
        case knownSharedSettingsVersion = "ksv"
        case knownSharedExpiration = "exp"
        case oneToOneIdentifier = "o2oi" // For one-to-one discussions
    }
    
    
    public var groupIdentifier: GroupIdentifier? {
        if let groupV1Identifier = groupV1Identifier {
            return .groupV1(groupV1Identifier: groupV1Identifier)
        } else if let groupV2Identifier = groupV2Identifier {
            return .groupV2(groupV2Identifier: groupV2Identifier)
        } else {
            return nil
        }
    }

    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(oneToOneIdentifier, forKey: .oneToOneIdentifier)
        if let groupV1Identifier = groupV1Identifier {
            try container.encode(groupV1Identifier.groupUid.raw, forKey: .groupUid)
            try container.encode(groupV1Identifier.groupOwner.getIdentity(), forKey: .groupOwner)
        }
        if let groupV2Identifier = groupV2Identifier {
            try container.encode(groupV2Identifier, forKey: .groupV2Identifier)
        }
        try container.encodeIfPresent(knownSharedSettingsVersion, forKey: .knownSharedSettingsVersion)
        try container.encodeIfPresent(knownSharedExpiration, forKey: .knownSharedExpiration)
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        let oneToOneIdentifier = try values.decodeIfPresent(OneToOneIdentifierJSON.self, forKey: .oneToOneIdentifier)
        
        let groupUidRaw = try values.decodeIfPresent(Data.self, forKey: .groupUid)
        let groupOwnerIdentity = try values.decodeIfPresent(Data.self, forKey: .groupOwner)
        
        let groupV2Identifier = try values.decodeIfPresent(Data.self, forKey: .groupV2Identifier)
        
        if let oneToOneIdentifier {
            self.oneToOneIdentifier = oneToOneIdentifier
            self.groupV1Identifier = nil
            self.groupV2Identifier = nil
        } else if let groupUidRaw = groupUidRaw,
            let groupOwnerIdentity = groupOwnerIdentity,
            let groupUid = UID(uid: groupUidRaw),
            let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) {
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = GroupV1Identifier(groupUid: groupUid, groupOwner: groupOwner)
            self.groupV2Identifier = nil
        } else if let groupV2Identifier = groupV2Identifier {
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = nil
            self.groupV2Identifier = groupV2Identifier
        } else {
            // This happens when receiving a message for a one2one discussion from a device running an old version of Olvid, which didn't use to send the oneToOneIdentifier)
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = nil
            self.groupV2Identifier = nil
        }

        self.knownSharedSettingsVersion = try values.decodeIfPresent(Int.self, forKey: .knownSharedSettingsVersion)
        self.knownSharedExpiration = try values.decodeIfPresent(ExpirationJSON.self, forKey: .knownSharedExpiration)

    }

}


public struct UpdateMessageJSON: Codable, Equatable, Hashable {
    
    private let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: "UpdateMessageJSON")

    private static func makeError(message: String) -> Error { NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { UpdateMessageJSON.makeError(message: message) }

    public let messageToEdit: MessageReferenceJSON
    public let oneToOneIdentifier: OneToOneIdentifierJSON?
    public let groupV1Identifier: GroupV1Identifier?
    public let groupV2Identifier: GroupV2Identifier?
    public let newTextBody: String?
    public let userMentions: [MessageJSON.UserMention]
    public let locationJSON: LocationJSON?
    
    public var groupIdentifier: GroupIdentifier? {
        if let groupV1Identifier = groupV1Identifier {
            return .groupV1(groupV1Identifier: groupV1Identifier)
        } else if let groupV2Identifier = groupV2Identifier {
            return .groupV2(groupV2Identifier: groupV2Identifier)
        } else {
            return nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case groupUid = "guid" // For group V1
        case groupOwner = "go" // For group V1
        case groupV2Identifier = "gid2"
        case body = "body"
        case messageToEdit = "ref"
        case userMentions = "um"
        case oneToOneIdentifier = "o2oi" // For one-to-one discussions
        case serializedLocation = "loc"
    }
    
    public init(persistedMessageSentToEdit msg: PersistedMessageSent, newTextBody: String?, userMentions: [MessageJSON.UserMention], locationJSON: LocationJSON?) throws {
        self.newTextBody = newTextBody
        guard let msgRef = msg.toMessageReferenceJSON() else {
            throw UpdateMessageJSON.makeError(message: "Could not create MessageReferenceJSON")
        }
        guard let discussion = msg.discussion else {
            throw UpdateMessageJSON.makeError(message: "Discussion is nil")
        }
        self.messageToEdit = msgRef
        guard let discussionKind = try msg.discussion?.kind else {
            throw UpdateMessageJSON.makeError(message: "Could not find discussion")
        }
        switch discussionKind {
        case .oneToOne:
            guard let oneToOneDiscussion = discussion as? PersistedOneToOneDiscussion else {
                assertionFailure()
                throw UpdateMessageJSON.makeError(message: "Could not cast discussion into a one2one discussion. Unexpected, this is a bug")
            }
            self.oneToOneIdentifier = try oneToOneDiscussion.oneToOneIdentifier
            self.groupV1Identifier = nil
            self.groupV2Identifier = nil
        case .groupV1(withContactGroup: let contactGroup):
            guard let groupUid = contactGroup?.groupUid,
                  let groupOwnerIdentity = contactGroup?.ownerIdentity,
                  let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) else {
                throw UpdateMessageJSON.makeError(message: "Could not determine group v1 uid")
            }
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = GroupV1Identifier(groupUid: groupUid, groupOwner: groupOwner)
            self.groupV2Identifier = nil
        case .groupV2(withGroup: let group):
            guard let groupV2Identifier = group?.groupIdentifier else {
                throw UpdateMessageJSON.makeError(message: "Could not determine group v2 uid")
            }
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = nil
            self.groupV2Identifier = groupV2Identifier
        }
        self.userMentions = userMentions
        self.locationJSON = locationJSON
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(oneToOneIdentifier, forKey: .oneToOneIdentifier)
        if let groupV1Identifier = groupV1Identifier {
            try container.encode(groupV1Identifier.groupUid.raw, forKey: .groupUid)
            try container.encode(groupV1Identifier.groupOwner.getIdentity(), forKey: .groupOwner)
        }
        if let groupV2Identifier = groupV2Identifier {
            try container.encode(groupV2Identifier, forKey: .groupV2Identifier)
        }
        if let newTextBody = newTextBody {
            try container.encode(newTextBody, forKey: .body)
        }
        try container.encode(messageToEdit, forKey: .messageToEdit)

        if let newTextBody, userMentions.isEmpty == false {
            let configuration = MessageJSON.UserMention.Configuration(message: newTextBody)
            try container.encode(userMentions, forKey: .userMentions, configuration: configuration)
        }

        try container.encodeIfPresent(locationJSON, forKey: .serializedLocation)

    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        let oneToOneIdentifier = try values.decodeIfPresent(OneToOneIdentifierJSON.self, forKey: .oneToOneIdentifier)
        
        let groupUidRaw = try values.decodeIfPresent(Data.self, forKey: .groupUid)
        let groupOwnerIdentity = try values.decodeIfPresent(Data.self, forKey: .groupOwner)
        
        let groupV2Identifier = try values.decodeIfPresent(Data.self, forKey: .groupV2Identifier)
        
        if let oneToOneIdentifier {
            self.oneToOneIdentifier = oneToOneIdentifier
            self.groupV1Identifier = nil
            self.groupV2Identifier = nil
        } else if let groupUidRaw = groupUidRaw,
            let groupOwnerIdentity = groupOwnerIdentity,
            let groupUid = UID(uid: groupUidRaw),
            let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) {
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = GroupV1Identifier(groupUid: groupUid, groupOwner: groupOwner)
            self.groupV2Identifier = nil
        } else if let groupV2Identifier = groupV2Identifier {
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = nil
            self.groupV2Identifier = groupV2Identifier
        } else {
            // This happens when receiving a message for a one2one discussion from a device running an old version of Olvid, which didn't use to send the oneToOneIdentifier)
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = nil
            self.groupV2Identifier = nil
        }

        self.locationJSON = try values.decodeIfPresent(LocationJSON.self, forKey: .serializedLocation)
        
        let newTextBody = try values.decodeIfPresent(String.self, forKey: .body)
        self.newTextBody = newTextBody
        self.messageToEdit = try values.decode(MessageReferenceJSON.self, forKey: .messageToEdit)

        if let newTextBody,
           values.contains(.userMentions),
           try values.decodeNil(forKey: .userMentions) == false {
            let decodingBlock: (Decoder) throws -> MessageJSON.UserMention?

            let configuration = MessageJSON.UserMention.Configuration(message: newTextBody)
            
            decodingBlock = { decoder -> MessageJSON.UserMention? in
                do {
                    return try MessageJSON.UserMention(from: decoder, configuration: configuration)
                } catch let error as MessageJSON.UserMention.MentionError.DecodingError {
                    assert(false, "failed to decode with error: \(error)") //used for debugging
                    return nil
                }
            }

            var _storage: [MessageJSON.UserMention] = []

            var container = try values.nestedUnkeyedContainer(forKey: .userMentions)

            while !container.isAtEnd {
                if let decodedMention = try decodingBlock(container.superDecoder()) {
                    _storage.append(decodedMention)
                }
            }

            userMentions = _storage
        } else {
            userMentions = []
        }
    }

    
    /// Allows to serialize this request when it must be saved for later in the `RemoteRequestSavedForLater` database
    public func jsonEncode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }

    
    /// Allows to deserialize this message when it was saved for later in the `RemoteRequestSavedForLater` database
    public static func jsonDecode(_ data: Data) throws -> UpdateMessageJSON {
        let decoder = JSONDecoder()
        return try decoder.decode(UpdateMessageJSON.self, from: data)
    }

}

public struct ReactionJSON: Codable {

    private let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: "ReactionJSON")

    private static func makeError(message: String) -> Error { NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { ReactionJSON.makeError(message: message) }

    public let messageReference: MessageReferenceJSON
    let oneToOneIdentifier: OneToOneIdentifierJSON?
    public let groupV1Identifier: GroupV1Identifier?
    public let groupV2Identifier: GroupV2Identifier?
    public let emoji: String?

    public var groupIdentifier: GroupIdentifier? {
        if let groupV1Identifier = groupV1Identifier {
            return .groupV1(groupV1Identifier: groupV1Identifier)
        } else if let groupV2Identifier = groupV2Identifier {
            return .groupV2(groupV2Identifier: groupV2Identifier)
        } else {
            return nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case groupUid = "guid" // For group V1
        case groupOwner = "go" // For group V1
        case groupV2Identifier = "gid2"
        case emoji = "reac"
        case messageReference = "ref"
        case oneToOneIdentifier = "o2oi" // For one-to-one discussions
    }

    public init(persistedMessageToReact msg: PersistedMessage, emoji: String?) throws {
        self.emoji = emoji
        guard let msgRef = msg.toMessageReferenceJSON() else {
            throw ReactionJSON.makeError(message: "Could not create MessageReferenceJSON")
        }
        guard let discussion = msg.discussion else {
            throw ReactionJSON.makeError(message: "Discussion is nil")
        }
        self.messageReference = msgRef
        guard let discussionKind = try msg.discussion?.kind else {
            throw ReactionJSON.makeError(message: "Could not find discussion")
        }
        switch discussionKind {
        case .oneToOne:
            guard let ownedCryptoId = discussion.ownedIdentity?.cryptoId, let contactCryptoId = (discussion as? PersistedOneToOneDiscussion)?.contactIdentity?.cryptoId else {
                throw ReactionJSON.makeError(message: "Could not determine OneToOneIdentifierJSON")
            }
            self.oneToOneIdentifier = OneToOneIdentifierJSON(ownedCryptoId: ownedCryptoId, contactCryptoId: contactCryptoId)
            self.groupV1Identifier = nil
            self.groupV2Identifier = nil
        case .groupV1(withContactGroup: let contactGroup):
            guard let groupUid = contactGroup?.groupUid,
                  let groupOwnerIdentity = contactGroup?.ownerIdentity,
                  let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) else {
                      throw ReactionJSON.makeError(message: "Could not determine group v1 uid")
                  }
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = GroupV1Identifier(groupUid: groupUid, groupOwner: groupOwner)
            self.groupV2Identifier = nil
        case .groupV2(withGroup: let group):
            guard let groupV2Identifier = group?.groupIdentifier else {
                throw ReactionJSON.makeError(message: "Could not determine group v2 uid")
            }
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = nil
            self.groupV2Identifier = groupV2Identifier
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(oneToOneIdentifier, forKey: .oneToOneIdentifier)
        if let groupV1Identifier = groupV1Identifier {
            try container.encode(groupV1Identifier.groupUid.raw, forKey: .groupUid)
            try container.encode(groupV1Identifier.groupOwner.getIdentity(), forKey: .groupOwner)
        }
        if let groupV2Identifier = groupV2Identifier {
            try container.encode(groupV2Identifier, forKey: .groupV2Identifier)
        }
        try container.encodeIfPresent(emoji, forKey: .emoji)
        try container.encode(messageReference, forKey: .messageReference)
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        let groupUidRaw = try values.decodeIfPresent(Data.self, forKey: .groupUid)
        let groupOwnerIdentity = try values.decodeIfPresent(Data.self, forKey: .groupOwner)

        let oneToOneIdentifier = try values.decodeIfPresent(OneToOneIdentifierJSON.self, forKey: .oneToOneIdentifier)
        let groupV2Identifier = try values.decodeIfPresent(Data.self, forKey: .groupV2Identifier)

        if let oneToOneIdentifier {
            self.oneToOneIdentifier = oneToOneIdentifier
            self.groupV1Identifier = nil
            self.groupV2Identifier = nil
        } else if let groupUidRaw = groupUidRaw,
            let groupOwnerIdentity = groupOwnerIdentity,
            let groupUid = UID(uid: groupUidRaw),
            let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) {
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = GroupV1Identifier(groupUid: groupUid, groupOwner: groupOwner)
            self.groupV2Identifier = nil
        } else if let groupV2Identifier = groupV2Identifier {
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = nil
            self.groupV2Identifier = groupV2Identifier
        } else {
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = nil
            self.groupV2Identifier = nil
        }

        self.emoji = try values.decodeIfPresent(String.self, forKey: .emoji)
        self.messageReference = try values.decode(MessageReferenceJSON.self, forKey: .messageReference)
    }

    /// Allows to serialize this request when it must be saved for later in the `RemoteRequestSavedForLater` database
    public func jsonEncode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }

    
    /// Allows to deserialize this message when it was saved for later in the `RemoteRequestSavedForLater` database
    public static func jsonDecode(_ data: Data) throws -> ReactionJSON {
        let decoder = JSONDecoder()
        return try decoder.decode(ReactionJSON.self, from: data)
    }

}


public struct ScreenCaptureDetectionJSON: Codable, ObvErrorMaker {
    
    private let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: "ScreenCaptureDetectionJSON")
    public static let errorDomain = "ScreenCaptureDetectionJSON"

    public let oneToOneIdentifier: OneToOneIdentifierJSON?
    let groupV1Identifier: GroupV1Identifier?
    let groupV2Identifier: GroupV2Identifier?

    public var groupIdentifier: GroupIdentifier? {
        if let groupV1Identifier = groupV1Identifier {
            return .groupV1(groupV1Identifier: groupV1Identifier)
        } else if let groupV2Identifier = groupV2Identifier {
            return .groupV2(groupV2Identifier: groupV2Identifier)
        } else {
            return nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case groupUid = "guid" // For group V1
        case groupOwner = "go" // For group V1
        case groupV2Identifier = "gid2"
        case oneToOneIdentifier = "o2oi" // For one-to-one discussions
    }

    public init(oneToOneIdentifier: OneToOneIdentifierJSON) {
        self.oneToOneIdentifier = oneToOneIdentifier
        self.groupV1Identifier = nil
        self.groupV2Identifier = nil
    }

    public init(groupV1Identifier: GroupV1Identifier) {
        self.oneToOneIdentifier = nil
        self.groupV1Identifier = groupV1Identifier
        self.groupV2Identifier = nil
    }

    public init(groupV2Identifier: GroupV2Identifier) {
        self.oneToOneIdentifier = nil
        self.groupV1Identifier = nil
        self.groupV2Identifier = groupV2Identifier
    }

    func jsonEncode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }

    static func jsonDecode(_ data: Data) throws -> ScreenCaptureDetectionJSON {
        let decoder = JSONDecoder()
        return try decoder.decode(ScreenCaptureDetectionJSON.self, from: data)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(oneToOneIdentifier, forKey: .oneToOneIdentifier)
        if let groupV1Identifier = groupV1Identifier {
            try container.encode(groupV1Identifier.groupUid.raw, forKey: .groupUid)
            try container.encode(groupV1Identifier.groupOwner.getIdentity(), forKey: .groupOwner)
        }
        if let groupV2Identifier = groupV2Identifier {
            try container.encode(groupV2Identifier, forKey: .groupV2Identifier)
        }
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        
        let groupUidRaw = try values.decodeIfPresent(Data.self, forKey: .groupUid)
        let groupOwnerIdentity = try values.decodeIfPresent(Data.self, forKey: .groupOwner)
        
        let oneToOneIdentifier = try values.decodeIfPresent(OneToOneIdentifierJSON.self, forKey: .oneToOneIdentifier)
        let groupV2Identifier = try values.decodeIfPresent(Data.self, forKey: .groupV2Identifier)
        
        if let oneToOneIdentifier {
            self.oneToOneIdentifier = oneToOneIdentifier
            self.groupV1Identifier = nil
            self.groupV2Identifier = nil
        } else if let groupUidRaw = groupUidRaw,
            let groupOwnerIdentity = groupOwnerIdentity,
            let groupUid = UID(uid: groupUidRaw),
            let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) {
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = GroupV1Identifier(groupUid: groupUid, groupOwner: groupOwner)
            self.groupV2Identifier = nil
        } else if let groupV2Identifier = groupV2Identifier {
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = nil
            self.groupV2Identifier = groupV2Identifier
        } else {
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = nil
            self.groupV2Identifier = nil
        }
    }

}


public struct LimitedVisibilityMessageOpenedJSON: Codable {
        
    let messageReference: MessageReferenceJSON
    let oneToOneIdentifier: OneToOneIdentifierJSON?
    let groupV1Identifier: GroupV1Identifier?
    let groupV2Identifier: GroupV2Identifier?
    
    public var groupIdentifier: GroupIdentifier? {
        if let groupV1Identifier {
            return .groupV1(groupV1Identifier: groupV1Identifier)
        } else if let groupV2Identifier {
            return .groupV2(groupV2Identifier: groupV2Identifier)
        } else {
            return nil
        }
    }
    
    
    public func getMessageId(ownedCryptoId: ObvCryptoId) throws -> ReceivedMessageIdentifier {
        let messageId = messageReference.getMessageId(ownedCryptoId: ownedCryptoId)
        switch messageId {
        case .sent, .system:
            throw ObvUICoreDataError.doesNotReferenceReceivedMessage
        case .received(let id):
            return id
        }
    }
    
    public func getDiscussionId(ownedCryptoId: ObvCryptoId) throws -> DiscussionIdentifier {
        if let groupV1Identifier {
            return .groupV1(id: .groupV1Identifier(groupV1Identifier: groupV1Identifier))
        } else if let groupV2Identifier {
            return .groupV2(id: .groupV2Identifier(groupV2Identifier: groupV2Identifier))
        } else if let oneToOneIdentifier {
            guard let contactCryptoId = oneToOneIdentifier.getContactIdentity(ownedIdentity: ownedCryptoId) else {
                assertionFailure()
                throw ObvUICoreDataError.couldNotDetermineDiscussionIdentifier
            }
            return .oneToOne(id: .contactCryptoId(contactCryptoId: contactCryptoId))
        } else {
            throw ObvUICoreDataError.noDiscussionWasSpecified
        }
    }

    enum CodingKeys: String, CodingKey {
        case messageReference = "m"
        case groupUid = "guid" // For group V1
        case groupOwner = "go" // For group V1
        case groupV2Identifier = "gid2"
        case oneToOneIdentifier = "o2oi" // For one-to-one discussions
    }

    public init(messageReference: MessageReferenceJSON, oneToOneIdentifier: OneToOneIdentifierJSON) {
        self.messageReference = messageReference
        self.oneToOneIdentifier = oneToOneIdentifier
        self.groupV1Identifier = nil
        self.groupV2Identifier = nil
    }

    public init(messageReference: MessageReferenceJSON, groupV1Identifier: GroupV1Identifier) {
        self.messageReference = messageReference
        self.oneToOneIdentifier = nil
        self.groupV1Identifier = groupV1Identifier
        self.groupV2Identifier = nil
    }

    public init(messageReference: MessageReferenceJSON, groupV2Identifier: GroupV2Identifier) {
        self.messageReference = messageReference
        self.oneToOneIdentifier = nil
        self.groupV1Identifier = nil
        self.groupV2Identifier = groupV2Identifier
    }

    func jsonEncode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }

    static func jsonDecode(_ data: Data) throws -> ScreenCaptureDetectionJSON {
        let decoder = JSONDecoder()
        return try decoder.decode(ScreenCaptureDetectionJSON.self, from: data)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(messageReference, forKey: .messageReference)
        try container.encodeIfPresent(oneToOneIdentifier, forKey: .oneToOneIdentifier)
        if let groupV1Identifier = groupV1Identifier {
            try container.encode(groupV1Identifier.groupUid.raw, forKey: .groupUid)
            try container.encode(groupV1Identifier.groupOwner.getIdentity(), forKey: .groupOwner)
        }
        try container.encodeIfPresent(groupV2Identifier, forKey: .groupV2Identifier)
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        
        self.messageReference = try values.decode(MessageReferenceJSON.self, forKey: .messageReference)
        
        let oneToOneIdentifier = try values.decodeIfPresent(OneToOneIdentifierJSON.self, forKey: .oneToOneIdentifier)

        let groupUidRaw = try values.decodeIfPresent(Data.self, forKey: .groupUid)
        let groupOwnerIdentity = try values.decodeIfPresent(Data.self, forKey: .groupOwner)
        
        let groupV2Identifier = try values.decodeIfPresent(Data.self, forKey: .groupV2Identifier)
        
        if let oneToOneIdentifier {
            self.oneToOneIdentifier = oneToOneIdentifier
            self.groupV1Identifier = nil
            self.groupV2Identifier = nil
        } else if let groupUidRaw = groupUidRaw,
            let groupOwnerIdentity = groupOwnerIdentity,
            let groupUid = UID(uid: groupUidRaw),
            let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) {
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = GroupV1Identifier(groupUid: groupUid, groupOwner: groupOwner)
            self.groupV2Identifier = nil
        } else if let groupV2Identifier = groupV2Identifier {
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = nil
            self.groupV2Identifier = groupV2Identifier
        } else {
            throw ObvUICoreDataError.noDiscussionWasSpecified
        }
    }

}


public struct DiscussionReadJSON: Codable {
    
    public let lastReadMessageServerTimestamp: Date
    public let oneToOneIdentifier: OneToOneIdentifierJSON?
    public let groupV1Identifier: GroupV1Identifier?
    public let groupV2Identifier: GroupV2Identifier?

    enum CodingKeys: String, CodingKey {
        case lastReadMessageServerTimestamp = "tim"
        case groupUid = "guid" // For group V1
        case groupOwner = "go" // For group V1
        case groupV2Identifier = "gid2"
        case oneToOneIdentifier = "o2oi" // For one-to-one discussions
    }

    public init(lastReadMessageServerTimestamp: Date, oneToOneIdentifier: OneToOneIdentifierJSON) {
        self.lastReadMessageServerTimestamp = lastReadMessageServerTimestamp
        self.oneToOneIdentifier = oneToOneIdentifier
        self.groupV1Identifier = nil
        self.groupV2Identifier = nil
    }

    public init(lastReadMessageServerTimestamp: Date, groupV1Identifier: GroupV1Identifier) {
        self.lastReadMessageServerTimestamp = lastReadMessageServerTimestamp
        self.oneToOneIdentifier = nil
        self.groupV1Identifier = groupV1Identifier
        self.groupV2Identifier = nil
    }

    public init(lastReadMessageServerTimestamp: Date, groupV2Identifier: GroupV2Identifier) {
        self.lastReadMessageServerTimestamp = lastReadMessageServerTimestamp
        self.oneToOneIdentifier = nil
        self.groupV1Identifier = nil
        self.groupV2Identifier = groupV2Identifier
    }

    func jsonEncode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }

    static func jsonDecode(_ data: Data) throws -> ScreenCaptureDetectionJSON {
        let decoder = JSONDecoder()
        return try decoder.decode(ScreenCaptureDetectionJSON.self, from: data)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lastReadMessageServerTimestamp.epochInMs, forKey: .lastReadMessageServerTimestamp)
        try container.encodeIfPresent(oneToOneIdentifier, forKey: .oneToOneIdentifier)
        if let groupV1Identifier = groupV1Identifier {
            try container.encode(groupV1Identifier.groupUid.raw, forKey: .groupUid)
            try container.encode(groupV1Identifier.groupOwner.getIdentity(), forKey: .groupOwner)
        }
        try container.encodeIfPresent(groupV2Identifier, forKey: .groupV2Identifier)
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        
        let lastReadMessageServerTimestampInMilliseconds = try values.decode(Int64.self, forKey: .lastReadMessageServerTimestamp)
        self.lastReadMessageServerTimestamp = Date(epochInMs: lastReadMessageServerTimestampInMilliseconds)
        
        let oneToOneIdentifier = try values.decodeIfPresent(OneToOneIdentifierJSON.self, forKey: .oneToOneIdentifier)

        let groupUidRaw = try values.decodeIfPresent(Data.self, forKey: .groupUid)
        let groupOwnerIdentity = try values.decodeIfPresent(Data.self, forKey: .groupOwner)
        
        let groupV2Identifier = try values.decodeIfPresent(Data.self, forKey: .groupV2Identifier)
        
        if let oneToOneIdentifier {
            self.oneToOneIdentifier = oneToOneIdentifier
            self.groupV1Identifier = nil
            self.groupV2Identifier = nil
        } else if let groupUidRaw = groupUidRaw,
            let groupOwnerIdentity = groupOwnerIdentity,
            let groupUid = UID(uid: groupUidRaw),
            let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) {
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = GroupV1Identifier(groupUid: groupUid, groupOwner: groupOwner)
            self.groupV2Identifier = nil
        } else if let groupV2Identifier = groupV2Identifier {
            self.oneToOneIdentifier = nil
            self.groupV1Identifier = nil
            self.groupV2Identifier = groupV2Identifier
        } else {
            throw ObvUICoreDataError.noDiscussionWasSpecified
        }
    }

    public func getDiscussionId(ownedCryptoId: ObvCryptoId) throws -> DiscussionIdentifier {
        if let groupV1Identifier {
            return .groupV1(id: .groupV1Identifier(groupV1Identifier: groupV1Identifier))
        } else if let groupV2Identifier {
            return .groupV2(id: .groupV2Identifier(groupV2Identifier: groupV2Identifier))
        } else if let oneToOneIdentifier {
            guard let contactCryptoId = oneToOneIdentifier.getContactIdentity(ownedIdentity: ownedCryptoId) else {
                assertionFailure()
                throw ObvUICoreDataError.couldNotDetermineDiscussionIdentifier
            }
            return .oneToOne(id: .contactCryptoId(contactCryptoId: contactCryptoId))
        } else {
            throw ObvUICoreDataError.noDiscussionWasSpecified
        }
    }

}



// MARK: - Private Helpers

private extension Data {
    
    func toUID() -> UID? {
        return UID(uid: self)
    }
    
}
