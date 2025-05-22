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
import ObvUICoreData
import ObvCircleAndTitlesView
import ObvDesignSystem


extension PersistedObvOwnedIdentity {

    var circleAndTitlesViewModelContent: CircleAndTitlesView.Model.Content {
        .init(textViewModel: self.textViewModel,
              profilePictureViewModelContent: self.profilePictureViewModelContent)
    }

}


extension PersistedGroupV2Member {

    var circleAndTitlesViewModelContent: CircleAndTitlesView.Model.Content {
        .init(textViewModel: self.textViewModel,
              profilePictureViewModelContent: self.profilePictureViewModelContent)
    }

}



extension PersistedObvOwnedIdentity {

    var initialCircleViewModelColors: InitialCircleView.Model.Colors {
        .init(background: self.circledInitialsConfiguration.backgroundColor(appTheme: AppTheme.shared),
              foreground: self.circledInitialsConfiguration.foregroundColor(appTheme: AppTheme.shared))
    }

}

extension PersistedGroupV2Member {

    var initialCircleViewModelColors: InitialCircleView.Model.Colors {
        .init(background: self.circledInitialsConfiguration.backgroundColor(appTheme: AppTheme.shared),
              foreground: self.circledInitialsConfiguration.foregroundColor(appTheme: AppTheme.shared))
    }

}



extension PersistedObvOwnedIdentity {

    var profilePictureViewModelContent: ProfilePictureView.Model.Content {
        .init(text: self.circledInitialsConfiguration.initials?.text ?? "",
              icon: .person,
              profilePicture: self.circledInitialsConfiguration.photo,
              showGreenShield: self.circledInitialsConfiguration.showGreenShield,
              showRedShield: self.circledInitialsConfiguration.showRedShield)
    }

}


extension PersistedGroupV2Member {

    var profilePictureViewModelContent: ProfilePictureView.Model.Content {
        .init(text: self.circledInitialsConfiguration.initials?.text ?? "",
              icon: .person,
              profilePicture: self.circledInitialsConfiguration.photo,
              showGreenShield: self.circledInitialsConfiguration.showGreenShield,
              showRedShield: self.circledInitialsConfiguration.showRedShield)
    }

}


extension PersistedObvOwnedIdentity {

    var textViewModel: TextView.Model {
        .init(titlePart1: self.identityCoreDetails.firstName,
              titlePart2: self.identityCoreDetails.lastName,
              subtitle: self.identityCoreDetails.position,
              subsubtitle: self.identityCoreDetails.company)
    }

}


extension PersistedGroupV2Member {

    var textViewModel: TextView.Model {
        .init(titlePart1: self.displayedFirstName,
              titlePart2: self.displayedCustomDisplayNameOrLastName,
              subtitle: self.displayedPosition,
              subsubtitle: self.displayedCompany)
    }

}
