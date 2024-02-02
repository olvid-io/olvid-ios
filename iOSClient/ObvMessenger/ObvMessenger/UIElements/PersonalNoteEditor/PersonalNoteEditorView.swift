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


protocol PersonalNoteEditorViewModelProtocol {
    var initialText: String? { get }
}


protocol PersonalNoteEditorViewActionsDelegate {
    func userWantsToDismissPersonalNoteEditorView() async
    func userWantsToUpdatePersonalNote(with newText: String?) async
}

@available(iOS 14.0, *)
struct PersonalNoteEditorView<Model: PersonalNoteEditorViewModelProtocol>: View {
    
    let model: Model
    let actions: PersonalNoteEditorViewActionsDelegate
    
    @State private var text = ""
    @State private var isOkButtonDisabled = true
    @State private var isShowingPlaceHolderText = false

    private func cancel() {
        Task {
            await actions.userWantsToDismissPersonalNoteEditorView()
        }
    }
    
    private func setInitialTextValue() {
        if let initialText = model.initialText, !initialText.isEmpty {
            self.text = model.initialText ?? ""
        } else {
            self.isShowingPlaceHolderText = true
            self.text = NSLocalizedString("TYPE_PERSONAL_NOTE_HERE", comment: "")
        }
    }
    
    private func ok() {
        let newText = self.text
        Task {
            await actions.userWantsToUpdatePersonalNote(with: newText)
        }
    }
    
    private func textDidChange(_ newText: String) {
        isOkButtonDisabled = text == (model.initialText ?? "") || isShowingPlaceHolderText
    }
    
    private func textEditorWasTapped() {
        if isShowingPlaceHolderText {
            self.text = ""
            self.isShowingPlaceHolderText = false
        }
    }
    
    var body: some View {
        VStack {
            TextEditor(text: $text)
                .onChange(of: text, perform: textDidChange)
                .foregroundColor(isShowingPlaceHolderText ? .secondary : .primary)
                .onTapGesture(perform: textEditorWasTapped)
            HStack {
                OlvidButton(
                    style: .standardWithBlueText,
                    title: Text("Cancel"),
                    systemIcon: .xmarkCircle,
                    action: cancel)
                OlvidButton(
                    style: .blue,
                    title: Text("Ok"),
                    systemIcon: .checkmarkCircle,
                    action: ok)
                .disabled(isOkButtonDisabled)
            }
        }
        .padding()
        .onAppear(perform: setInitialTextValue)
    }
    
}



@available(iOS 14.0, *)
struct PersonalNoteEditorView_Previews: PreviewProvider {
    
    private struct ModelForPreviews: PersonalNoteEditorViewModelProtocol {
        let initialText: String?
    }
    
    private struct ActionsForPreviews: PersonalNoteEditorViewActionsDelegate {
        func userWantsToUpdatePersonalNote(with newText: String?) async {}
        func userWantsToDismissPersonalNoteEditorView() async {}
    }
    
    static var previews: some View {
        Group {
            PersonalNoteEditorView(
                model: ModelForPreviews(initialText: "Some note writted before"),
                actions: ActionsForPreviews())
            PersonalNoteEditorView(
                model: ModelForPreviews(initialText: nil),
                actions: ActionsForPreviews())
        }
    }
    
}
