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
import WiFiAware
import Network
import ObvAppCoreConstants

/// Requests the Wi-Fi Aware scheduler to minimise latency by prioritising this
/// connection's traffic. Used when configuring both the listener and outbound connections.
@available(iOS 26.0, *)
let appPerformanceMode: WAPerformanceMode = .realtime

/// Maps to the `interactiveVideo` QoS tier, used for history transfer traffic
/// over the Wi-Fi Aware connection.
@available(iOS 26.0, *)
let appAccessCategory: WAAccessCategory = .interactiveVideo

/// The `NWParameters` service class derived from `appAccessCategory`, applied to
/// both the listener and outbound connections so the OS scheduler treats transfer
/// messages as interactive traffic end-to-end.
@available(iOS 26.0, *)
let appServiceClass: NWParameters.ServiceClass = appAccessCategory.serviceClass

#endif // canImport(WiFiAware)
