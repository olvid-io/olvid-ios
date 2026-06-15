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
import ObvDesignSystem


struct WebRTCImportInstructionsViewActions: View {
    
    private var title: String {
        return String(localizedInThisBundle: "WEBRTC_INSTRUCTIONS_TITLE")
    }

    private var instructionString01: String {
        return String(localizedInThisBundle: "WEBRTC_INSTRUCTIONS_STEP_TURN_ON")
    }

    private var instructionString02: String {
        String(localizedInThisBundle: "WEBRTC_INSTRUCTIONS_STEP_SAME_WIFI")
    }

    private var instructionString03: String {
        String(localizedInThisBundle: "WEBRTC_INSTRUCTIONS_STEP_NAVIGATE_TO_TRANSFER_SETTINGS_ON_REMOTE_DEVICE")
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

                        Divider()
                            .padding(.leading, 60)

                        InstructionRowView(systemIcon: .macbookAndIphone, text: instructionString03, color: .orange)

                    }
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: ObvCardViewParameters.defaultCornerRadius, style: .continuous))

                }
                .padding()
            }

        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

}


#if DEBUG

#Preview {
    WebRTCImportInstructionsViewActions()
}

#endif
