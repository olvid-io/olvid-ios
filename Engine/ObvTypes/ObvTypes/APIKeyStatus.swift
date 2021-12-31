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

/// valid: cle unipersonnelle, valide, pas expireee. Elle peut ne pas avoir de date d'expiration.
/// unknown: the server does not know the key. Access to free features only. C'est aussi ce qui est envoyé pour une clée normalement "free" ou "freeTrial" mais expirée.
/// licensesExhausted: attribuée a qqun d'autre.
/// expired: the key is valid, known in DB, unipersonnelle, mais expirée
/// free: (nombre de licence à -1 sur serveur),  quand c'est free et encore actif. C'est une cle pour beta.
/// freeTrial: quand c'est freeTrial et encore actif. Technique clé de MAC.
public enum APIKeyStatus: Int, CustomStringConvertible {
    
    case valid = 0
    case unknown = 1
    case licensesExhausted = 2
    case expired = 3
    case free = 4
    case freeTrial = 5
    case awaitingPaymentGracePeriod = 6
    case awaitingPaymentOnHold = 7
    case freeTrialExpired = 8
    
    public var description: String {
        switch self {
        case .valid: return "valid"
        case .unknown: return "unknow"
        case .licensesExhausted: return "licenses exhausted"
        case .expired: return "expired"
        case .free: return "free"
        case .freeTrial: return "free trial"
        case .awaitingPaymentGracePeriod: return "awaiting payment - grace period"
        case .awaitingPaymentOnHold: return "awaiting payment - on hold"
        case .freeTrialExpired: return "free trial expired"
        }
    }
    
    public var canBeActivated: Bool {
        switch self {
        case .valid, .free, .freeTrial:
            return true
        case .licensesExhausted, .expired, .unknown, .awaitingPaymentGracePeriod, .awaitingPaymentOnHold, .freeTrialExpired:
            return false
        }
    }
}


public struct APIPermissions: OptionSet {
    
    public let rawValue: Int
    
    public static let canCall = APIPermissions(rawValue: 1 << 0)
    
    public init(rawValue: Int) {
        assert(rawValue < 4)
        self.rawValue = rawValue
    }
}
