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


protocol ProfileAlreadyExistsOnTargetDeviceViewActionsProtocol {
    func userWantsToNavigateToProfileThatAlreadyExistsOnTargetDevice(ownedCryptoId: ObvCryptoId) async
}


/// Shown on the target device when the profile the user tried to transfer turns out to already exist on this device.
/// This is not an error: there was simply nothing to transfer. This screen explains that and allows the user to navigate to the profile.
struct ProfileAlreadyExistsOnTargetDeviceView: View {

    let model: Model
    let actions: ProfileAlreadyExistsOnTargetDeviceViewActionsProtocol

    struct Model {
        let ownedCryptoId: ObvCryptoId
    }

    private func showProfileButtonTapped() {
        Task {
            await actions.userWantsToNavigateToProfileThatAlreadyExistsOnTargetDevice(ownedCryptoId: model.ownedCryptoId)
        }
    }


    var body: some View {
        ScrollView {
            VStack {

                ObvHeaderView(title: "PROFILE_ALREADY_EXISTS_ON_TARGET_DEVICE_TITLE".localizedInThisBundle,
                              subtitle: "PROFILE_ALREADY_EXISTS_ON_TARGET_DEVICE_SUBTITLE".localizedInThisBundle)

                LaptopcomputerAndIphoneView()
                    .padding(.top)

                HStack {
                    Text("PROFILE_ALREADY_EXISTS_ON_TARGET_DEVICE_BODY_NOTHING_TO_DO")
                        .font(.body)
                        .foregroundStyle(.primary)
                    Spacer()
                }.padding(.top)

                HStack {
                    Text("PROFILE_ALREADY_EXISTS_ON_TARGET_DEVICE_BODY_MULTIPLE_PROFILES")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Spacer()
                }.padding(.top)

                OlvidButtonNew(action: showProfileButtonTapped) {
                    Text("PROFILE_ALREADY_EXISTS_ON_TARGET_DEVICE_SHOW_PROFILE_BUTTON")
                }.padding(.top)

                Spacer()

            }
            .padding(.horizontal)
        }
    }

}


private struct LaptopcomputerAndIphoneView: View {
    var body: some View {
        HStack {
            Spacer()
            Image(systemIcon: .laptopcomputerAndIphone)
                .font(.system(size: 80, weight: .regular))
                .foregroundStyle(.secondary)
                .overlay(alignment: .topTrailing) {
                    Image(systemIcon: .checkmarkCircleFill)
                        .font(.system(size: 30, weight: .regular))
                        .foregroundStyle(Color(UIColor.systemGreen))
                        .background(.background, in: .circle.inset(by: -2))
                        .offset(y: -10)
                }
            Spacer()
        }
    }
}



// MARK: - Previews

#if DEBUG

private final class ActionsForPreviews: ProfileAlreadyExistsOnTargetDeviceViewActionsProtocol {

    func userWantsToNavigateToProfileThatAlreadyExistsOnTargetDevice(ownedCryptoId: ObvCryptoId) async {}

}

extension ObvCryptoId {

    @MainActor
    fileprivate static let sampleData: Self =
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!)

}

@MainActor
private let modelForPreviews: ProfileAlreadyExistsOnTargetDeviceView.Model = .init(ownedCryptoId: .sampleData)

@MainActor
private let actionsForPreviews = ActionsForPreviews()

#Preview {
    NavigationStack {
        ProfileAlreadyExistsOnTargetDeviceView(model: modelForPreviews, actions: actionsForPreviews)
    }
}

#endif
