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
import Foundation

struct MultilineSubmitViewModifier: ViewModifier {
    
    init(
        text: Binding<String>,
        submitLabel: SubmitLabel,
        onSubmit: @escaping () -> Void
    ) {
        self._text = text
        self.submitLabel = submitLabel
        self.onSubmit = onSubmit
    }
    
    @Binding private var text: String

    private let submitLabel: SubmitLabel
    private let onSubmit: () -> Void
    
    @FocusState private var isFocused: Bool
    
    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .submitLabel(submitLabel)
            .onChange(of: text) { newValue in
                guard isFocused else { return }
                guard newValue.contains("\n") else { return }
                isFocused = false
                text = newValue.replacingOccurrences(of: "\n", with: "")
                onSubmit()
            }
    }
}

public extension View {
    
    func onMultilineSubmit(in text: Binding<String>,
                           submitLabel: SubmitLabel = .done,
                           action: @escaping () -> Void) -> some View {
        self.modifier(
            MultilineSubmitViewModifier(text: text,
                                        submitLabel: submitLabel,
                                        onSubmit: action)
        )
    }
    
    func multilineSubmit(for text: Binding<String>,
                         submitLabel: SubmitLabel = .done) -> some View {
            self.modifier(
                MultilineSubmitViewModifier(text: text,
                                            submitLabel: submitLabel,
                                            onSubmit: {})
            )
        }
}
