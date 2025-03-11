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
import ObvCrypto
import ObvTypes
import ObvEncoder


/// Identifies a sent or received message at the App level.
///
/// This type is distinct from ``ObvTypes.ObvMessageIdentifier`` as it uses the `senderIdentifier`, `senderThreadIdentifier`, and `senderSequenceNumber` instead of the message identifier from server to identify a message.
public enum ObvMessageAppIdentifier {
    
    case sent(discussionIdentifier: ObvDiscussionIdentifier, senderThreadIdentifier: UUID, senderSequenceNumber: Int)
    case received(discussionIdentifier: ObvDiscussionIdentifier, senderIdentifier: Data, senderThreadIdentifier: UUID, senderSequenceNumber: Int)
    
}


extension ObvMessageAppIdentifier: Equatable, Hashable {}

extension ObvMessageAppIdentifier {
    
    public var discussionIdentifier: ObvDiscussionIdentifier {
        switch self {
        case .sent(discussionIdentifier: let discussionIdentifier, _, _):
            return discussionIdentifier
        case .received(discussionIdentifier: let discussionIdentifier, _, _, _):
            return discussionIdentifier
        }
    }
    
    public var senderThreadIdentifier: UUID {
        switch self {
        case .sent(_, senderThreadIdentifier: let senderThreadIdentifier, _):
            return senderThreadIdentifier
        case .received(_, _, senderThreadIdentifier: let senderThreadIdentifier, _):
            return senderThreadIdentifier
        }
    }
    
    public var senderSequenceNumber: Int {
        switch self {
        case .sent(_, _, senderSequenceNumber: let senderSequenceNumber):
            return senderSequenceNumber
        case .received(_, _, _, senderSequenceNumber: let senderSequenceNumber):
            return senderSequenceNumber
        }
    }
    
    /// Sender of a received message. Nil for a sent message.
    public var contactIdentifier: ObvContactIdentifier? {
        switch self {
        case .sent:
            return nil
        case .received(discussionIdentifier: let discussionIdentifier, senderIdentifier: let senderIdentifier, senderThreadIdentifier: _, senderSequenceNumber: _):
            guard let contactCryptoId = try? ObvCryptoId(identity: senderIdentifier) else { assertionFailure(); return nil }
            return .init(contactCryptoId: contactCryptoId, ownedCryptoId: discussionIdentifier.ownedCryptoId)
        }
    }
    
    public var isReceived: Bool {
        switch self {
        case .received: return true
        default: return false
        }
    }

    public var isSent: Bool {
        switch self {
        case .sent: return true
        default: return false
        }
    }

}


// MARK: - Implementing ObvCodable, used by LosslessStringConvertible

extension ObvMessageAppIdentifier: ObvCodable {
    
    public func obvEncode() -> ObvEncoded {
        switch self {
        case .sent(discussionIdentifier: let discussionIdentifier, senderThreadIdentifier: let senderThreadIdentifier, senderSequenceNumber: let senderSequenceNumber):
            return [
                self.direction.obvEncode(),
                discussionIdentifier.obvEncode(),
                senderThreadIdentifier.obvEncode(),
                senderSequenceNumber.obvEncode(),
            ].obvEncode()
        case .received(discussionIdentifier: let discussionIdentifier, senderIdentifier: let senderIdentifier, senderThreadIdentifier: let senderThreadIdentifier, senderSequenceNumber: let senderSequenceNumber):
            return [
                self.direction.obvEncode(),
                discussionIdentifier.obvEncode(),
                senderIdentifier.obvEncode(),
                senderThreadIdentifier.obvEncode(),
                senderSequenceNumber.obvEncode(),
            ].obvEncode()
        }
    }
    
    
    public init?(_ obvEncoded: ObvEncoded) {
        guard let encodeds = [ObvEncoded](obvEncoded) else {
            assertionFailure()
            return nil
        }
        guard !encodeds.isEmpty else { assertionFailure(); return nil }
        do {
            let direction: Direction = try encodeds[0].obvDecode()
            switch direction {
            case .sent:
                guard encodeds.count == 4 else { assertionFailure(); return nil }
                let discussionIdentifier: ObvDiscussionIdentifier = try encodeds[1].obvDecode()
                let senderThreadIdentifier: UUID = try encodeds[2].obvDecode()
                let senderSequenceNumber: Int = try encodeds[3].obvDecode()
                self = .sent(discussionIdentifier: discussionIdentifier,
                             senderThreadIdentifier: senderThreadIdentifier,
                             senderSequenceNumber: senderSequenceNumber)
            case .received:
                guard encodeds.count == 5 else { assertionFailure(); return nil }
                let discussionIdentifier: ObvDiscussionIdentifier = try encodeds[1].obvDecode()
                let senderIdentifier: Data = try encodeds[2].obvDecode()
                let senderThreadIdentifier: UUID = try encodeds[3].obvDecode()
                let senderSequenceNumber: Int = try encodeds[4].obvDecode()
                self = .received(discussionIdentifier: discussionIdentifier,
                                 senderIdentifier: senderIdentifier,
                                 senderThreadIdentifier: senderThreadIdentifier,
                                 senderSequenceNumber: senderSequenceNumber)
            }
        } catch {
            assertionFailure()
            return nil
        }
    }
    
    
    private var direction: Direction {
        switch self {
        case .sent: return .sent
        case .received: return .received
        }
    }

    
    private enum Direction: String, ObvCodable {
        
        case sent = "s"
        case received = "r"
        
        func obvEncode() -> ObvEncoded {
            self.rawValue.obvEncode()
        }
        
        init?(_ obvEncoded: ObvEncoded) {
            guard let rawValue: String = try? obvEncoded.obvDecode() else {
                assertionFailure()
                return nil
            }
            self.init(rawValue: rawValue)
        }
        
    }

}


// MARK: - Implementing LosslessStringConvertible, leveraging the ObvCodable conformance

extension ObvMessageAppIdentifier: LosslessStringConvertible {
    
    
    public var description: String {
        self.obvEncode().rawData.hexString()
    }
    
    
    public init?(_ description: String) {
        guard let rawData = Data(hexString: description) else { assertionFailure(); return nil }
        guard let encoded = ObvEncoded(withRawData: rawData) else { assertionFailure(); return nil}
        do {
            self = try encoded.obvDecode()
        } catch {
            assertionFailure()
            return nil
        }
    }
    
}


//extension ObvMessageAppIdentifier: Codable {
//    
//    /// This serialization should **not** be changed as it used for long terme storage (typicially, in siri intents).
//
//    enum CodingKeys: String, CodingKey {
//        case direction = "d"
//        case discussionIdentifier = "di"
//        case senderIdentifier = "si"
//        case senderThreadIdentifier = "sti"
//        case senderSequenceNumber = "ssn"
//    }
//    
//    
//    public func encode(to encoder: any Encoder) throws {
//        do {
//            var container = encoder.container(keyedBy: CodingKeys.self)
//            try container.encode(self.directionRaw, forKey: .direction)
//            switch self {
//            case .sent(discussionIdentifier: let discussionIdentifier, senderThreadIdentifier: let senderThreadIdentifier, senderSequenceNumber: let senderSequenceNumber):
//                try container.encode(discussionIdentifier, forKey: .discussionIdentifier)
//                try container.encode(senderThreadIdentifier, forKey: .senderThreadIdentifier)
//                try container.encode(senderSequenceNumber, forKey: .senderSequenceNumber)
//            case .received(discussionIdentifier: let discussionIdentifier, senderIdentifier: let senderIdentifier, senderThreadIdentifier: let senderThreadIdentifier, senderSequenceNumber: let senderSequenceNumber):
//                try container.encode(discussionIdentifier, forKey: .discussionIdentifier)
//                try container.encode(senderIdentifier, forKey: .senderIdentifier)
//                try container.encode(senderThreadIdentifier, forKey: .senderThreadIdentifier)
//                try container.encode(senderSequenceNumber, forKey: .senderSequenceNumber)
//            }
//        } catch {
//            assertionFailure()
//            throw error
//        }
//    }
//    
//    
//    public init(from decoder: any Decoder) throws {
//        let values = try decoder.container(keyedBy: CodingKeys.self)
//        let directionRaw = try values.decode(DirectionRaw.self, forKey: .direction)
//        switch directionRaw {
//        case .sent:
//            let discussionIdentifier = try values.decode(ObvDiscussionIdentifier.self, forKey: .discussionIdentifier)
//            let senderThreadIdentifier = try values.decode(UUID.self, forKey: .senderThreadIdentifier)
//            let senderSequenceNumber = try values.decode(Int.self, forKey: .senderSequenceNumber)
//            self = .sent(discussionIdentifier: discussionIdentifier, senderThreadIdentifier: senderThreadIdentifier, senderSequenceNumber: senderSequenceNumber)
//        case .received:
//            let discussionIdentifier = try values.decode(ObvDiscussionIdentifier.self, forKey: .discussionIdentifier)
//            let senderIdentifier = try values.decode(Data.self, forKey: .senderIdentifier)
//            let senderThreadIdentifier = try values.decode(UUID.self, forKey: .senderThreadIdentifier)
//            let senderSequenceNumber = try values.decode(Int.self, forKey: .senderSequenceNumber)
//            self = .received(discussionIdentifier: discussionIdentifier, senderIdentifier: senderIdentifier, senderThreadIdentifier: senderThreadIdentifier, senderSequenceNumber: senderSequenceNumber)
//        }
//    }
//
//    
//    private enum DirectionRaw: String, Codable {
//        case sent = "s"
//        case received = "r"
//    }
//    
//    
//    private var directionRaw: DirectionRaw {
//        switch self {
//        case .sent: return .sent
//        case .received: return .received
//        }
//    }
//
//    
//    public func encodeToJson() throws -> Data {
//        let encoder = JSONEncoder()
//        return try encoder.encode(self)
//    }
//    
//    
//    public static func decodeFromJson(data: Data) throws -> Self {
//        let decoder = JSONDecoder()
//        return try decoder.decode(Self.self, from: data)
//    }
//
//}

// MARK: - LosslessStringConvertible (almost)

//extension ObvMessageAppIdentifier {
//
//    /// Since this getter can throw, we cannot conform to CustomStringConvertible and thus, we cannot conform to LosslessStringConvertible.
//    public var description: String {
//        get throws {
//            try self.encodeToJson().base64EncodedString()
//        }
//    }
//    
//    
//    public init?(_ description: String) {
//        guard let data = Data(base64Encoded: description) else { assertionFailure(); return nil }
//        do {
//            self = try Self.decodeFromJson(data: data)
//        } catch {
//            assertionFailure()
//            return nil
//        }
//    }
//
//}
