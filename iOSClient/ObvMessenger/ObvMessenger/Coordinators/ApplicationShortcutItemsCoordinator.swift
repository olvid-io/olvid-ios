/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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

final class ApplicationShortcutItemsCoordinator {
    
    private var observationTokens = [NSObjectProtocol]()
    
    init() {
        observationTokens.append(contentsOf: [
            ObvMessengerInternalNotification.observeAppStateChanged(queue: .main) { [weak self] previousState, currentState in
                guard currentState.iOSAppState == .notActive else { return }
                self?.registerDynamicQuickActionsToDisplayOnTheHomeScreen()
            },
        ])
    }
    

    private func registerDynamicQuickActionsToDisplayOnTheHomeScreen() {
        assert(Thread.isMainThread)
        let scanQRCodeShortcutItem = UIApplicationShortcutItem(with: .scanQRCode)
        UIApplication.shared.shortcutItems = [scanQRCodeShortcutItem]
    }
    
}


// MARK: - ApplicationShortcut

enum ApplicationShortcut: CustomStringConvertible, LosslessStringConvertible {
    
    case scanQRCode

    var description: String {
        let prefix = "UIApplicationShortcutItem"
        let suffix: String
        switch self {
        case .scanQRCode:
            suffix = "scanQRCode"
        }
        return [prefix, suffix].joined(separator: ".")
    }

    init?(_ description: String) {
        let elements = description.split(separator: ".")
        guard elements.count == 2 else { assertionFailure(); return nil }
        guard elements[0] == "UIApplicationShortcutItem" else { assertionFailure(); return nil }
        switch elements[1] {
        case "scanQRCode":
            self = Self.scanQRCode
        default:
            assertionFailure()
            return nil
        }
    }

    var localizedTitle: String {
        switch self {
        case .scanQRCode:
            return Strings.scanQRCode
        }
    }
    
    var localizedSubtitle: String? {
        switch self {
        case .scanQRCode:
            return nil
        }
    }
    
    var icon: UIApplicationShortcutIcon? {
        switch self {
        case .scanQRCode:
            if #available(iOS 13, *) {
                return UIApplicationShortcutIcon(systemImageName: "qrcode.viewfinder")
            } else {
                return nil
            }
        }
    }
    
    var userInfo: [String: NSSecureCoding]? {
        switch self {
        case .scanQRCode:
            return nil
        }
    }
    
    private struct Strings {
        static let scanQRCode = NSLocalizedString("Scan QR code", comment: "")
    }
}

extension UIApplicationShortcutItem {
    
    convenience init(with shortcut: ApplicationShortcut) {
        self.init(type: shortcut.description,
                  localizedTitle: shortcut.localizedTitle,
                  localizedSubtitle: shortcut.localizedSubtitle,
                  icon: shortcut.icon,
                  userInfo: shortcut.userInfo)
    }
    
}
