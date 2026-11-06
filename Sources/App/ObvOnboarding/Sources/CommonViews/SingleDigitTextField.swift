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


protocol SingleDigitTextFielddActions {
    func singleTextFieldDidChangeAtIndex(_ index: Int)
}



struct SingleDigitTextField: View {
    
    private let key: LocalizedStringKey
    private let text: Binding<String>
    private let actions: SingleDigitTextFielddActions? // Not needed when the this text field stays disabled
    private let model: Model? // Not needed when the this text field stays disabled
    
    @Environment(\.isEnabled) var isEnabled
    
    struct Model {
        let index: Int // Index of this text field in the BackupKeyTextField
    }
    
    private static let maxLength = 1
    
    /// Both `actions` and `model` must be set, unless this text field is disabled by default (just used to show some existing value).
    init(_ key: LocalizedStringKey, text: Binding<String>, actions: SingleDigitTextFielddActions?, model: Model?) {
        self.key = key
        self.text = text
        self.actions = actions
        self.model = model
    }
    
    private let myFont = Font
        .system(size: 18)
        .monospaced()
        .weight(.bold)

    var body: some View {
        TextField(key, text: text)
            .keyboardType(.decimalPad)
            .textContentType(.none)
            .multilineTextAlignment(.center)
            .font(myFont)
            .padding(.vertical, 10)
            .overlay(content: {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(UIColor.systemGray2), lineWidth: 1)
                    .padding(.horizontal, 1)
            }).background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(UIColor.systemGray5))
                    .padding(.horizontal, 1)
                    .opacity(isEnabled ? 0 : 1)
            )
            .onChange(of: text.wrappedValue) { newValue in
                guard let actions, let model else { return }
                // We limit the string length to maxLength characters. Writing the sanitized value back
                // re-enters this closure with the clean value, which is the one we report.
                let sanitized = String(newValue.removingAllCharactersNotInCharacterSet(.decimalDigits).prefix(Self.maxLength))
                guard newValue == sanitized else {
                    text.wrappedValue = sanitized
                    return
                }
                actions.singleTextFieldDidChangeAtIndex(model.index)
            }
    }
    
}


// MARK: - Private helpers

fileprivate extension String {
    func removingAllCharactersNotInCharacterSet(_ characterSet: CharacterSet) -> String {
        return String(self
            .trimmingWhitespacesAndNewlines()
            .unicodeScalars
            .filter({
                characterSet.contains($0)
            }))
    }
}
