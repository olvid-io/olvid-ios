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

import SwiftUI
import ObvUI
import ObvDesignSystem


@available(iOS 16.0, *)
private let kCircledInitialsViewSize = CircledInitialsView.Size.medium
private let kCircleToTextAreaPadding = CGFloat(8.0)
private let kRightDetailPlaceholderSideLength = CGFloat(30.0)


@available(iOS 16.0, *)
extension NewDiscussionsViewController {
    
    final class DiscussionCell: UICollectionViewListCell {

        private var viewModel: ViewModel?

        func configure(viewModel: ViewModel) {
            self.viewModel = viewModel
            setNeedsUpdateConfiguration()
        }

        
        override func updateConfiguration(using state: UICellConfigurationState) {
            guard let viewModel else { assertionFailure(); contentConfiguration = defaultContentConfiguration(); return; }
            backgroundConfiguration = CustomBackgroundConfiguration.configuration(for: state, viewModel: viewModel)
            contentConfiguration = UIHostingConfiguration { DiscussionsListCellContentView(viewModel: viewModel, state: state) }
            separatorLayoutGuide.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor, constant: kCircledInitialsViewSize.sideLength + kCircleToTextAreaPadding).isActive = true
        }
        

        private struct CustomBackgroundConfiguration {
            static func configuration(for state: UICellConfigurationState, viewModel: NewDiscussionsViewController.DiscussionCell.ViewModel) -> UIBackgroundConfiguration {

                var background = UIBackgroundConfiguration.clear()
                
                if UIDevice.current.userInterfaceIdiom == .phone {
                    
                    // iPhone
                    
                    if state.isHighlighted || state.isSelected {
                        
                        background.backgroundColor = .systemFill
                        
                        if state.isHighlighted {
                            // Reduce the alpha of the tint color to 30% when highlighted
                            background.backgroundColorTransformer = .init { $0.withAlphaComponent(0.3) }
                        }
                        
                    } else if viewModel.isPinned {
                        
                        background.backgroundColor = .secondarySystemBackground
                        
                    }

                    
                } else {

                    // iPad and Mac
                    
                    if state.isHighlighted || state.isSelected {
                        
                        if !state.isEditing {
                            
                            background.cornerRadius = 16
                            background.backgroundInsets = .init(top: 0, leading: 8, bottom: 0, trailing: 8)
                            
                            // Set nil to use the inherited tint color of the cell when highlighted or selected
                            background.backgroundColor = nil
                            
                            if state.isHighlighted {
                                // Reduce the alpha of the tint color to 30% when highlighted
                                background.backgroundColorTransformer = .init { $0.withAlphaComponent(0.3) }
                            }
                            
                        }
                        
                    }

                }
                                
                return background
                
            }
        }

    }
    
}


// MARK: - SwiftUIDiscussionsCellContentView

@available(iOS 16.0, *)
fileprivate struct DiscussionsListCellContentView: View {

    let viewModel: NewDiscussionsViewController.DiscussionCell.ViewModel
    var state: UICellConfigurationState

    private var titleColor: Color {
        let color: UIColor = .label
        if state.isSelected && UIDevice.current.userInterfaceIdiom != .phone {
            return Color(color.resolvedColor(with: .init(userInterfaceStyle: .dark)))
        } else {
            return Color(color)
        }
    }

    private var subtitleColor: Color {
        let color: UIColor = .secondaryLabel
        if state.isSelected && UIDevice.current.userInterfaceIdiom != .phone {
            return Color(color.resolvedColor(with: .init(userInterfaceStyle: .dark)))
        } else {
            return Color(color)
        }
    }

    private var timestampColor: Color {
        let color: UIColor = .secondaryLabel
        if state.isSelected && UIDevice.current.userInterfaceIdiom != .phone {
            return Color(color.resolvedColor(with: .init(userInterfaceStyle: .dark)))
        } else {
            return Color(color)
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: kCircleToTextAreaPadding) {
            if let config = viewModel.circledInitialsConfig {
                CircledInitialsView(configuration: config, size: kCircledInitialsViewSize, style: viewModel.style)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(viewModel.title)
                        .foregroundColor(titleColor)
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
                        .foregroundColor(timestampColor)
                        .lineLimit(1)
                        .font(.caption)
                }
                HStack(alignment: .top) {
                    if let statusIcon = viewModel.statusIcon {
                        ( // Best way to integrate SF Symbol at the beginning of a text even if it is multi-lined because it results in a single Text
                            Text(Image(symbolIcon: statusIcon)).font(.caption).baselineOffset(1)
                            +
                            (Text(" ") + Text(viewModel.subtitle))
                        )
                        .foregroundColor(subtitleColor)
                        .lineLimit(2)
                    } else {
                        Text(viewModel.subtitle)
                            .foregroundColor(subtitleColor)
                            .lineLimit(2)
                    }
                    Spacer()
                    HStack(alignment: .center, spacing: 0) {
                        
                        if viewModel.aNewReceivedMessageDoesMentionOwnedIdentity {
                            Image(systemIcon: AppTheme.shared.icons.mentionnedIcon)
                                .frame(width: kRightDetailPlaceholderSideLength,
                                       height: kRightDetailPlaceholderSideLength)
                                .foregroundColor(Color(UIColor.systemRed))
                        }
                        
                        if viewModel.shouldMuteNotifications {
                            Image(systemIcon: AppTheme.shared.icons.muteIcon)
                                .frame(width: kRightDetailPlaceholderSideLength,
                                       height: kRightDetailPlaceholderSideLength)
                                .foregroundColor(Color(UIColor.systemGray))
                        } else if viewModel.isArchived {
                            Image(systemIcon: AppTheme.shared.icons.archivebox)
                                .frame(width: kRightDetailPlaceholderSideLength,
                                       height: kRightDetailPlaceholderSideLength)
                                .foregroundColor(Color(UIColor.systemGray))
                        } else if viewModel.numberOfNewReceivedMessages > 0 {
                            Text(String(viewModel.numberOfNewReceivedMessages))
                                .foregroundColor(.white)
                                .font(.caption)
                                .lineLimit(1)
                                .padding(.horizontal, 8.0)
                                .padding(.vertical, 4.0)
                                .background(Capsule().foregroundColor(Color(uiColor: AppTheme.appleBadgeRedColor)))
                        } else if viewModel.isPinned {
                            Image(systemIcon: .pinFill)
                                .font(.footnote)
                                .lineLimit(1)
                                .padding(.horizontal, 4.0)
                                .padding(.vertical, 4.0)
                                .rotationEffect(.degrees(30), anchor: .center)
                                .foregroundColor(Color(.systemYellow))
                        }

                    }.frame(height: kRightDetailPlaceholderSideLength)

                }
            }
        }

    }
}
