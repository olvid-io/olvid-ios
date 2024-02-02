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

import UIKit
import SwiftUI
import ObvUICoreData
import ObvUI
import ObvEngine
import ObvTypes


final class ListOfContactDevicesViewController: UIHostingController<ContactDevicesListView<PersistedObvContactIdentity>>, ContactDevicesListViewActionsDelegate {
        
    private let obvEngine: ObvEngine
    
    init(persistedContact: PersistedObvContactIdentity, obvEngine: ObvEngine) {
        self.obvEngine = obvEngine
        let actions = ContactDevicesListViewActions()
        let rootView = ContactDevicesListView(model: persistedContact, actions: actions)
        super.init(rootView: rootView)
        actions.delegate = self
    }

    
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    
    // MARK: - ContactDevicesListViewActionsDelegate
    
    func userWantsToClearAllContactDevices(contactIdentifier: ObvContactIdentifier) async {
        DispatchQueue(label: "Background queue for deleteAllContactDevicesAndChannelsThenPerformContactDeviceDiscovery").async { [weak self] in
            try? self?.obvEngine.deleteAllContactDevicesAndChannelsThenPerformContactDeviceDiscovery(contactIdentifier: contactIdentifier)
        }
    }
    
    func userWantsToSearchForNewContactDevices(contactIdentifier: ObvContactIdentifier) async {
        DispatchQueue(label: "Background queue for performContactDeviceDiscovery").async { [weak self] in
            try? self?.obvEngine.performContactDeviceDiscovery(contactIdentifier: contactIdentifier)
            DispatchQueue.main.async { [weak self] in
                self?.showHUD(type: .checkmark)
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) {
                    self?.hideHUD()
                }
            }
        }
    }
    
    func userWantsToRestartChannelCreationWithContactDevice(contactIdentifier: ObvContactIdentifier, deviceIdentifier: Data) async {
        DispatchQueue(label: "Background queue for recreateChannelWithContactDevice").async { [weak self] in
            try? self?.obvEngine.recreateChannelWithContactDevice(contactIdentifier: contactIdentifier, contactDeviceIdentifier: deviceIdentifier)
        }
    }
    
}




fileprivate final class ContactDevicesListViewActions: ContactDevicesListViewActionsDelegate {
    
    weak var delegate: ContactDevicesListViewActionsDelegate?
    
    func userWantsToClearAllContactDevices(contactIdentifier: ObvContactIdentifier) async {
        await delegate?.userWantsToClearAllContactDevices(contactIdentifier: contactIdentifier)
    }
    
    func userWantsToSearchForNewContactDevices(contactIdentifier: ObvContactIdentifier) async {
        await delegate?.userWantsToSearchForNewContactDevices(contactIdentifier: contactIdentifier)
    }
    
    func userWantsToRestartChannelCreationWithContactDevice(contactIdentifier: ObvContactIdentifier, deviceIdentifier: Data) async {
        await delegate?.userWantsToRestartChannelCreationWithContactDevice(contactIdentifier: contactIdentifier, deviceIdentifier: deviceIdentifier)
    }
    
}
