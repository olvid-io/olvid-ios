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
    
    public init(ownedIdentity: PersistedObvOwnedIdentity) {
        
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
                  photoURL: photoURL,
                  showGreenShield: ownedIdentity.isKeycloakManaged)
        
    }
    
    public init(ownedDevice: PersistedObvOwnedDevice) throws {
        guard let ownedIdentity = ownedDevice.ownedIdentity else {
            assertionFailure()
            throw ObvErrorCoreDataInitializers.ownedIdentityNotFound
        }
        self.init(ownedIdentity: ownedIdentity)
    }
    
    
    public init(contact: PersistedObvContactIdentity) {
        
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
                  photoURL: photoURL,
                  showGreenShield: contact.isCertifiedByOwnKeycloak)
        
    }
    
    
    public init(groupV2Member: PersistedGroupV2Member) {
        
        if let contact = groupV2Member.contact {
            
            self.init(contact: contact)
            
        } else {
            
            let character = (groupV2Member.firstName ?? groupV2Member.lastName)?.first
            let characterOrIcon: ObvAvatarViewModel.CharacterOrIcon
            if let character {
                characterOrIcon = .character(character)
            } else {
                characterOrIcon = .icon(.person)
            }
            
            let backgroundColor = groupV2Member.circledInitialsConfiguration.backgroundColor(appTheme: AppTheme.shared)
            let foregroundColor = groupV2Member.circledInitialsConfiguration.foregroundColor(appTheme: AppTheme.shared)
            let colors = ObvDesignSystem.ObvAvatarViewModel.Colors(foreground: foregroundColor, background: backgroundColor)
            
            self.init(characterOrIcon: characterOrIcon,
                      colors: colors,
                      photoURL: nil)
       }
        
    }
    
    
    public init(contactDevice: PersistedObvContactDevice) throws {
        guard let contact = contactDevice.identity else {
            assertionFailure()
            throw ObvErrorCoreDataInitializers.contactNotFound
        }
        self.init(contact: contact)
    }
    
    
    public init(continuousLocation: PersistedLocationContinuous) throws {
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
    
    
    public init(groupV1: PersistedContactGroup) {
        let backgroundColor = groupV1.circledInitialsConfiguration.backgroundColor(appTheme: AppTheme.shared)
        let foregroundColor = groupV1.circledInitialsConfiguration.foregroundColor(appTheme: AppTheme.shared)
        let colors = ObvDesignSystem.ObvAvatarViewModel.Colors(foreground: foregroundColor, background: backgroundColor)

        let photoURL = groupV1.displayPhotoURL // This takes into account the custom photo, if there is one

        self.init(characterOrIcon: .icon(.person3Fill),
                  colors: colors,
                  photoURL: photoURL)
    }
    
    
    public init(groupV2: PersistedGroupV2) {
        let backgroundColor = groupV2.circledInitialsConfiguration.backgroundColor(appTheme: AppTheme.shared)
        let foregroundColor = groupV2.circledInitialsConfiguration.foregroundColor(appTheme: AppTheme.shared)
        let colors = ObvDesignSystem.ObvAvatarViewModel.Colors(foreground: foregroundColor, background: backgroundColor)

        let photoURL = groupV2.displayPhotoURL // This takes into account the custom photo, if there is one

        self.init(characterOrIcon: .icon(.person3Fill),
                  colors: colors,
                  photoURL: photoURL,
                  showGreenShield: groupV2.keycloakManaged)
    }

    
    public init(displayedContactGroup: DisplayedContactGroup) throws {
        if let groupV1 = displayedContactGroup.groupV1 {
            self.init(groupV1: groupV1)
        } else if let groupV2 = displayedContactGroup.groupV2 {
            self.init(groupV2: groupV2)
        } else {
            throw ObvErrorCoreDataInitializers.groupNotFound
        }
    }
    
    
    public init(persistedDiscussion: PersistedDiscussion) throws {
        
        switch persistedDiscussion.status {
        case .preDiscussion, .active:
            
            switch try persistedDiscussion.kind {
            case .oneToOne(withContactIdentity: let withContactIdentity):
                guard let withContactIdentity else { assertionFailure(); throw ObvErrorCoreDataInitializers.contactNotFound }
                self.init(contact: withContactIdentity)
            case .groupV1(withContactGroup: let withContactGroup):
                guard let withContactGroup else { assertionFailure(); throw ObvErrorCoreDataInitializers.groupNotFound }
                self.init(groupV1: withContactGroup)
            case .groupV2(withGroup: let withGroup):
                guard let withGroup else { assertionFailure(); throw ObvErrorCoreDataInitializers.groupNotFound }
                self.init(groupV2: withGroup)
            }
            
        case .locked:
            
            self.init(characterOrIcon: .icon(.lock(.fill, .none)),
                      colors: .init(foreground: .secondaryLabel, background: .secondarySystemBackground),
                      photoURL: nil)
            
        }
        
    }
    
    
    enum ObvErrorCoreDataInitializers: Error {
        case ownedIdentityNotFound
        case contactNotFound
        case unexpectedPersistedLocationContinuousSubclass
        case ownedDeviceNotFound
        case contactDeviceNotFound
        case groupNotFound
    }
    
}


extension PersistedObvOwnedIdentity {
    
    public var avatarViewModel: ObvDesignSystem.ObvAvatarViewModel {
        .init(ownedIdentity: self)
    }
    
}


extension PersistedObvContactIdentity {
    
    public var avatarViewModel: ObvDesignSystem.ObvAvatarViewModel {
        .init(contact: self)
    }
    
}


extension PersistedObvOwnedDevice {
    
    public var avatarViewModel: ObvDesignSystem.ObvAvatarViewModel {
        get throws {
            try .init(ownedDevice: self)
        }
    }

}


extension PersistedObvContactDevice {
    
    public var avatarViewModel: ObvDesignSystem.ObvAvatarViewModel {
        get throws {
            try .init(contactDevice: self)
        }
    }
    
}


extension PersistedLocationContinuous {
    
    public var avatarViewModel: ObvDesignSystem.ObvAvatarViewModel {
        get throws {
            try .init(continuousLocation: self)
        }
    }

}


extension PersistedContactGroup {
    
    public var avatarViewModel: ObvDesignSystem.ObvAvatarViewModel {
        .init(groupV1: self)
    }

}


extension PersistedGroupV2 {
    
    public var avatarViewModel: ObvDesignSystem.ObvAvatarViewModel {
        .init(groupV2: self)
    }
    
}


extension PersistedDiscussion {
    
    public var avatarViewModel: ObvDesignSystem.ObvAvatarViewModel {
        get throws {
            try .init(persistedDiscussion: self)
        }
    }
    
}
