/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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
  

import UIKit
import os.log
import ObvEngine
import ObvAppCoreConstants


actor WebSocketManager {
    
    private static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: "WebSocketManager")

    private let obvEngine: ObvEngine
    
    init(obvEngine: ObvEngine) {
        self.obvEngine = obvEngine
    }
    
    private var observationTokens = [NSObjectProtocol]()

    private var currentStateNeedsWebsockets = false
    private var anIncomingCallRequiresWebSocket = false
    private var iOSLifecycleStateRequiresWebSocket = false

    func performPostInitialization() async {
        await observeNotifications()
    }
    
    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func storeObservationTokens(observationTokens: [NSObjectProtocol]) {
        self.observationTokens += observationTokens
    }

    
    func applicationWasInitializedButWasNeverOnScreen() async {
        // This is required when performing a cold launch, not clear why.
        setiOSLifecycleStateRequiresWebSocket(to: true)
    }
    
    
    @MainActor
    private func observeNotifications() async {
        os_log("🧦 observeAppBasedLifeCycleEvents", log: Self.log, type: .info)
        let didEnterBackgroundNotification = UIApplication.didEnterBackgroundNotification
        let willTerminateNotification = UIApplication.willTerminateNotification
        let didBecomeActiveNotification = UIApplication.didBecomeActiveNotification
        let willEnterForegroundNotification = UIApplication.willEnterForegroundNotification
        let tokens = [
            NotificationCenter.default.addObserver(forName: willEnterForegroundNotification, object: nil, queue: nil) { [weak self] _ in
                os_log("🧦 willEnterForegroundNotification", log: Self.log, type: .info)
                Task { [weak self] in await self?.setiOSLifecycleStateRequiresWebSocket(to: true) }
            },
            NotificationCenter.default.addObserver(forName: didBecomeActiveNotification, object: nil, queue: nil) { _ in
                os_log("🧦 didBecomeActiveNotification", log: Self.log, type: .info)
                Task { [weak self] in await self?.setiOSLifecycleStateRequiresWebSocket(to: true) }
            },
            NotificationCenter.default.addObserver(forName: didEnterBackgroundNotification, object: nil, queue: nil) { _ in
                 os_log("didEnterBackgroundNotification", log: Self.log, type: .info)
                 Task { [weak self] in await self?.setiOSLifecycleStateRequiresWebSocket(to: false) }
            },
            NotificationCenter.default.addObserver(forName: willTerminateNotification, object: nil, queue: nil) { _ in
                os_log("🧦 willTerminateNotification", log: Self.log, type: .info)
                Task { [weak self] in await self?.setiOSLifecycleStateRequiresWebSocket(to: false) }
            },
            VoIPNotification.observeNewCallToShow { _ in
                os_log("🧦 observeNewIncomingCall", log: Self.log, type: .info)
                Task { [weak self] in await self?.setAnIncomingCallRequiresWebSocket(to: true) }
            },
            VoIPNotification.observeNoMoreCallInProgress {
                os_log("🧦 noMoreCallInProgress", log: Self.log, type: .info)
                Task { [weak self] in await self?.setAnIncomingCallRequiresWebSocket(to: false) }
            },
        ]
        await storeObservationTokens(observationTokens: tokens)
    }
    
    
    private func setiOSLifecycleStateRequiresWebSocket(to value: Bool) {
        assert(!Thread.isMainThread)
        self.iOSLifecycleStateRequiresWebSocket = value
        connectOrDisconnectWebsocketAsAppropriate()
    }
    
    
    private func setAnIncomingCallRequiresWebSocket(to value: Bool) {
        assert(!Thread.isMainThread)
        self.anIncomingCallRequiresWebSocket = value
        connectOrDisconnectWebsocketAsAppropriate()
    }
    
    
    private func connectOrDisconnectWebsocketAsAppropriate() {
        assert(!Thread.isMainThread)
        let requiresWebSocket = iOSLifecycleStateRequiresWebSocket || anIncomingCallRequiresWebSocket
        guard requiresWebSocket != currentStateNeedsWebsockets else { return }
        currentStateNeedsWebsockets = requiresWebSocket
        if requiresWebSocket {
            Task { await connectWebsockets() }
        } else {
            Task { await disconnectWebsockets() }
        }
    }
    

    private func connectWebsockets() async {
        assert(!Thread.isMainThread)
        do {
            os_log("🧦🏁☎️🏓 Will request the engine to connect websockets", log: Self.log, type: .info)
            try await obvEngine.downloadMessagesAndConnectWebsockets()
        } catch {
            os_log("Could not download messages not connect websockets: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure()
        }
    }
    
    
    private func disconnectWebsockets() async {
        assert(!Thread.isMainThread)
        os_log("🏁☎️🏓 Will request the engine to disconnect websockets", log: Self.log, type: .info)
        do {
            try await obvEngine.disconnectWebsockets()
        } catch {
            os_log("🧦Could not disconnect websockets: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure()
        }
    }
    
}
