/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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

import ObvUI
import ObvUICoreData
import SwiftUI



struct EditSingleContactIdentityNicknameView: View {

    @ObservedObject var singleIdentity: SingleContactIdentity
    let saveAction: () -> Void
    /// Used to prevent small screen settings when the keyboard appears on a large screen
    @State private var largeScreenUsedOnce = false

    private var canSave: Bool {
        return singleIdentity.hasChanged
    }

    private var disableSaveButton: Bool {
        !canSave
    }

    private var disableResetButton: Bool {
        singleIdentity.customDisplayName == nil && singleIdentity.customPhotoURL == nil
    }

    private var deviceName: String {
        UIDevice.current.name
    }
    
    var body: some View {
        ZStack {
            Color(AppTheme.shared.colorScheme.systemBackground)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .edgesIgnoringSafeArea(.all)
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 0) {
                    ObvCardView {
                        HStack {
                            /// REMARK the given singleIdentity does not allow to modify its picture, but here in nickname editor we want to force the picture edition)
                            ContactIdentityCardContentView(
                                model: singleIdentity,
                                preferredDetails: .customOrTrusted,
                                editionMode: singleIdentity.editCustomPictureMode)
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top)
                .fixedSize(horizontal: false, vertical: true)
                Form {
                    Section(footer:
                                VStack(spacing: 16) {
                        Text("EDIT_CONTACT_NICKNAME_EXPLANATION_\(deviceName)")
                        HStack(spacing: 16) {
                            OlvidButton(style: .standard,
                                        title: Text(CommonString.Word.Reset),
                                        systemIcon: .pencilSlash,
                                        action: {
                                withAnimation {
                                    singleIdentity.customDisplayName = nil
                                    singleIdentity.customPhotoURL = nil
                                }
                            })
                                .disabled(disableResetButton)
                            OlvidButton(style: .blue,
                                        title: Text(CommonString.Word.Save),
                                        systemIcon: .checkmarkSquareFill,
                                        action: {
                                saveAction()
                            })
                                .disabled(disableSaveButton)
                        }
                    }
                    ) {
                        TextField(LocalizedStringKey("FORM_NICKNAME"), text: Binding.init(
                            get: { singleIdentity.customDisplayName ?? "" },
                            set: {
                                singleIdentity.customDisplayName = $0.isEmpty ? nil : $0
                            }))
                            .disableAutocorrection(true)
                    }
                }
            }
        }
    }
}


struct EditSingleContactIdentityNicknameView_Previews: PreviewProvider {

    static let testData = [
        SingleContactIdentity(
            firstName: "Marco",
            lastName: "Polo",
            position: "Traveler",
            company: "Venezia",
            publishedContactDetails: nil,
            contactStatus: .seenPublishedDetails,
            contactHasNoDevice: false,
            contactIsOneToOne: true,
            isActive: true),
        SingleContactIdentity(firstName: "Marco",
                              lastName: "Polo",
                              position: "Traveler",
                              company: "Venezia",
                              customDisplayName: "Il Milione",
                              publishedContactDetails: nil,
                              contactStatus: .seenPublishedDetails,
                              contactHasNoDevice: false,
                              contactIsOneToOne: true,
                              isActive: true),
    ]

    static var previews: some View {
        Group {
            ForEach(testData) {
                EditSingleContactIdentityNicknameView(singleIdentity: $0,
                                                      saveAction: {})
            }
            ForEach(testData) {
                EditSingleContactIdentityNicknameView(singleIdentity: $0,
                                                      saveAction: {})
                    .environment(\.colorScheme, .dark)
            }
        }
    }
}
