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
import SwiftUI
import UIKit

@available(iOS 16.0, *)
private let kCircledInitialsViewSize = CircledInitialsView.Size.small
private let kCircleToTextAreaPadding = CGFloat(8.0)
private let kRightDetailPlaceholderSideLength = CGFloat(30.0)

@available(iOS 16.0, *)
public final class DiscussionsListShortCell: UICollectionViewListCell {

    private var viewModel: DiscussionsListShortCellViewModel?
    private var selectionStyle: UITableViewCell.SelectionStyle = .default
    
    func configure(viewModel: DiscussionsListShortCellViewModel, selectionStyle: UITableViewCell.SelectionStyle) {
        self.viewModel = viewModel
        self.selectionStyle = selectionStyle
        setNeedsUpdateConfiguration()
    }
    
    public override func updateConfiguration(using state: UICellConfigurationState) {
        guard let viewModel else { assertionFailure(); contentConfiguration = defaultContentConfiguration(); return; }
        contentConfiguration = UIHostingConfiguration { DiscussionsListShortCellContentView(viewModel: viewModel) }.updated(for: state)
        
        if selectionStyle == .none {
            // swiftlint:disable commented_code
            // Disabling selection for individual list cells.
            // https://developer.apple.com/forums/thread/658420?answerId=629926022#629926022
            // swiftlint:enable commented_code
            automaticallyUpdatesBackgroundConfiguration = false
            var modifiedState = state
            modifiedState.isHighlighted = false
            modifiedState.isSelected = false
            backgroundConfiguration = backgroundConfiguration?.updated(for: modifiedState)
        }
        
        separatorLayoutGuide.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor, constant: kCircledInitialsViewSize.sideLength + kCircleToTextAreaPadding).isActive = true
        accessories = [.multiselect(displayed: .whenEditing)]
    }
}


// MARK: - SwiftUIDiscussionsCellContentView
@available(iOS 16.0, *)
fileprivate struct DiscussionsListShortCellContentView: View {

    let viewModel: DiscussionsListShortCellViewModel
    
    var body: some View {
        HStack(alignment: .top, spacing: kCircleToTextAreaPadding) {
            if let config = viewModel.circledInitialsConfig {
                CircledInitialsView(configuration: config, size: kCircledInitialsViewSize)
            }
            VStack(alignment: .center, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(viewModel.title)
                        .foregroundColor(Color(AppTheme.shared.colorScheme.label))
                        .lineLimit(1)
                        .font(.system(.callout, design: .rounded))
                        .frame(maxHeight: .infinity, alignment: .center)
                    if viewModel.circledInitialsConfig?.showGreenShield == true {
                        Image(systemIcon: .checkmarkShieldFill)
                            .foregroundColor(Color(.systemGreen))
                    }
                    if viewModel.circledInitialsConfig?.showRedShield == true {
                        Image(systemIcon: .exclamationmarkShieldFill)
                            .foregroundColor(Color(.systemRed))
                    }
                }
            }
        }
    }
}
