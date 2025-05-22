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
  

import Foundation
import SwiftUI
import UIKit
import ObvDesignSystem
import ObvAppCoreConstants


@available(iOS 16.0, *)
extension HorizontalListOfSelectedDiscussionsViewController {
    
    final class PlaceholderCell: UICollectionViewCell {
        
        func configure() {
            setNeedsUpdateConfiguration()
        }
        
        override func updateConfiguration(using state: UICellConfigurationState) {
            contentConfiguration = UIHostingConfiguration {
                VStack(alignment: .center) {
                    Text("DISCUSSIONS_LIST_SELECTION_PLACEHOLDER_CELL")
                        .foregroundStyle(.primary)
                        .font(.headline)
                    if ObvAppCoreConstants.targetEnvironmentIsMacCatalyst {
                        Text("HOLD_DOWN_CMD_TO_SELECT_MULTIPLE_DISCUSSIONS")
                            .foregroundStyle(.primary)
                            .font(.subheadline)
                    }
                }
            }.updated(for: state)
            
            var background = UIBackgroundConfiguration.listPlainCell()
            background.backgroundColor = .systemFill
            background.cornerRadius = 12.0
            backgroundConfiguration = background
        }
    }

    
}
