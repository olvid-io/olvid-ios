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


struct ObvWiFiAwareViewDefaultDataSource {
    
}


@available(iOS 26.0, *)
extension ObvWiFiAwareViewDefaultDataSource: ObvWiFiAwareViewDataSource {
    
    func getAsyncStreamOfObvWAPairedDevice(_ view: ObvWiFiAwareView) async -> AsyncThrowingStream<[ObvWAPairedDevice], any Error> {
        let stream = AsyncThrowingStream<[ObvWAPairedDevice], any Error> { (continuation: AsyncThrowingStream<[ObvWAPairedDevice], any Error>.Continuation) in
            Task {
                do {
                    for try await updatedDeviceList in WAPairedDevice.allDevices {
                        let pairedDevices: [ObvWAPairedDevice] = Array(updatedDeviceList.values).map({ .init(waPairedDevice: $0) })
                        continuation.yield(pairedDevices)
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
        return stream
    }
    
}


// MARK: - Helpers

private extension ObvWAPairedDevice.ObvPairingInfo {
    
    @available(iOS 26.0, *)
    init?(pairingInfo: WAPairedDevice.PairingInfo?) {
        guard let pairingInfo else { return nil }
        self = .init(vendorName: pairingInfo.vendorName,
                     modelName: pairingInfo.modelName,
                     pairingName: pairingInfo.pairingName,
                     description: pairingInfo.description)
    }
    
}

private extension ObvWAPairedDevice {
    
    @available(iOS 26.0, *)
    init(waPairedDevice: WAPairedDevice) {
        self = .init(id: waPairedDevice.id,
                     pairingInfo: .init(pairingInfo: waPairedDevice.pairingInfo))
    }
    
}

#endif // canImport(WiFiAware)
