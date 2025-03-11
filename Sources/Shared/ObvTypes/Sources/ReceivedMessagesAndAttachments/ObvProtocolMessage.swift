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
import ObvEncoder


/// When the app receives an encrypted notification, it requests decryption from the engine.
/// If the notification is an encrypted user message (delivered via APNs) and the decrypted content
/// is a protocol message, the engine returns an `ObvProtocolMessage` (wrapped in a `ObvDecryptedNotification`).
///
/// Note that creating an `ObvProtocolMessage` is done by using the initializer defined in an `ObvProtocolMessage` extension at
/// protocol manager level.
public enum ObvProtocolMessage {

    case mutualIntroduction(mediator: ObvContactIdentifier, introducedIdentity: ObvCryptoId, introducedIdentityCoreDetails: ObvIdentityCoreDetails)
    
    public var ownedCryptoId: ObvCryptoId {
        switch self {
        case .mutualIntroduction(mediator: let mediator, introducedIdentity: _, introducedIdentityCoreDetails: _):
            return mediator.ownedCryptoId
        }
    }
    
    fileprivate var rawKind: ObvProtocolMessageRawKind {
        switch self {
        case .mutualIntroduction: return .mutualIntroduction
        }
    }
    
    
    public func obvEqual(to other: ObvProtocolMessage) -> Bool {
        switch self {
        case .mutualIntroduction(let mediator1, let introducedIdentity1, _):
            switch other {
            case .mutualIntroduction(let mediator2, let introducedIdentity2, _):
                return mediator1 == mediator2 && introducedIdentity1 == introducedIdentity2
            }
        }
    }
    
}


extension ObvProtocolMessage: ObvFailableCodable {
        
    public func obvEncode() throws -> ObvEncoded {
        do {
            switch self {
            case .mutualIntroduction(let mediator, let introducedIdentity, let introducedIdentityCoreDetails):
                return [
                    self.rawKind.obvEncode(),
                    mediator.obvEncode(),
                    introducedIdentity.obvEncode(),
                    try introducedIdentityCoreDetails.jsonEncode().obvEncode(),
                ].obvEncode()
            }
        } catch {
            assertionFailure()
            throw error
        }
    }
    
    public init?(_ obvEncoded: ObvEncoded) {
        guard let encodeds = [ObvEncoded](obvEncoded) else { assertionFailure(); return nil }
        guard !encodeds.isEmpty else { assertionFailure(); return nil }
        guard let rawKind = ObvProtocolMessageRawKind(encodeds[0]) else { assertionFailure(); return nil }
        switch rawKind {
        case .mutualIntroduction:
            guard encodeds.count == 4 else { assertionFailure(); return nil }
            do {
                let mediator: ObvContactIdentifier = try encodeds[1].obvDecode()
                let introducedIdentity: ObvCryptoId = try encodeds[2].obvDecode()
                let introducedIdentityCoreDetailsRaw: Data = try encodeds[3].obvDecode()
                let introducedIdentityCoreDetails: ObvIdentityCoreDetails = try ObvIdentityCoreDetails.jsonDecode(introducedIdentityCoreDetailsRaw)
                self = .mutualIntroduction(mediator: mediator, introducedIdentity: introducedIdentity, introducedIdentityCoreDetails: introducedIdentityCoreDetails)
            } catch {
                assertionFailure()
                return nil
            }
        }
    }
    
}


// MARK: - Private Raw Kind

private enum ObvProtocolMessageRawKind: Int {
    
    case mutualIntroduction = 0
    
    private var obvProtocolMessageType: Any {
        switch self {
        case .mutualIntroduction:
            return ObvProtocolMessage.mutualIntroduction
        }
    }
    
}


extension ObvProtocolMessageRawKind: ObvCodable {
    
    func obvEncode() -> ObvEncoded {
        self.rawValue.obvEncode()
    }
    
    init?(_ obvEncoded: ObvEncoded) {
        guard let rawValue = Int(obvEncoded) else { assertionFailure(); return nil }
        guard let value = Self.init(rawValue: rawValue) else { assertionFailure(); return nil }
        self = value
    }
    
}
