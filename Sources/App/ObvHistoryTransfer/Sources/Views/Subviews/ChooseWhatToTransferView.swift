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
import ObvTypes
import ObvDesignSystem
import ObvSystemIcon


@MainActor
protocol ChooseWhatToTransferViewActions {
    func userDidChooseWhatToTransferToDestination(_ view: ChooseWhatToTransferView, transferMethod: ChooseWhatToTransferView.ForTransferMethod, scope: TransferScope)
}


struct ChooseWhatToTransferView: View {

    let transferMethod: ForTransferMethod
    let actions: any ChooseWhatToTransferViewActions

    enum ForTransferMethod: Equatable, Hashable {
        case webrtc(otherOwnedDeviceIdentifier: ObvOwnedDeviceIdentifier, nameOfRemoteDevice: String?)
        case zip(ownedCryptoId: ObvCryptoId)
        case wifiAware(role: TransferRole, ownedCryptoId: ObvCryptoId)
    }
    
    @State private var selectedScope: TransferScope? = nil

    private func continueButtonTapped() {
        guard let selectedScope else { return }
        actions.userDidChooseWhatToTransferToDestination(self, transferMethod: transferMethod, scope: selectedScope)
    }

    var body: some View {
        VStack(spacing: 0) {

            ScrollView {
                VStack(spacing: 20) {

                    HistoryTransferSectionTitle(title: String(localizedInThisBundle: "CHOOSE_WHAT_TO_TRANSFER_TITLE"))

                    VStack(spacing: 12) {
                        TransferScopeOptionView(
                            title: "TRANSFER_SCOPE_MESSAGES_ONLY_TITLE",
                            subtitle: "TRANSFER_SCOPE_MESSAGES_ONLY_SUBTITLE",
                            scope: .messagesOnly,
                            selectedScope: $selectedScope
                        )
                        TransferScopeOptionView(
                            title: "TRANSFER_SCOPE_MESSAGES_AND_ATTACHMENTS_TITLE",
                            subtitle: "TRANSFER_SCOPE_MESSAGES_AND_ATTACHMENTS_SUBTITLE",
                            scope: .messagesAndAttachments,
                            selectedScope: $selectedScope
                        )
                    }

                }
                .padding()
            }

            OlvidButtonNew(action: continueButtonTapped) {
                Text("CONTINUE_BUTTON_TITLE")
            }
            .disabled(selectedScope == nil)
            .padding()

        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

}


private struct TransferScopeOptionView: View {

    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let scope: TransferScope
    @Binding var selectedScope: TransferScope?

    private var isSelected: Bool { selectedScope == scope }
    private let cornerRadius: CGFloat = ObvCardViewParameters.defaultCornerRadius

    @ViewBuilder
    private var iconView: some View {
        switch scope {
        case .messagesOnly:
            MessagesView()
        case .messagesAndAttachments:
            MessagesAndAttachmentsIconView()
        }
    }

    var body: some View {
        Button {
            withAnimation { selectedScope = scope }
        } label: {
            HStack {

                iconView
                    .padding(.trailing, 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .padding(.trailing, 8)

                Spacer(minLength: 0)

                ObvRadioButtonView(value: scope, selectedValue: $selectedScope)

            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .rainbowBorder(cornerRadius: cornerRadius, isActive: isSelected)
    }

}


private struct MessagesAndAttachmentsIconView: View {

    var body: some View {
        VStack(alignment: .center) {

            MessagesView()

            Image(systemIcon: .paperclip)
                .font(.system(size: MessagesView.size, weight: .medium))
                .foregroundStyle(.gray)

        }

    }

}


private struct MessagesView: View {
    
    static let size: CGFloat = 20
    
    var body: some View {
        Image(systemIcon: .bubbleLeftAndBubbleRightFill)
            .font(.system(size: MessagesView.size, weight: .medium))
            .foregroundStyle(.blue)
    }

    
}


// MARK: - Previews

#if DEBUG

private final class ActionsForPreviews: ChooseWhatToTransferViewActions {
    func userDidChooseWhatToTransferToDestination(_ view: ChooseWhatToTransferView, transferMethod: ChooseWhatToTransferView.ForTransferMethod, scope: TransferScope) {}
}

#Preview {
    NavigationStack {
        ChooseWhatToTransferView(
            transferMethod: .webrtc(otherOwnedDeviceIdentifier: ObvOwnedDeviceIdentifier.sampleDatas[0],
                                    nameOfRemoteDevice: "iPhone 17"),
            actions: ActionsForPreviews()
        )
    }
}

#endif
