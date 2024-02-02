/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import UIKit
import SwiftUI
import ObvTypes
import ObvEngine


protocol ChooseDeviceToReactivateHostingViewControllerDelegate: AnyObject {
    func userWantsToDismissChooseDeviceToReactivateHostingViewController() async
}


final class ChooseDeviceToReactivateHostingViewController: UIHostingController<ChooseDeviceToReactivateView<ChooseDeviceToReactivateViewModel>>, ChooseDeviceToReactivateViewActionsDelegate {
    
    let obvEngine: ObvEngine
    let model: ChooseDeviceToReactivateViewModel
    weak var delegate: ChooseDeviceToReactivateHostingViewControllerDelegate?
    
    init(model: ChooseDeviceToReactivateViewModel, obvEngine: ObvEngine, delegate: ChooseDeviceToReactivateHostingViewControllerDelegate) {
        self.obvEngine = obvEngine
        self.model = model
        self.delegate = delegate
        let actions = ChooseDeviceToReactivateViewActions()
        let rootView = ChooseDeviceToReactivateView(model: model, actions: actions)
        super.init(rootView: rootView)
        actions.delegate = self
    }
    
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    // MARK: ChooseDeviceToReactivateViewActionsDelegate
    
    
    func theReactivationProgressViewDidAppear(ownedCryptoId: ObvCryptoId) async {
        do {
            let ownedDeviceDiscoveryResult = try await obvEngine.performOwnedDeviceDiscoveryNow(ownedCryptoId: ownedCryptoId)
            model.updateStatusWith(ownedDeviceDiscoveryResult: ownedDeviceDiscoveryResult)
        } catch {
            assertionFailure()
            model.updateStatusAsServerQueryFailed()
        }

    }
    
    
    @MainActor
    func userWantsToCancelReactivationOfCurrentDevice() async {
        await delegate?.userWantsToDismissChooseDeviceToReactivateHostingViewController()
    }
    
    
    @MainActor
    func userWantsToActivateCurrentDevice(ownedCryptoId: ObvCryptoId, currentDeviceIdentifier: Data, deviceIdentifierOfOtherDeviceToDeactivate: Data?) async {
        showHUD(type: .spinner)
        do {
            try await ObvPushNotificationManager.shared.userRequestedReactivationOf(ownedCryptoId: ownedCryptoId, replacedDeviceIdentifier: deviceIdentifierOfOtherDeviceToDeactivate)
            showHUD(type: .checkmark)
            await suspendDuringTimeInterval(1.5)
            hideHUD()
            await delegate?.userWantsToDismissChooseDeviceToReactivateHostingViewController()
        } catch {
            showHUD(type: .xmark)
            await suspendDuringTimeInterval(1.5)
            hideHUD()
        }
    }

}



// MARK: - ChooseDeviceToReactivateViewModel

final class ChooseDeviceToReactivateViewModel: ObservableObject, ChooseDeviceToReactivateViewModelProtocol {
        
    struct Device: DeviceCardViewModelProtocol {
        let deviceIdentifier: Data
        let deviceName: String
        let expirationDate: Date?
        let latestRegistrationDate: Date?
    }
    
    let ownedCryptoId: ObvCryptoId
    let currentDeviceName: String
    let currentDeviceIdentifier: Data
    @Published var status: ChooseDeviceToReactivateViewStatus<Device>

    init(ownedCryptoId: ObvCryptoId, currentDeviceName: String, currentDeviceIdentifier: Data) {
        self.ownedCryptoId = ownedCryptoId
        self.currentDeviceName = currentDeviceName
        self.currentDeviceIdentifier = currentDeviceIdentifier
        self.status = .queryingServer
    }
    
    
    fileprivate func updateStatusWith(ownedDeviceDiscoveryResult: ObvOwnedDeviceDiscoveryResult) {
        
        let devicesFromServer = ownedDeviceDiscoveryResult.devices.map {
            Device(deviceIdentifier: $0.identifier, deviceName: $0.name ?? String($0.identifier.hexString().prefix(4)), expirationDate: $0.expirationDate, latestRegistrationDate: $0.latestRegistrationDate)
        }

        let serverAnswerReceivedStatus: ChooseDeviceToReactivateViewStatus<Device>.ServerAnswerReceivedStatus
        if ownedDeviceDiscoveryResult.devices.isEmpty {
            serverAnswerReceivedStatus = .noActiveDeviceFoundOnServer
        } else if ownedDeviceDiscoveryResult.isMultidevice {
            serverAnswerReceivedStatus = .multideviceFeatureAvailable(devicesFromServer: devicesFromServer)
        } else if ownedDeviceDiscoveryResult.devices.allSatisfy({ $0.expirationDate != nil }) {
            serverAnswerReceivedStatus = .multideviceFeatureUnavailableAndAllActiveDevicesExpire(devicesFromServer: devicesFromServer)
        } else {
            serverAnswerReceivedStatus = .multideviceFeatureUnavailableAndAtLeastOneNonExpiringActiveDeviceFound(devicesFromServer: devicesFromServer)
        }

        withAnimation {
            self.status = .serverAnswerReceived(status: serverAnswerReceivedStatus)
        }
        
    }
    
    
    fileprivate func updateStatusAsServerQueryFailed() {
        withAnimation {
            self.status = .serverQueryFailed
        }
    }
    
}





fileprivate final class ChooseDeviceToReactivateViewActions: ChooseDeviceToReactivateViewActionsDelegate {
        
    var delegate: ChooseDeviceToReactivateViewActionsDelegate?
    
    func theReactivationProgressViewDidAppear(ownedCryptoId: ObvCryptoId) async {
        await delegate?.theReactivationProgressViewDidAppear(ownedCryptoId: ownedCryptoId)
    }
    
    func userWantsToCancelReactivationOfCurrentDevice() async {
        await delegate?.userWantsToCancelReactivationOfCurrentDevice()
    }
    
    func userWantsToActivateCurrentDevice(ownedCryptoId: ObvTypes.ObvCryptoId, currentDeviceIdentifier: Data, deviceIdentifierOfOtherDeviceToDeactivate: Data?) async {
        await delegate?.userWantsToActivateCurrentDevice(ownedCryptoId: ownedCryptoId, currentDeviceIdentifier: currentDeviceIdentifier, deviceIdentifierOfOtherDeviceToDeactivate: deviceIdentifierOfOtherDeviceToDeactivate)
    }
}
