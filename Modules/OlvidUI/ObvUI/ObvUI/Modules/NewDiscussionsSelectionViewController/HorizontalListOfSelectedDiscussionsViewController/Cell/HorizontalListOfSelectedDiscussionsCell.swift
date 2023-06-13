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
  

import CoreData
import Foundation
import ObvUICoreData
import SwiftUI
import UIKit
import UI_CircledInitialsView_CircledInitialsConfiguration

@available(iOS 16.0, *)
extension HorizontalListOfSelectedDiscussionsViewController {
    
    public final class Cell: UICollectionViewCell {
        
        private var viewModel: ViewModel?
        private weak var delegate: HorizontalListOfSelectedDiscussionsViewControllerDelegate?
        
        func configure(viewModel: ViewModel, delegate: HorizontalListOfSelectedDiscussionsViewControllerDelegate?) {
            self.viewModel = viewModel
            self.delegate = delegate
            setNeedsUpdateConfiguration()
        }
        
        public override func updateConfiguration(using state: UICellConfigurationState) {
            guard let viewModel else { assertionFailure(); return }
            
            contentConfiguration = UIHostingConfiguration {
                HorizontalListOfSelectedDiscussionsView(viewModel: viewModel, delegate: delegate)
            }.updated(for: state)
            
            var background = UIBackgroundConfiguration.listPlainCell()
            background.backgroundColor = .systemFill
            background.cornerRadius = 12.0
            backgroundConfiguration = background
        }
    }
    
}


@available(iOS 16.0, *)
private struct HorizontalListOfSelectedDiscussionsView: View {
    
    let viewModel: HorizontalListOfSelectedDiscussionsViewController.Cell.ViewModel
    weak var delegate: HorizontalListOfSelectedDiscussionsViewControllerDelegate?

    var body: some View {
        HStack(alignment: .top) {
            if let config = viewModel.circledInitialsConfig {
                CircledInitialsView(configuration: config, size: .medium, style: viewModel.style)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.title)
                            .foregroundColor(Color(AppTheme.shared.colorScheme.label))
                            .font(.caption)
                            .lineLimit(2)
                        if let subtitle = viewModel.subtitle {
                            Text(subtitle)
                                .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                                .font(.caption2)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                }
                if let subtitleLineTwo = viewModel.subtitleLineTwo {
                    Text(subtitleLineTwo)
                        .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                        .font(.caption2)
                        .lineLimit(2)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button(action: {
                delegate?.userWantsToDeselectItem(with: viewModel.discussionObjectID)
            }, label: {
                Image(systemIcon: .xmarkCircle)
                    .resizable()
                    .frame(width: 16, height: 16)
                    .foregroundColor(Color(AppTheme.shared.colorScheme.label))
                    .padding(8)
                    .clipShape(Circle())
            })
            .offset(x: 8, y: -8)
        }
    }
    
}




@available(iOS 16.0, *)
struct HorizontalListOfSelectedDiscussionsView_Previews: PreviewProvider {
    
    static let viewModel = HorizontalListOfSelectedDiscussionsViewController.Cell.ViewModel(
        discussionObjectID: TypeSafeManagedObjectID(objectID: NSManagedObjectID()),
        title: "A very long title that should spane the whole cell",
        subtitle: "Subtitle",
        subtitleLineTwo: "Subtitle line 2",
        circledInitialsConfig: nil,
        style: .hue)
    
    static var previews: some View {
        HorizontalListOfSelectedDiscussionsView(viewModel: Self.viewModel)
            .previewLayout(.sizeThatFits)
    }
}
