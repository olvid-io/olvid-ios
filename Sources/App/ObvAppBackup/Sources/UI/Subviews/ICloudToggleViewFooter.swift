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


struct ICloudToggleViewFooter: View {

    var body: some View {
        if let learnMoreURL = LearnMoreURLs.iCloudKeychain.url {
            // We use a Markdown trick so as to show an in-line link instead of a button.
            Text("ICLOUD_KEYCHAIN_INFORMATION_[LEARN_MORE](_)")
                .environment(\.openURL, OpenURLAction { url in
                    UIApplication.shared.open(learnMoreURL, options: [:], completionHandler: nil)
                    return .handled
                })
        }
    }
}
