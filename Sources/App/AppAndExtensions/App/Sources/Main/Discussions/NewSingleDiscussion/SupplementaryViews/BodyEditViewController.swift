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

import UIKit
import SwiftUI
import ObvDesignSystem
import ObvAppTypes
import ObvComposition
import ObvTypes
import ObvSettings


@available(iOS 26.0, *)
@MainActor
protocol BodyEditViewDelegate {
    func userWantsToSendEditedMessage(_ view: BodyEditView, newBody: AttributedString?, messageIdentifier: ObvMessageAppIdentifier) async
    func userWantsToCancelMessageEdition(_ view: BodyEditView) async
}


@available(iOS 26.0, *)
final class BodyEditViewController: UIHostingController<BodyEditView> {
    
    init(currentBody: AttributedString?, messageIdentifier: ObvMessageAppIdentifier, delegate: BodyEditViewDelegate) {
        let rootView = BodyEditView(currentBody: currentBody, messageIdentifier: messageIdentifier, delegate: delegate)
        super.init(rootView: rootView)
    }
    
    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}


@available(iOS 26.0, *)
struct BodyEditView: View {

    let initialBody: AttributedString?
    let delegate: BodyEditViewDelegate
    let messageIdentifier: ObvMessageAppIdentifier
    
    @State private var isInterfaceDisabled = false

    @State private var text: AttributedString
    @State private var selection: AttributedTextSelection

    init(currentBody: AttributedString?, messageIdentifier: ObvMessageAppIdentifier, delegate: BodyEditViewDelegate) {
        self.initialBody = currentBody
        self.delegate = delegate
        self.messageIdentifier = messageIdentifier
        let body = currentBody ?? AttributedString()
        self._text = State(initialValue: body)
        self._selection = State(initialValue: AttributedTextSelection(insertionPoint: body.endIndex))
    }
    
    private func dismissButtonTapped() {
        isInterfaceDisabled = true
        Task {
            await delegate.userWantsToCancelMessageEdition(self)
        }
    }
    
    private func sendButtonTapped() {
        isInterfaceDisabled = true
        Task {
            await delegate.userWantsToSendEditedMessage(self, newBody: text, messageIdentifier: messageIdentifier)
        }
    }
    
    /// This method is called whenever the text selection changes. It adjusts the text selection to ensure that mentions are always fully selected,
    /// whether the user moves the cursor or selects a range of text.
    private func onChangeOfAttributedTextSelection(_ oldValue: AttributedTextSelection, _ newValue: AttributedTextSelection) {
        self.selection = self.text.adjustSelectionForMentions(newValue)
    }
    
    /// This method is called whenever the text changes. It ensures atomic removal of entire mentions.
    ///
    /// If a partial mention is deleted (e.g., a single character at the end of a mention),
    /// it removes the **entire mention**.
    ///
    /// - **Assumption**:
    ///   Relies on `onChangeOfAttributedTextSelection(...)` to pre-filter cases,
    ///   so only single-character deletions at mention end are handled here.
    private func onChangeOfText(_ oldValue: AttributedString, _ newValue: AttributedString) {
        if let (fixedText, fixedInsertionIndex) = newValue.fixingPartialMentionDeletionCompared(to: oldValue) {
            self.text = fixedText
            self.selection = .init(insertionPoint: fixedInsertionIndex)
        }
    }
    
    
    var body: some View {
        ZStack {
            Color(Color(UIColor.secondarySystemBackground))
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0.0) {
                Spacer()
                VStack(spacing: 0.0) {
                    Text("EDIT_YOUR_MESSAGE")
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(nil)
                        .multilineTextAlignment(.center)
                        .font(.title)
                        .foregroundColor(Color(AppTheme.shared.colorScheme.label))
                        .padding(.bottom, 4.0)
                    Text("UPDATE_YOUR_ALREADY_SENT_MESSAGE")
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(nil)
                        .multilineTextAlignment(.center)
                        .font(.callout)
                        .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                        .padding(.bottom, 8.0)
                    ObvCardView(backgroundColor: Color(UIColor.systemBackground)) {
                        TextEditor(text: $text, selection: $selection)
                            .autocorrectionObv(autocorrection: ObvMessengerSettings.Discussions.autocorrectionType, spellChecking: .yes)
                            .textInputFormattingControlVisibility(.hidden, for: .all)
                            .attributedTextFormattingDefinition(ComposeMentionTextFormattingDefinition())
                    }
                    .padding(.vertical)
                    HStack {
                        OlvidButtonNew(action: dismissButtonTapped, style: .glassOrBordered) {
                            Label { Text("Cancel") } icon: { Image(systemIcon: .xmarkCircleFill) }
                        }
                        OlvidButtonNew(action: sendButtonTapped) {
                            Label { Text("Send") } icon: { Image(systemIcon: .paperplaneFill) }
                        }
                        .disabled(text.trimmingWhitespacesAndNewlines() == initialBody)
                    }
                }
                .padding()
            }
        }
        .onChange(of: selection, onChangeOfAttributedTextSelection)
        .onChange(of: text, onChangeOfText)
        .disabled(isInterfaceDisabled)
    }
    
}


// MARK: - Previews

#if DEBUG

@available(iOS 26.0, *)
@MainActor
private final class DelegateForPreviews: BodyEditViewDelegate {
    
    func userWantsToSendEditedMessage(_ view: BodyEditView, newBody: AttributedString?, messageIdentifier: ObvAppTypes.ObvMessageAppIdentifier) async {
        print("User wants to send edited message: \(String(describing: newBody))")
    }
    
    
    func userWantsToCancelMessageEdition(_ view: BodyEditView) async {
        print("User wants to cancel message edition")
    }
    
}

@available(iOS 26.0, *)
@MainActor
private let delegateForPreviews = DelegateForPreviews()

extension ObvCryptoId {
    
    @MainActor
    static let sampleDataForOwnedCryptoId: Self = try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!)

    @MainActor
    static let sampleDataForContactCryptoId: Self = try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000153c2183e6feef914ef20ae0f2ce4dd025022221b0bfdf22fb16859feac477fa0023713e65219d2c01f6feb26f9d2a390fd9afce7389f7ae22884f0efccad74c83")!)

}

@MainActor
private let contactIdentifier = ObvContactIdentifier(contactCryptoId: .sampleDataForContactCryptoId, ownedCryptoId: .sampleDataForOwnedCryptoId)

@MainActor
private let discussionIdentifier = ObvDiscussionIdentifier.oneToOne(id: contactIdentifier)

@MainActor
private let messageIdentifier = ObvMessageAppIdentifier.sent(discussionIdentifier: discussionIdentifier, senderThreadIdentifier: UUID(), senderSequenceNumber: 0)

@available(iOS 26.0, *)
#Preview {
    BodyEditView(currentBody: AttributedString("Test string"),
                 messageIdentifier: messageIdentifier,
                 delegate: delegateForPreviews)
}

#endif
