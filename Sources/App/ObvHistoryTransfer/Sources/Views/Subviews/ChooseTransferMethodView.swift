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
import ObvTypes
import ObvDesignSystem


@MainActor
protocol ChooseTransferMethodViewActions {
    func userChoseTransferMethod(selectedTransferMethod: TransferMethod, selectedOwnedCryptoId: ObvCryptoId, role: TransferRole)
}




struct ChooseTransferMethodView: View {

    let role: TransferRole
    let selectedOwnedCryptoId: ObvCryptoId
    let actions: any ChooseTransferMethodViewActions

    @State private var selectedMethod: TransferMethod? = nil

    private var navigationTitle: String {
        String(localizedInThisBundle: "CHOOSE_TRANSFER_METHOD_NAVIGATION_TITLE")
    }

    private func continueButtonTapped() {
        guard let selectedMethod else { assertionFailure(); return }
        actions.userChoseTransferMethod(selectedTransferMethod: selectedMethod, selectedOwnedCryptoId: selectedOwnedCryptoId, role: role)
    }

    var body: some View {
        VStack(spacing: 0) {

            ScrollView {
                VStack(spacing: 20) {

                    HistoryTransferSectionTitle(title: String(localizedInThisBundle: "CHOOSE_TRANSFER_METHOD_TITLE"))

                    VStack(spacing: 12) {
                        TransferMethodCardView(
                            systemIcon: .wifi,
                            iconBackgroundColor: .blue,
                            title: "CHOOSE_TRANSFER_METHOD_WIFI_TITLE",
                            subtitle: "CHOOSE_TRANSFER_METHOD_WIFI_SUBTITLE",
                            method: .webRTC,
                            selectedMethod: $selectedMethod
                        )
                        TransferMethodBetweenIPhonesCardView(selectedMethod: $selectedMethod)
                        TransferMethodAsZip(selectedMethod: $selectedMethod, role: role)
                    }

                }
                .padding()
            }

            OlvidButtonNew(action: continueButtonTapped) {
                Text("CONTINUE_BUTTON_TITLE")
            }
            .disabled(selectedMethod == nil)
            .padding()

        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(navigationTitle)
        .toolbar {
            // Hide the navigation title, but keep it in the back button
            ToolbarItem(placement: .principal) {
                Text(verbatim: "")
            }
        }
    }

}


struct TransferMethodBetweenIPhonesCardView: View {
    
    @Binding var selectedMethod: TransferMethod?
    
    var body: some View {
        TransferMethodCardView(
            systemIcon: .iphone,
            iconBackgroundColor: Color(.systemGray),
            title: "CHOOSE_TRANSFER_METHOD_IPHONE_TITLE",
            subtitle: "CHOOSE_TRANSFER_METHOD_IPHONE_SUBTITLE",
            method: .wifiAware,
            selectedMethod: $selectedMethod
        )
    }
}


struct TransferMethodAsZip: View {
    
    @Binding var selectedMethod: TransferMethod?
    let role: TransferRole

    private var title: LocalizedStringKey {
        switch role {
        case .source:
            return "CHOOSE_TRANSFER_METHOD_ZIP_TITLE_SOURCE"
        case .destination:
            return "CHOOSE_TRANSFER_METHOD_ZIP_TITLE_DESTINATION"
        }
    }

    private var subtitle: LocalizedStringKey {
        switch role {
        case .source:
            return "CHOOSE_TRANSFER_METHOD_ZIP_SUBTITLE_SOURCE"
        case .destination:
            return "CHOOSE_TRANSFER_METHOD_ZIP_SUBTITLE_DESTINATION"
        }
    }

    var body: some View {
        TransferMethodCardView(
            systemIcon: .zipperPage,
            iconBackgroundColor: .orange,
            title: title,
            subtitle: subtitle,
            method: .zip,
            selectedMethod: $selectedMethod
        )
    }
    
}


private struct TransferMethodCardView: View {

    let systemIcon: SystemIcon
    let iconBackgroundColor: Color
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let method: TransferMethod
    @Binding var selectedMethod: TransferMethod?

    private var isSelected: Bool { selectedMethod == method }
    private let cornerRadius: CGFloat = ObvCardViewParameters.defaultCornerRadius

    var body: some View {
        Button {
            withAnimation { selectedMethod = method }
        } label: {
            HStack(spacing: 12) {
                
                Image(systemIcon: systemIcon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(iconBackgroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)
                
                ObvRadioButtonView(value: method, selectedValue: $selectedMethod)

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


// MARK: - Previews

#if DEBUG

private final class ActionsForPreviews: ChooseTransferMethodViewActions {
    func userChoseTransferMethod(selectedTransferMethod: TransferMethod, selectedOwnedCryptoId: ObvCryptoId, role: TransferRole) {}
}

#Preview {
    NavigationStack {
        ChooseTransferMethodView(
            role: .source,
            selectedOwnedCryptoId: ObvCryptoId.sampleDatasForOwnedCryptoId[0],
            actions: ActionsForPreviews()
        )
    }
}

#endif
