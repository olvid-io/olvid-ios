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
import ObvSystemIcon
import ObvTypes


@MainActor
public protocol PersonalNoteEditorViewActions {
    func userWantsToUpdatePersonalNote(_ view: PersonalNoteEditorView, with newText: String?, about: PersonalNoteEditorView.Model.About) async throws
}

@MainActor
public protocol PersonalNoteEditorViewNavigation {
    func userWantsToDismissPersonalNoteEditorView(_ view: PersonalNoteEditorView)
}

public struct PersonalNoteEditorView: View {
    
    let model: Model
    let actions: any PersonalNoteEditorViewActions
    let navigation: any PersonalNoteEditorViewNavigation
    
    public init(model: Model, actions: PersonalNoteEditorViewActions, navigation: any PersonalNoteEditorViewNavigation) {
        self.model = model
        self.actions = actions
        self.navigation = navigation
    }
    
    public struct Model {
        let about: About
        let initialText: String?
        
        public init(initialText: String?, about: About) {
            self.initialText = initialText
            self.about = about
        }
        
        public enum About {
            case contact(ObvContactIdentifier)
            case groupV1(ObvGroupV1Identifier)
            case groupV2(ObvGroupV2Identifier)
        }
        
    }
    
    @State private var text = ""
    @State private var isOkButtonDisabled = true
    @State private var isShowingPlaceHolderText = false
    @FocusState private var isFocused: Bool
    
    private func cancel() {
        navigation.userWantsToDismissPersonalNoteEditorView(self)
    }
    
    private func setInitialTextValue() {
        if let initialText = model.initialText, !initialText.isEmpty {
            self.text = model.initialText ?? ""
        } else {
            self.isShowingPlaceHolderText = true
            self.text = String(localizedInThisBundle: "TYPE_PERSONAL_NOTE_HERE")
        }
    }
    
    private func ok() {
        let newText = self.text
        Task {
            do {
                try await actions.userWantsToUpdatePersonalNote(self, with: newText, about: model.about)
                navigation.userWantsToDismissPersonalNoteEditorView(self)
            } catch {
                assertionFailure()
            }
        }
    }
    
    private func textDidChange(_ newText: String) {
        isOkButtonDisabled = text == (model.initialText ?? "") || isShowingPlaceHolderText
    }
    
    private func textEditorFocusChanged(isFocused: Bool) {
        if isFocused && isShowingPlaceHolderText {
            self.text = ""
            self.isShowingPlaceHolderText = false
        }
    }
    
    public var body: some View {
        VStack {
            TextEditor(text: $text)
                .focused($isFocused)
                .onChange(of: isFocused) { isFocused in
                    textEditorFocusChanged(isFocused: isFocused)
                }
                .onChange(of: text, perform: textDidChange)
                .foregroundColor(isShowingPlaceHolderText ? .secondary : .primary)
            HStack {
                OlvidButtonNew(action: cancel, style: .glassOrBordered) {
                    Label(title: { Text("Cancel") }, icon: { Image(systemIcon: .xmarkCircle) })
                }
                OlvidButtonNew(action: ok) {
                    Label(title: { Text("Ok") }, icon: { Image(systemIcon: .checkmarkCircle) })
                }
                .disabled(isOkButtonDisabled)
            }
        }
        .padding()
        .onAppear(perform: setInitialTextValue)
    }
    
}


#if DEBUG

@MainActor
private struct ActionsForPreviews: PersonalNoteEditorViewActions {
    func userWantsToUpdatePersonalNote(_ view: PersonalNoteEditorView, with newText: String?, about: PersonalNoteEditorView.Model.About) {}
}

@MainActor
extension ActionsForPreviews: PersonalNoteEditorViewNavigation {
    func userWantsToDismissPersonalNoteEditorView(_ view: PersonalNoteEditorView) {}
}

@MainActor
private let actionsForPreviews = ActionsForPreviews()

#Preview {
    PersonalNoteEditorView(
        model: .init(initialText: "Some note writted before",
                     about: .contact(.sampleData)),
        actions: actionsForPreviews,
        navigation: actionsForPreviews)
}

#endif
