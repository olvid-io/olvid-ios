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
  
import ObvUI
import SwiftUI
import ObvUICoreData
import UI_ObvCircledInitials
import ObvDesignSystem

/// Legacy view. Use InitialCircleViewNew instead.
struct ProfilePictureView: View {

    struct Model {
        
        struct Content {
            let text: String?
            let icon: CircledInitialsIcon
            let profilePicture: UIImage?
            let showGreenShield: Bool
            let showRedShield: Bool
            
            var initialCircleViewModelContent: InitialCircleView.Model.Content {
                .init(text: text, icon: icon)
            }
            
        }

        let content: Content
        let colors: InitialCircleView.Model.Colors
        let circleDiameter: CGFloat

        init(content: Content, colors: InitialCircleView.Model.Colors, circleDiameter: CGFloat) {
            self.content = content
            self.colors = colors
            self.circleDiameter = circleDiameter
        }
        
        fileprivate var initialCircleViewModel: InitialCircleView.Model {
            .init(content: content.initialCircleViewModelContent,
                  colors: colors,
                  circleDiameter: circleDiameter)
        }
        
    }


    let model: Model

    init(model: Model) {
        self.model = model
    }

    var body: some View {
        Group {
            if let profilePicture = model.content.profilePicture {
                Image(uiImage: profilePicture)
                    .resizable()
                    .scaledToFit()
                    .frame(width: model.circleDiameter, height: model.circleDiameter)
                    .clipShape(Circle())
            } else {
                InitialCircleView(model: model.initialCircleViewModel)
            }
        }
        .overlay(Image(systemName: "checkmark.shield.fill")
            .font(.system(size: (model.circleDiameter) / 4))
            .foregroundColor(model.content.showGreenShield ? Color(AppTheme.shared.colorScheme.green) : .clear),
                 alignment: .topTrailing
        )
        .overlay(Image(systemIcon: .exclamationmarkShieldFill)
            .font(.system(size: (model.circleDiameter) / 2))
            .foregroundColor(model.content.showRedShield ? .red : .clear),
                 alignment: .center
        )
        
    }
}


// MARK: - NSManagedObjects extension

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
