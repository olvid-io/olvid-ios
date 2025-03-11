/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import ObvUICoreData
import CoreLocation
import SwiftUI
import MapKit

@available(iOS 17.0, *)
@MainActor
protocol MapViewModelProtocol: ObservableObject {
    
    var ownedIdentity: PersistedObvOwnedIdentity { get }
    
    var isAnimated: Bool { get set }
    var hasAppeared: Bool { get set }
    var currentLocation: CLLocation? { get set }
        
    func centerToCurrentUser(shouldCenter: Bool) async
    func onTask() async
    func onAppear()
    func onDisappear()
    
    var position: MapCameraPosition { get set }
    var interactionModes: MapInteractionModes { get }
    var userPosition: CLLocationCoordinate2D? { get set }
}
