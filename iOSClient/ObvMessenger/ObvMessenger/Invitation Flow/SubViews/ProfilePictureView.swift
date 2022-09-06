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
  

import SwiftUI

struct ProfilePictureView: View {

    let profilePicture: UIImage?
    let circleBackgroundColor: UIColor?
    let circleTextColor: UIColor?
    let circledTextView: Text?
    let systemImage: CircledInitialsIcon
    let customCircleDiameter: CGFloat?
    let showGreenShield: Bool
    let showRedShield: Bool

    init(profilePicture: UIImage?,
         circleBackgroundColor: UIColor?,
         circleTextColor: UIColor?,
         circledTextView: Text?,
         systemImage: CircledInitialsIcon,
         showGreenShield: Bool,
         showRedShield: Bool,
         customCircleDiameter: CGFloat? = ProfilePictureView.circleDiameter) {
        self.profilePicture = profilePicture
        self.circleBackgroundColor = circleBackgroundColor
        self.circleTextColor = circleTextColor
        self.circledTextView = circledTextView
        self.systemImage = systemImage
        self.showGreenShield = showGreenShield
        self.showRedShield = showRedShield
        self.customCircleDiameter = customCircleDiameter
    }

    static let circleDiameter: CGFloat = 60.0

    var body : some View {
        Group {
            if let profilePicture = profilePicture {
                Image(uiImage: profilePicture)
                    .resizable()
                    .scaledToFit()
                    .frame(width: customCircleDiameter ?? ProfilePictureView.circleDiameter, height: customCircleDiameter ?? ProfilePictureView.circleDiameter)
                    .clipShape(Circle())
            } else {
                InitialCircleView(circledTextView: circledTextView,
                                  systemImage: systemImage,
                                  circleBackgroundColor: circleBackgroundColor,
                                  circleTextColor: circleTextColor,
                                  circleDiameter: customCircleDiameter ?? ProfilePictureView.circleDiameter)
            }
        }
        .overlay(Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: (customCircleDiameter ?? ProfilePictureView.circleDiameter) / 4))
                    .foregroundColor(showGreenShield ? Color(AppTheme.shared.colorScheme.green) : .clear),
                 alignment: .topTrailing
        )
        .overlay(Image(systemIcon: .exclamationmarkShieldFill)
                    .font(.system(size: (customCircleDiameter ?? ProfilePictureView.circleDiameter) / 2))
                    .foregroundColor(showRedShield ? .red : .clear),
                 alignment: .center
        )

    }
}
