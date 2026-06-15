/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import ObvTypes
import ObvDesignSystem


/// View showing details about one owned identity.
///
/// We use a internal model to make it possible to have SwiftUI previews
struct OwnedIdentityItemView: View {
    
    let currentOwnedCryptoId: ObvCryptoId
    let viewModel: OwnedIdentityChooserViewModel.OwnedIdentity
    let dataSource: OwnedIdentityChooserViewDataSource
    let avatarViewDataSource: ObvAvatarViewDataSource
    let configuration: OwnedIdentityChooserInnerViewConfiguration
    @Binding var ownedCryptoIdTappedByUser: ObvCryptoId?

    private static let kCircleToTextAreaPadding = CGFloat(8.0)
    private static let animationDurationWhenSwitchingIdentity: Double = 0.3 // In secconds
    
    private var showCheckmark: Bool {
        if let ownedCryptoIdTappedByUser {
            return viewModel.ownedCryptoId == ownedCryptoIdTappedByUser
        } else {
            return viewModel.ownedCryptoId == self.currentOwnedCryptoId
        }
    }
    
    
    private func onTap() {
        switch configuration.mode {
        case .changeCurrentProfile:
            guard ownedCryptoIdTappedByUser == nil else { return } // Prevents double tapping
        case .selectProfile:
            break // Let the user change the selected profile
        }
        withAnimation {
            ownedCryptoIdTappedByUser = viewModel.ownedCryptoId
        }
    }
    
    var body: some View {
        Group {
            HStack(alignment: .center, spacing: Self.kCircleToTextAreaPadding) {
                ObvAvatarView(model: viewModel.avatarViewModel, style: .circle, size: .normal, dataSource: avatarViewDataSource)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(viewModel.title)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .font(.system(.headline, design: .rounded))
                        if viewModel.showGreenShield {
                            Image(systemIcon: .checkmarkShieldFill)
                                .foregroundColor(.green)
                        }
                        if viewModel.showRedShield {
                            Image(systemIcon: .exclamationmarkShieldFill)
                                .foregroundColor(.red)
                        }
                    }
                    if !viewModel.subtitle.isEmpty {
                        Text(viewModel.subtitle)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .font(.subheadline)
                    }
                }
                Spacer()
                if viewModel.showHiddenProfileIcon {
                    Image(systemIcon: .eyeSlash)
                        .imageScale(.small)
                        .foregroundColor(.secondary)
                }
                switch configuration.mode {
                case .changeCurrentProfile:
                    if showCheckmark {
                        Image(systemIcon: .checkmarkCircleFill)
                            .imageScale(.large)
                            .foregroundColor(.blue)
                    } else if viewModel.totalBadgeCount > 0 {
                        ObvBadgeNumberOfNewMessages(numberOfNewReceivedMessages: viewModel.totalBadgeCount)
                    }
                case .selectProfile:
                    ObvRadioButtonView(value: self.viewModel.ownedCryptoId, selectedValue: $ownedCryptoIdTappedByUser)
                        .padding(.trailing, 8)
                }
            }
            .contentShape(Rectangle()) // This makes it possible to have an "on tap" gesture that also works when the Spacer is tapped
        }
        .onTapGesture(perform: onTap) // We used to have a button, but it suffered interferences with the drag gesture
    }
    
}
