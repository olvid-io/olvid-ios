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

import UIKit
import Platform_Base

@available(iOSApplicationExtension 14.0, *)
internal extension TextInputShortcutsResultView {
    final class _SuggestionCell: UICollectionViewListCell {
        /// When configuring me for the first time, please specify the template background configuration, with a `visualEffect`
        internal var customDefaultBackgroundConfiguration: UIBackgroundConfiguration?

        override func updateConfiguration(using state: UICellConfigurationState) {
            super.updateConfiguration(using: state)

            assert(customDefaultBackgroundConfiguration != nil, "please specify the default background configuration")

            if state.isSelected ||
                state.isHighlighted ||
                state.isFocused {
                backgroundConfiguration = customDefaultBackgroundConfiguration
            } else {
                backgroundConfiguration = customDefaultBackgroundConfiguration..{
                    $0?.backgroundColor = .clear
                }
            }
        }
    }
}
