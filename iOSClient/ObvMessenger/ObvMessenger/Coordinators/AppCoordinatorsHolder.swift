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
  

import Foundation
import ObvEngine


final class AppCoordinatorsHolder {
    
    private let persistedDiscussionsUpdatesCoordinator: PersistedDiscussionsUpdatesCoordinator
    private let bootstrapCoordinator: BootstrapCoordinator
    private let obvOwnedIdentityCoordinator: ObvOwnedIdentityCoordinator
    private let contactIdentityCoordinator: ContactIdentityCoordinator
    private let contactGroupCoordinator: ContactGroupCoordinator

    
    init(obvEngine: ObvEngine) {

        let queueSharedAmongCoordinators = OperationQueue.createSerialQueue(name: "Queue shared among coordinators", qualityOfService: .default)
        
        self.persistedDiscussionsUpdatesCoordinator = PersistedDiscussionsUpdatesCoordinator(obvEngine: obvEngine, operationQueue: queueSharedAmongCoordinators)
        self.bootstrapCoordinator = BootstrapCoordinator(obvEngine: obvEngine, operationQueue: queueSharedAmongCoordinators)
        self.obvOwnedIdentityCoordinator = ObvOwnedIdentityCoordinator(obvEngine: obvEngine, operationQueue: queueSharedAmongCoordinators)
        self.contactIdentityCoordinator = ContactIdentityCoordinator(obvEngine: obvEngine, operationQueue: queueSharedAmongCoordinators)
        self.contactGroupCoordinator = ContactGroupCoordinator(obvEngine: obvEngine, operationQueue: queueSharedAmongCoordinators)
        
    }
    

    func applicationAppearedOnScreen(forTheFirstTime: Bool) async {
        await self.persistedDiscussionsUpdatesCoordinator.applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime)
        await self.bootstrapCoordinator.applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime)
        await self.obvOwnedIdentityCoordinator.applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime)
        await self.contactIdentityCoordinator.applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime)
        await self.contactGroupCoordinator.applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime)
    }

}
