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


@available(iOS 26.0, *)
typealias WiFiAwareConnection = NetworkConnection<Coder<NetworkEvent, NetworkEvent, NetworkJSONCoder>>
typealias WiFiAwareConnectionID = String


/// Bundles a live `WiFiAwareConnection` with its most recent `WAPerformanceReport`
/// so both can be stored and compared as a single value in `deviceConnections`.
/// Equality is based on `localTimestamp` so `deviceConnections` is only updated
/// when a new performance sample actually arrives.
@available(iOS 26.0, *)
struct ConnectionDetail: Sendable, Equatable {
    let connection: WiFiAwareConnection
    let performanceReport: WAPerformanceReport

    public static func == (lhs: ConnectionDetail, rhs: ConnectionDetail) -> Bool {
        return lhs.performanceReport.localTimestamp == rhs.performanceReport.localTimestamp
    }
}

/// Events originating on the local device that `WifiAwareTransferTransportDelegate` needs to react to.
///
/// Produced by two sources and consumed by `WifiAwareTransferTransportDelegate.handleLocalEvent`:
/// - `WifiAwareTransferTransportDelegate` yields browser/listener lifecycle events.
/// - `ConnectionManager` yields connection lifecycle and performance events.
@available(iOS 26.0, *)
enum LocalEvent: Sendable {
    /// The `NetworkBrowser` is running and scanning for publishers.
    case browserRunning
    /// The browser found a publisher endpoint and the viewer is now dialling it.
    case connecting
    /// The browser stopped, optionally with an error (e.g. timeout, no paired devices).
    case browserStopped(WAError?)

    /// The `NetworkListener` is running and accepting incoming connections.
    case listenerRunning
    /// The listener stopped, optionally with an error.
    case listenerStopped(WAError?)

    /// Sub-events for an individual peer connection.
    enum ConnectionEvent {
        /// The link is fully established; carries the remote device and initial metrics.
        case ready(WAPairedDevice, ConnectionDetail)
        /// A periodic performance sample arrived; carries updated signal/latency data.
        case performance(WAPairedDevice, ConnectionDetail)
        /// The connection was closed; carries the device, its ID for cleanup, and an
        /// optional error explaining why.
        case stopped(WAPairedDevice, WiFiAwareConnectionID, WAError?)
    }
    case connection(ConnectionEvent)
}

#endif // canImport(WiFiAware)
