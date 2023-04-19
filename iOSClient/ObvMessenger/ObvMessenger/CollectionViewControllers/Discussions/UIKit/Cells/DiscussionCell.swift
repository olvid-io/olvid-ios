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
import os.log
import SwiftUI
import UIKit


private let kCircleSideLength = CGFloat(60.0)
private let kCircleToTextAreaPadding = CGFloat(8.0)
private let kRightDetailPlaceholderSideLength = CGFloat(30.0)

@available(iOS 16.0, *)
final class DiscussionCell: UICollectionViewListCell {
    
    struct Content: Equatable {
        let numberOfNewReceivedMessages: Int
        let circledInitialsConfig: CircledInitialsConfiguration?
        let shouldMuteNotifications: Bool
        let title: String
        let subtitle: String
        let isSubtitleInItalics: Bool
        let timestampOfLastMessage: String
    }
    
    fileprivate var content: Content?
    fileprivate var selectionStyle: UITableViewCell.SelectionStyle = .default
    
    func configure(content: Content, selectionStyle: UITableViewCell.SelectionStyle) {
        self.content = content
        self.selectionStyle = selectionStyle
        setNeedsUpdateConfiguration()
    }
    
    override func updateConfiguration(using state: UICellConfigurationState) {
        guard let content else { assertionFailure(); contentConfiguration = defaultContentConfiguration(); return }

        contentConfiguration = UIHostingConfiguration { SwiftUIDiscussionsCellContentView(content: content) }.updated(for: state)
        
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
        
        separatorLayoutGuide.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor, constant: kCircleSideLength + kCircleToTextAreaPadding).isActive = true
    }
}

// MARK: - SwiftUIDiscussionsCellContentView
@available(iOS 16.0, *)
struct SwiftUIDiscussionsCellContentView: View {

    let content: DiscussionCell.Content
    
    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: Self.self))
        
    var body: some View {
        HStack(alignment: .top, spacing: kCircleToTextAreaPadding) {
            if let config = content.circledInitialsConfig {
                SwiftUINewCircledInitialsView(configuration: config)
                    .frame(width: kCircleSideLength, height: kCircleSideLength)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(content.title)
                        .foregroundColor(Color(AppTheme.shared.colorScheme.label))
                        .lineLimit(1)
                        .font(.system(.headline, design: .rounded))
                    if content.circledInitialsConfig?.showGreenShield == true {
                        Image(systemIcon: .checkmarkShieldFill)
                            .foregroundColor(Color(.systemGreen))
                    }
                    if content.circledInitialsConfig?.showRedShield == true {
                        Image(systemIcon: .exclamationmarkShieldFill)
                            .foregroundColor(Color(.systemRed))
                    }
                    Spacer()
                    Text(content.timestampOfLastMessage)
                        .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                        .lineLimit(1)
                        .font(.caption)
                }
                HStack(alignment: .top) {
                    Text(content.subtitle)
                        .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                        .lineLimit(2)
                        .font(.subheadline)
                        .italic(content.isSubtitleInItalics)
                    Spacer()
                    VStack {
                        if content.shouldMuteNotifications {
                            Image(systemIcon: ObvMessengerConstants.muteIcon)
                                .frame(width: kRightDetailPlaceholderSideLength,
                                       height: kRightDetailPlaceholderSideLength)
                                .foregroundColor(.gray)
                        } else if content.numberOfNewReceivedMessages > 0 {
                            Text(String(content.numberOfNewReceivedMessages))
                                .foregroundColor(.white)
                                .font(.caption)
                                .lineLimit(1)
                                .padding(.horizontal, 8.0)
                                .padding(.vertical, 4.0)
                                .background(Capsule().foregroundColor(Color(uiColor: AppTheme.appleBadgeRedColor)))
                        }
                    }
                }
            }
        }
    }
}
