/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import CoreData
import ObvUICoreData
import ObvTypes
import ObvSingleOwnedIdentity


@MainActor
protocol ObvChooseDeviceToReactivateViewAppDataSourceDelegate: AnyObject {
    func performOwnedDeviceDiscoveryNow(_ dataSource: ObvChooseDeviceToReactivateViewAppDataSource, ownedCryptoId: ObvTypes.ObvCryptoId) async throws -> ObvTypes.ObvOwnedDeviceDiscoveryResult
}


@MainActor
final class ObvChooseDeviceToReactivateViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext
    weak var delegate: ObvChooseDeviceToReactivateViewAppDataSourceDelegate?

    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext, delegate: ObvChooseDeviceToReactivateViewAppDataSourceDelegate) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
        self.delegate = delegate
    }

}


extension ObvChooseDeviceToReactivateViewAppDataSource: ObvChooseDeviceToReactivateViewDataSource {
    
    func getObvChooseDeviceToReactivateViewModel(_ view: ObvSingleOwnedIdentity.ObvChooseDeviceToReactivateView, ownedCryptoId: ObvCryptoId) async throws -> ObvSingleOwnedIdentity.ObvChooseDeviceToReactivateView.Model {
        assert(Thread.isMainThread)
        guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: ObvStack.shared.viewContext) else {
            throw ObvError.ownedIdentityIsNil
        }
        return try .init(ownedIdentity: ownedIdentity)
    }
    
    func performOwnedDeviceDiscoveryNow(_ view: ObvSingleOwnedIdentity.ObvChooseDeviceToReactivateView, ownedCryptoId: ObvTypes.ObvCryptoId) async throws -> ObvTypes.ObvOwnedDeviceDiscoveryResult {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        return try await delegate.performOwnedDeviceDiscoveryNow(self, ownedCryptoId: ownedCryptoId)
    }
    
}


extension ObvChooseDeviceToReactivateViewAppDataSource {
    
    enum ObvError: Error {
        case ownedIdentityIsNil
        case delegateIsNil
    }
    
}


extension ObvSingleOwnedIdentity.ObvChooseDeviceToReactivateView.Model {
    
    init(ownedIdentity: PersistedObvOwnedIdentity) throws {
        guard let currentDevice = ownedIdentity.currentDevice else {
            throw ObvChooseDeviceToReactivateViewModelInitError.currentDeviceIsNil
        }
        self.init(currentDeviceName: currentDevice.name,
                  currentDeviceIdentifier: currentDevice.identifier)
    }
    
    enum ObvChooseDeviceToReactivateViewModelInitError: Error {
        case currentDeviceIsNil
    }
    
}
