/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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

#if canImport(WiFiAware)
import Foundation
import WiFiAware
import Network


// Publishable service declared in Info.plist

@available(iOS 26.0, *)
public extension WAPublishableService {
    static var chatHistoryTransferService: WAPublishableService? {
        allServices["_obv-chat-tran._tcp"]
    }
}


// Subscribable service declared in Info.plist

@available(iOS 26.0, *)
public extension WASubscribableService {
    static var chatHistoryTransferService: WASubscribableService? {
        allServices["_obv-chat-tran._tcp"]
    }
}


@available(iOS 26.0, *)
public extension WAAccessCategory {
    /// Maps a `WAAccessCategory` to the equivalent `NWParameters.ServiceClass` so the
    /// same QoS intent can be expressed to both the Wi-Fi Aware framework and the
    /// Network framework. Used in `NetworkConfig.swift` to derive `appServiceClass`
    /// from `appAccessCategory`.
    var serviceClass: NWParameters.ServiceClass {
        switch self {
        case .bestEffort: .bestEffort
        case .background: .background
        case .interactiveVideo: .interactiveVideo
        case .interactiveVoice: .interactiveVoice
        default : .bestEffort
        }
    }
}
#endif // canImport(WiFiAware)
