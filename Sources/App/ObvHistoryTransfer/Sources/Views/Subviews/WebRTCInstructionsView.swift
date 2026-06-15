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
protocol WebRTCInstructionsViewActions {
    func userConfirmedOnSourceDeviceThatDestinationDeviceIsOnSameWifiNetwork(_ view: WebRTCInstructionsView, otherOwnedDeviceIdentifier: ObvOwnedDeviceIdentifier, nameOfRemoteDevice: String?)
}


struct WebRTCInstructionsView: View {

    let otherOwnedDeviceIdentifier: ObvOwnedDeviceIdentifier
    let nameOfRemoteDevice: String?
    let actions: any WebRTCInstructionsViewActions

    private var title: String {
        if let nameOfRemoteDevice {
            return String(localizedInThisBundle: "WEBRTC_INSTRUCTIONS_TITLE_\(nameOfRemoteDevice)")
        } else {
            return String(localizedInThisBundle: "WEBRTC_INSTRUCTIONS_TITLE")
        }
    }
    
    private var instructionString01: String {
        if let nameOfRemoteDevice {
            return String(localizedInThisBundle: "WEBRTC_INSTRUCTIONS_STEP_TURN_ON_\(nameOfRemoteDevice)")
        } else {
            return String(localizedInThisBundle: "WEBRTC_INSTRUCTIONS_STEP_TURN_ON")
        }
    }
    
    private var instructionString02: String {
        if let nameOfRemoteDevice {
            String(localizedInThisBundle: "WEBRTC_INSTRUCTIONS_STEP_SAME_WIFI_\(nameOfRemoteDevice)")
        } else {
            String(localizedInThisBundle: "WEBRTC_INSTRUCTIONS_STEP_SAME_WIFI")
        }

    }
    
    private func buttonTapped() {
        actions.userConfirmedOnSourceDeviceThatDestinationDeviceIsOnSameWifiNetwork(self, otherOwnedDeviceIdentifier: otherOwnedDeviceIdentifier, nameOfRemoteDevice: nameOfRemoteDevice)
    }
    
    var body: some View {
        VStack(spacing: 0) {

            ScrollView {
                VStack(spacing: 20) {

                    HistoryTransferSectionTitle(title: title)
                        .padding(.bottom)

                    VStack(spacing: 0) {

                        InstructionRowView(systemIcon: .power, text: instructionString01, color: .green)

                        Divider()
                            .padding(.leading, 60)

                        InstructionRowView(systemIcon: .wifi, text: instructionString02, color: .blue)

                    }
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: ObvCardViewParameters.defaultCornerRadius, style: .continuous))

                }
                .padding()
            }

            OlvidButtonNew(action: buttonTapped) {
                Text("WEBRTC_INSTRUCTIONS_CONTINUE_BUTTON_TITLE")
            }
            .padding()

        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

}


struct InstructionRowView: View {

    let systemIcon: SystemIcon
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemIcon: systemIcon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 7))

            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

}


// MARK: - Previews

#if DEBUG

@MainActor
private final class WebRTCInstructionsViewActionsForPreviews {}

extension WebRTCInstructionsViewActionsForPreviews: WebRTCInstructionsViewActions {

    func userConfirmedOnSourceDeviceThatDestinationDeviceIsOnSameWifiNetwork(_ view: WebRTCInstructionsView, otherOwnedDeviceIdentifier: ObvOwnedDeviceIdentifier, nameOfRemoteDevice: String?) {
        print("User confirmed that the destination device is on the same Wi-Fi network")
    }

}

@MainActor
private let actionsForPreviews = WebRTCInstructionsViewActionsForPreviews()

#Preview {
    NavigationStack {
        WebRTCInstructionsView(
            otherOwnedDeviceIdentifier: .sampleDatas[0],
            nameOfRemoteDevice: "OnePlus 13",
            actions: actionsForPreviews
        )
    }
}

#endif
