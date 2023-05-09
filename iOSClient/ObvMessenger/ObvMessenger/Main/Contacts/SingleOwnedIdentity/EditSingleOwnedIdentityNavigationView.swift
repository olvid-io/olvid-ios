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
import SwiftUI


struct EditSingleOwnedIdentityNavigationView: View {

    let editionType: EditSingleOwnedIdentityView.EditionType
    @ObservedObject var singleIdentity: SingleIdentity
    let userConfirmedPublishAction: () -> Void
    let dismissAction: () -> Void

    private func navigationBarTitle() -> Text {
        switch editionType {
        case .edition: return Text("EDIT_MY_ID")
        case .creation: return Text("CREATE_MY_ID")
        }
    }

    var body: some View {
        NavigationView {
            EditSingleOwnedIdentityView(editionType: editionType, singleIdentity: singleIdentity, userConfirmedPublishAction: userConfirmedPublishAction)
                .navigationBarTitle(navigationBarTitle(), displayMode: .inline)
                .navigationBarItems(leading:
                                        OptionalView(predicate: { editionType == .edition }) {
                                            Button(action: dismissAction,
                                                   label: {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .font(Font.system(size: 24, weight: .semibold, design: .default))
                                                   })
                                                .foregroundColor(Color(AppTheme.shared.colorScheme.tertiaryLabel)) }
                )
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}


struct EditSingleOwnedIdentityNavigationView_Previews: PreviewProvider {

    static var previews: some View {
        Group {
            ForEach(EditSingleOwnedIdentityView_Previews.testData) {
                EditSingleOwnedIdentityNavigationView(editionType: .edition,
                                                      singleIdentity: $0,
                                                      userConfirmedPublishAction: {},
                                                      dismissAction: {})
                EditSingleOwnedIdentityNavigationView(editionType: .creation,
                                                      singleIdentity: $0,
                                                      userConfirmedPublishAction: {},
                                                      dismissAction: {})
            }
            ForEach(EditSingleOwnedIdentityView_Previews.testData) {
                EditSingleOwnedIdentityNavigationView(editionType: .edition,
                                                      singleIdentity: $0,
                                                      userConfirmedPublishAction: {},
                                                      dismissAction: {})
                    .environment(\.colorScheme, .dark)
                EditSingleOwnedIdentityNavigationView(editionType: .creation,
                                                      singleIdentity: $0,
                                                      userConfirmedPublishAction: {},
                                                      dismissAction: {})
                    .environment(\.colorScheme, .dark)
            }
            EditSingleOwnedIdentityNavigationView(editionType: .edition,
                                                  singleIdentity: EditSingleOwnedIdentityView_Previews.testData[1],
                                                  userConfirmedPublishAction: {},
                                                  dismissAction: {})
                .environment(\.colorScheme, .dark)
                .previewDevice(PreviewDevice(rawValue: "iPhone XS"))
            EditSingleOwnedIdentityNavigationView(editionType: .creation,
                                                  singleIdentity: EditSingleOwnedIdentityView_Previews.testData[1],
                                                  userConfirmedPublishAction: {},
                                                  dismissAction: {})
                .environment(\.colorScheme, .dark)
                .previewDevice(PreviewDevice(rawValue: "iPhone XS"))
        }
    }
}
