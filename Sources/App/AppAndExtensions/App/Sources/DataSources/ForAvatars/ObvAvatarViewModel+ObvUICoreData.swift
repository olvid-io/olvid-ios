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
import ObvDesignSystem


extension ObvDesignSystem.ObvAvatarViewModel {
    
    init(ownedIdentity: PersistedObvOwnedIdentity) {
        
        let character = ownedIdentity.customOrFullDisplayName.first
        let characterOrIcon: CharacterOrIcon
        if let character {
            characterOrIcon = .character(character)
        } else {
            characterOrIcon = .icon(.person)
        }
        
        let backgroundColor = ownedIdentity.circledInitialsConfiguration.backgroundColor(appTheme: AppTheme.shared)
        let foregroundColor = ownedIdentity.circledInitialsConfiguration.foregroundColor(appTheme: AppTheme.shared)
        let colors = ObvDesignSystem.ObvAvatarViewModel.Colors(foreground: foregroundColor, background: backgroundColor)
        
        let photoURL = ownedIdentity.photoURL
        
        self.init(characterOrIcon: characterOrIcon,
                  colors: colors,
                  photoURL: photoURL)
        
    }
    
    init(ownedDevice: PersistedObvOwnedDevice) throws {
        guard let ownedIdentity = ownedDevice.ownedIdentity else {
            assertionFailure()
            throw ObvErrorCoreDataInitializers.ownedIdentityNotFound
        }
        self.init(ownedIdentity: ownedIdentity)
    }
    
    
    init(contact: PersistedObvContactIdentity) {
        
        let character = contact.customOrFullDisplayName.first
        let characterOrIcon: CharacterOrIcon
        if let character {
            characterOrIcon = .character(character)
        } else {
            characterOrIcon = .icon(.person)
        }

        let backgroundColor = contact.circledInitialsConfiguration.backgroundColor(appTheme: AppTheme.shared)
        let foregroundColor = contact.circledInitialsConfiguration.foregroundColor(appTheme: AppTheme.shared)
        let colors = ObvDesignSystem.ObvAvatarViewModel.Colors(foreground: foregroundColor, background: backgroundColor)

        let photoURL = contact.customPhotoURL ?? contact.photoURL
        
        self.init(characterOrIcon: characterOrIcon,
                  colors: colors,
                  photoURL: photoURL)
        
    }
    
    
    init(contactDevice: PersistedObvContactDevice) throws {
        guard let contact = contactDevice.identity else {
            assertionFailure()
            throw ObvErrorCoreDataInitializers.contactNotFound
        }
        self.init(contact: contact)
    }
    
    
    init(continuousLocation: PersistedLocationContinuous) throws {
        if let continuousLocationSent = continuousLocation as? PersistedLocationContinuousSent {
            guard let ownedDevice = continuousLocationSent.ownedDevice else {
                assertionFailure()
                throw ObvErrorCoreDataInitializers.ownedDeviceNotFound
            }
            try self.init(ownedDevice: ownedDevice)
        } else if let continuousLocationRecevied = continuousLocation as? PersistedLocationContinuousReceived {
            guard let contactDevice = continuousLocationRecevied.contactDevice else {
                assertionFailure()
                throw ObvErrorCoreDataInitializers.contactDeviceNotFound
            }
            try self.init(contactDevice: contactDevice)
        } else {
            assertionFailure()
            throw ObvErrorCoreDataInitializers.unexpectedPersistedLocationContinuousSubclass
        }
    }
    
    enum ObvErrorCoreDataInitializers: Error {
        case ownedIdentityNotFound
        case contactNotFound
        case unexpectedPersistedLocationContinuousSubclass
        case ownedDeviceNotFound
        case contactDeviceNotFound
    }
    
}


extension PersistedObvOwnedIdentity {
    
    var avatarViewModel: ObvDesignSystem.ObvAvatarViewModel {
        .init(ownedIdentity: self)
    }
    
}


extension PersistedObvContactIdentity {
    
    var avatarViewModel: ObvDesignSystem.ObvAvatarViewModel {
        .init(contact: self)
    }
    
}


extension PersistedObvOwnedDevice {
    
    var avatarViewModel: ObvDesignSystem.ObvAvatarViewModel {
        get throws {
            try .init(ownedDevice: self)
        }
    }

}


extension PersistedObvContactDevice {
    
    var avatarViewModel: ObvDesignSystem.ObvAvatarViewModel {
        get throws {
            try .init(contactDevice: self)
        }
    }
    
}


extension PersistedLocationContinuous {
    
    var avatarViewModel: ObvDesignSystem.ObvAvatarViewModel {
        get throws {
            try .init(continuousLocation: self)
        }
    }

}
