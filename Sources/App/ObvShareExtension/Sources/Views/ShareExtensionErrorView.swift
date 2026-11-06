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
import ObvSystemIcon
import ObvDesignSystem


/// Error screen shown by the share extension when it cannot proceed and the user must launch or
/// update the main Olvid app. Presented from `ShareExtensionViewController` via a `UIHostingController`.
///
/// Lives in this framework (not the share-extension target) so it can be previewed: Xcode cannot host
/// SwiftUI previews inside a `com.apple.share-services` app extension.
public struct ShareExtensionErrorView: View {

    public enum Reason {
        case shouldUpdateToLatestVersion
        case shouldLaunchTheApp
        case nothingToShare
    }

    let reason: Reason
    let onDismiss: () -> Void

    public init(reason: Reason, onDismiss: @escaping () -> Void) {
        self.reason = reason
        self.onDismiss = onDismiss
    }

    private var title: String {
        switch reason {
        case .shouldUpdateToLatestVersion:
            return String(localizedInThisBundle: "SHARE_EXTENSION_ERROR_UPDATE_TITLE")
        case .shouldLaunchTheApp:
            return String(localizedInThisBundle: "SHARE_EXTENSION_ERROR_LAUNCH_TITLE")
        case .nothingToShare:
            return String(localizedInThisBundle: "SHARE_EXTENSION_ERROR_NOTHING_TO_SHARE_TITLE")
        }
    }

    private var message: String {
        switch reason {
        case .shouldUpdateToLatestVersion:
            return String(localizedInThisBundle: "PLEASE_UPDATE_OLVID_FROM_MAIN_APP")
        case .shouldLaunchTheApp:
            return String(localizedInThisBundle: "PLEASE_LAUNCH_OLVID_FROM_MAIN_APP")
        case .nothingToShare:
            return String(localizedInThisBundle: "SHARE_EXTENSION_ERROR_NOTHING_TO_SHARE_MESSAGE")
        }
    }

    private var systemIcon: SystemIcon {
        switch reason {
        case .shouldUpdateToLatestVersion: return .arrowDownCircle
        case .shouldLaunchTheApp: return .appBadge
        case .nothingToShare: return .exclamationmarkTriangleFill
        }
    }

    public var body: some View {
        VStack {
            Spacer()
            ObvContentUnavailableView(title: title, systemIcon: systemIcon, description: message)
            Spacer()
            Button(action: onDismiss) {
                Text("OK")
                    .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color(AppTheme.shared.colorScheme.olvidLight))
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
    }

}


// MARK: - Previews

#if DEBUG

#Preview("Launch the app") {
    ShareExtensionErrorView(reason: .shouldLaunchTheApp, onDismiss: {})
}

#Preview("Update required") {
    ShareExtensionErrorView(reason: .shouldUpdateToLatestVersion, onDismiss: {})
}

#Preview("Nothing to share") {
    ShareExtensionErrorView(reason: .nothingToShare, onDismiss: {})
}

#endif
