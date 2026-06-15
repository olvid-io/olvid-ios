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
import SwiftUIIntrospect



public enum ObvTextAutocorrectionType: Int, Sendable {
    case `default` = 0
    case no = 1
    case yes = 2
    #if canImport(UIKit)
    var uiTextAutocorrectionType: UITextAutocorrectionType {
        switch self {
        case .default: return .default
        case .no: return .no
        case .yes: return .yes
        }
    }
    #endif // canImport(UIKit)
}


public enum ObvSpellCheckingType : Int, Sendable {
    case `default` = 0
    case no = 1
    case yes = 2
    #if canImport(UIKit)
    var uiTextSpellCheckingType: UITextSpellCheckingType {
        switch self {
        case .default: return .default
        case .no: return .no
        case .yes: return .yes
        }
    }
    #endif // canImport(UIKit)
}


extension TextEditor {
    
    @MainActor
    public func autocorrectionObv(autocorrection: ObvTextAutocorrectionType = .default, spellChecking: ObvSpellCheckingType = .default) -> some View {
        #if canImport(UIKit)
        return self.introspect(.textEditor, on: .iOS(.v16, .v17, .v18, .v26), customize: { uiTextView in
            uiTextView.autocorrectionType = autocorrection.uiTextAutocorrectionType
            uiTextView.spellCheckingType = spellChecking.uiTextSpellCheckingType
        })
        #endif // canImport(UIKit)
    }
    
}
