/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import ObvUI

@available(iOS 16.0, *)
private let kCircledInitialsViewSize = CircledInitialsView.Size.medium
private let kCircleToTextAreaPadding = CGFloat(8.0)
private let kRightDetailPlaceholderSideLength = CGFloat(30.0)


@available(iOS 16.0, *)
extension NewDiscussionsViewController {
    
    final class Cell: UICollectionViewListCell {

        private var viewModel: ViewModel?
        private var selectionStyle: UITableViewCell.SelectionStyle = .default

        func configure(viewModel: ViewModel, selectionStyle: UITableViewCell.SelectionStyle) {
            self.viewModel = viewModel
            self.selectionStyle = selectionStyle
            setNeedsUpdateConfiguration()
        }

        
        override func updateConfiguration(using state: UICellConfigurationState) {
            guard let viewModel else { assertionFailure(); contentConfiguration = defaultContentConfiguration(); return; }
            contentConfiguration = UIHostingConfiguration { DiscussionsListCellContentView(viewModel: viewModel, state: state) }.updated(for: state)
            
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
                if viewModel.isPinned {
                    backgroundConfiguration?.backgroundColor = .secondarySystemBackground
                } else {
                    backgroundConfiguration?.backgroundColor = .systemBackground
                }
            } else {
                if state.isHighlighted || state.isSelected {
                    backgroundConfiguration?.backgroundColor = .systemFill
                } else if viewModel.isPinned {
                    backgroundConfiguration?.backgroundColor = .secondarySystemBackground
                } else {
                    backgroundConfiguration?.backgroundColor = .systemBackground
                }
            }
            
            separatorLayoutGuide.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor, constant: kCircledInitialsViewSize.sideLength + kCircleToTextAreaPadding).isActive = true
            
        }

    }
    
}


// MARK: - SwiftUIDiscussionsCellContentView
@available(iOS 16.0, *)
fileprivate struct DiscussionsListCellContentView: View {

    let viewModel: NewDiscussionsViewController.Cell.ViewModel
    var state: UICellConfigurationState

    var body: some View {
        HStack(alignment: .top, spacing: kCircleToTextAreaPadding) {
            if let config = viewModel.circledInitialsConfig {
                CircledInitialsView(configuration: config, size: kCircledInitialsViewSize, style: viewModel.style)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(viewModel.title)
                        .foregroundColor(Color(AppTheme.shared.colorScheme.label))
                        .lineLimit(1)
                        .font(.system(.headline, design: .rounded))
                    if viewModel.circledInitialsConfig?.showGreenShield == true {
                        Image(systemIcon: .checkmarkShieldFill)
                            .foregroundColor(Color(.systemGreen))
                    }
                    if viewModel.circledInitialsConfig?.showRedShield == true {
                        Image(systemIcon: .exclamationmarkShieldFill)
                            .foregroundColor(Color(.systemRed))
                    }
                    Spacer()
                    Text(viewModel.timestampOfLastMessage)
                        .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                        .lineLimit(1)
                        .font(.caption)
                }
                HStack(alignment: .top) {
                    Text(viewModel.subtitle)
                        .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                        .lineLimit(2)
                        .font(.subheadline)
                        .italic(viewModel.isSubtitleInItalics)
                    Spacer()
                    HStack(alignment: .center, spacing: 0) {
                        if viewModel.aNewReceivedMessageDoesMentionOwnedIdentity {
                            Image(systemIcon: AppTheme.shared.icons.mentionnedIcon)
                                .frame(width: kRightDetailPlaceholderSideLength,
                                       height: kRightDetailPlaceholderSideLength)
                                .foregroundColor(.red)
                        }
                        if viewModel.shouldMuteNotifications {
                            Image(systemIcon: AppTheme.shared.icons.muteIcon)
                                .frame(width: kRightDetailPlaceholderSideLength,
                                       height: kRightDetailPlaceholderSideLength)
                                .foregroundColor(.gray)
                        } else if viewModel.isArchived {
                            Image(systemIcon: AppTheme.shared.icons.archivebox)
                                .frame(width: kRightDetailPlaceholderSideLength,
                                       height: kRightDetailPlaceholderSideLength)
                                .foregroundColor(.gray)
                        } else if viewModel.numberOfNewReceivedMessages > 0 {
                            Text(String(viewModel.numberOfNewReceivedMessages))
                                .foregroundColor(.white)
                                .font(.caption)
                                .lineLimit(1)
                                .padding(.horizontal, 8.0)
                                .padding(.vertical, 4.0)
                                .background(Capsule().foregroundColor(Color(uiColor: AppTheme.appleBadgeRedColor)))
                        }
                    }.frame(height: kRightDetailPlaceholderSideLength)

                }
            }
        }.overlay(alignment: .leading) {
            Image(systemIcon: AppTheme.shared.icons.pinIcon)
                .font(.system(size: 14))
                .foregroundColor(Color(UIColor.tertiaryLabel))
                .offset(x: -18)
                .opacity(viewModel.isPinned && !state.isEditing ? 1.0 : 0.0)
        }

    }
}
