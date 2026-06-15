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
import OSLog
import WiFiAware
import Network
import ObvAppCoreConstants


@available(iOS 26.0, *)
typealias WiFiAwareConnectionState = (WiFiAwareConnection, WiFiAwareConnection.State)

@available(iOS 26.0, *)
private struct ConnectionInfo {
    let receiverTask: Task<Void, Error>
    let stateUpdateTask: Task<Void, Error>
    var remoteDevice: WAPairedDevice?
}


@available(iOS 26.0, *)
actor ConnectionManager: Sendable {
    
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "ConnectionManager")

    private var connections: [WiFiAwareConnectionID: WiFiAwareConnection] = [:]
    private var connectionsInfo: [WiFiAwareConnectionID: ConnectionInfo] = [:]
    
    /// Emits lifecycle and performance events about connections.
    /// Consumed by `WifiAwareTransferTransportDelegate`.
    public let localEvents: AsyncStream<LocalEvent>
    private let localEventsContinuation: AsyncStream<LocalEvent>.Continuation

    /// Emits messages received from the remote peer over Wi-Fi Aware
    /// (e.g. `srcDiscussionList`, `srcMessages`). Consumed by `WifiAwareTransferTransportDelegate`.
    public let networkEvents: AsyncStream<NetworkEvent>
    private let networkEventsContinuation: AsyncStream<NetworkEvent>.Continuation

    /// Creates the two async streams that feed events to `WifiAwareTransferTransportDelegate`.
    /// Called once when `WifiAwareTransferTransportDelegate` initializes and creates its `ConnectionManager`.
    init() {
        (self.localEvents, self.localEventsContinuation) = AsyncStream.makeStream(of: LocalEvent.self)
        (self.networkEvents, self.networkEventsContinuation) = AsyncStream.makeStream(of: NetworkEvent.self)
    }

    // MARK: - Setup

    /// Registers an already-created connection and starts monitoring it.
    ///
    /// Called on the source device.
    ///
    /// Called by the `NetworkListener` acceptance callback inside `WifiAwareTransferTransportDelegate.listen()`
    /// when it accepts a new incoming connection from the destination device. Spins up two background tasks
    /// for this connection: one to watch its state transitions (ready / failed / cancelled) and one to receive
    /// incoming messages. After this call the connection is tracked and its events will
    /// flow into `localEvents` and `networkEvents`.
    func add(_ connection: WiFiAwareConnection) {
        Self.logger.info("📰 Add connection: \(connection.debugDescription)")

        connectionsInfo[connection.id] = .init(receiverTask: setupReceiver(connection),
                                               stateUpdateTask: setupStateUpdateHandler(connection))
    }

    
    /// Creates a new outbound Wi-Fi Aware TCP connection to a discovered publisher endpoint
    /// and registers it via `add(_:)`.
    ///
    /// Called on the destination device.
    ///
    /// Called by `WifiAwareTransferTransportDelegate.browse()` after the browser has resolved the
    /// first available publisher endpoint. The connection is configured with the app's
    /// realtime performance mode and `interactiveVideo` service class. Once added, the
    /// state-update handler will emit `.connection(.ready(...))` when the link comes up.
    func setupConnection(to endpoint: WAEndpoint) {
        let connection = NetworkConnection(
            to:
                endpoint,
            using: .parameters {
                Coder(receiving: NetworkEvent.self, sending: NetworkEvent.self, using: NetworkJSONCoder()) {
                    TCP()
                }
            }
            .wifiAware { $0.performanceMode = appPerformanceMode }
            .serviceClass(appServiceClass)
        )

        Self.logger.info("📰 Set up connection: \(connection.debugDescription)\nto: \(endpoint)")

        add(connection)
    }

    // MARK: - State Updates

    /// Subscribes to state changes on a connection and translates them into `LocalEvent`s.
    ///
    /// Called once per connection inside `add(_:)`. The Wi-Fi Aware framework delivers
    /// `.ready` once the secure link is established; at that point the method reads the
    /// Wi-Fi Aware path to obtain the remote `WAPairedDevice` and the initial
    /// `WAPerformanceReport`, then yields `.connection(.ready(...))` so
    /// `WifiAwareTransferTransportDelegate` can update its transfer state and — on the
    /// destination side — send the `startStreaming` message to signal readiness to the source.
    ///
    /// If the connection fails, `.connection(.stopped(...))` is yielded with the wrapped
    /// `WAError` so the delegate can handle the disconnection.
    private func setupStateUpdateHandler(_ connection: WiFiAwareConnection) -> Task<Void, Error> {
        let (stream, continuation) = AsyncStream.makeStream(of: WiFiAwareConnectionState.self)

        connection.onStateUpdate { connection, state in
            Self.logger.info("📰 \(connection.debugDescription): \(String(describing: state))")
            continuation.yield((connection, state))
        }

        return Task {
            for await (connection, state) in stream {
                var connectionError: NWError? = nil

                switch state {
                case .setup, .waiting, .preparing: break

                case .ready:
                    connections[connection.id] = connection

                    if let wifiAwarePath = try await connection.currentPath?.wifiAware {
                        let connectedDevice = wifiAwarePath.endpoint.device
                        let performanceReport = wifiAwarePath.performance

                        let detail = ConnectionDetail(connection: connection, performanceReport: performanceReport)
                        localEventsContinuation.yield(.connection(.ready(connectedDevice, detail)))

                        connectionsInfo[connection.id]?.remoteDevice = connectedDevice
                    }

                case .failed(let error):
                    stop(connection)
                    connectionError = error
                    fallthrough

                case .cancelled:
                    guard let disconnectedDevice = connectionsInfo[connection.id]?.remoteDevice else { continue }
                    localEventsContinuation.yield(.connection(.stopped(disconnectedDevice, connection.id, connectionError?.wifiAware)))

                @unknown default: break
                }
            }
        }
    }

    
    // MARK: - Receive

    /// Listens for incoming messages on a connection and forwards them to `networkEvents`.
    ///
    /// Called once per connection inside `add(_:)`. The connection's `.messages` async
    /// sequence yields decoded `NetworkEvent` values (JSON over TCP). Each event is
    /// re-yielded on `networkEventsContinuation` so `WifiAwareTransferTransportDelegate.handleNetworkEvent`
    /// can act on it.
    private func setupReceiver(_ connection: WiFiAwareConnection) -> Task<Void, Error> {
        Self.logger.info("📰 Set up receiver: \(connection.debugDescription)")

        return Task {
            for try await (event, _) in connection.messages {
                networkEventsContinuation.yield(event)
            }
            Self.logger.info("📰 Receiver closed: \(connection.debugDescription)")
        }
    }

    
    // MARK: - Send

    /// Encodes and sends a `NetworkEvent` to a specific peer connection over Wi-Fi Aware.
    ///
    /// Called by `WifiAwareTransferTransportDelegate` when the destination needs to send
    /// `startStreaming` to the source, or by `sendToAll(_:)` when broadcasting messages
    /// to all connected peers. Failures are propagated to the caller.
    func send(_ event: NetworkEvent, to connection: WiFiAwareConnection) async throws {
        do {
            try await connection.send(event)
        } catch {
            Self.logger.error("📰 Failed to send to: \(connection.debugDescription): \(error)")
            throw error
        }
    }


    // MARK: - Teardown

    /// Cancels the receiver task for a connection and removes it from the live
    /// connections dictionary, stopping any further message delivery.
    ///
    /// Called when a connection transitions to `.failed` (inside `setupStateUpdateHandler`)
    /// or when the user explicitly disconnects a device via `WifiAwareTransferTransportDelegate.stopConnection(to:)`.
    /// The state-update task is left running briefly so it can still emit the final
    /// `.connection(.stopped(...))` event; `invalidate(_:)` cleans it up afterwards.
    func stop(_ connection: WiFiAwareConnection) {
        Self.logger.info("📰 Stop connection: \(connection.debugDescription)")
        connectionsInfo[connection.id]?.receiverTask.cancel()
        if let removedConnection = connections.removeValue(forKey: connection.id) {
            Self.logger.info("📰 Removed: \(removedConnection.debugDescription)")
        }
    }

    
    /// Cancels the state-update task for a connection ID and removes all associated
    /// tracking metadata.
    ///
    /// Called by `WifiAwareTransferTransportDelegate` after it has already processed the `.stopped` event,
    /// once it has had a chance to update its own state. Separating `stop` from `invalidate`
    /// ensures the `.stopped` event can still be emitted before the state-update task
    /// is torn down.
    func invalidate(_ id: WiFiAwareConnectionID) {
        Self.logger.info("📰 Invalidate connection ID: \(id)")
        connectionsInfo[id]?.stateUpdateTask.cancel()
        connectionsInfo.removeValue(forKey: id)
    }

    /// Cancels all background tasks and closes both async streams.
    ///
    /// Called automatically when `WifiAwareTransferTransportDelegate` is deallocated. Finishing the
    /// continuations causes the event-handler tasks to exit their `for await` loops and terminate cleanly.
    deinit {
        for info in connectionsInfo.values {
            info.receiverTask.cancel()
            info.stateUpdateTask.cancel()
        }
        connections.removeAll()

        localEventsContinuation.finish()
        networkEventsContinuation.finish()
    }

}

#endif // canImport(WiFiAware)
