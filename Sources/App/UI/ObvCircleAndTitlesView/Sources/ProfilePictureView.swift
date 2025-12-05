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
  
import SwiftUI
import ObvUIObvCircledInitials
import ObvDesignSystem


/// Legacy view. Use InitialCircleViewNew instead.
/// 2025-11-05: Not that clear we shouldn't use this view instead of `InitialCircleViewNew`
public struct ProfilePictureView: View {

    public struct Model {
        
        public struct Content {
            let text: String?
            let icon: CircledInitialsIcon
            let profilePicture: UIImage?
            let showGreenShield: Bool
            let showRedShield: Bool
            
            public init(text: String?, icon: CircledInitialsIcon, profilePicture: UIImage?, showGreenShield: Bool, showRedShield: Bool) {
                self.text = text
                self.icon = icon
                self.profilePicture = profilePicture
                self.showGreenShield = showGreenShield
                self.showRedShield = showRedShield
            }
            
            var initialCircleViewModelContent: InitialCircleView.Model.Content {
                .init(text: text, icon: icon)
            }
            
        }

        let content: Content
        let colors: InitialCircleView.Model.Colors
        let circleDiameter: CGFloat

        public init(content: Content, colors: InitialCircleView.Model.Colors, circleDiameter: CGFloat) {
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

    public init(model: Model) {
        self.model = model
    }

    public var body: some View {
        Group {
            if let profilePicture = model.content.profilePicture {
                Image(uiImage: profilePicture)
                    .resizable()
                    .scaledToFit()
                    .frame(width: model.circleDiameter, height: model.circleDiameter)
                    .clipShape(Circle())
            } else {
                InitialCircleView(model: model.initialCircleViewModel)
                    .frame(width: model.circleDiameter, height: model.circleDiameter)
            }
        }
        .overlay(Image(systemIcon: .checkmarkShieldFill)
                    .font(.system(size: (model.circleDiameter) / 4))
                    .foregroundColor(model.content.showGreenShield ? Color(AppTheme.shared.colorScheme.green) : .clear)
                    .accessibilityHidden(!model.content.showGreenShield),
                 alignment: .topTrailing
        )
        .overlay(Image(systemIcon: .exclamationmarkShieldFill)
            .font(.system(size: (model.circleDiameter) / 2))
            .foregroundColor(model.content.showRedShield ? .red : .clear)
            .accessibilityHidden(!model.content.showRedShield),
                 alignment: .center
        )
        
    }
}
