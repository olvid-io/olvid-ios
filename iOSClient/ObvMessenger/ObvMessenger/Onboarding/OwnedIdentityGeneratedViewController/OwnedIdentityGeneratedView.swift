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

import SwiftUI

final class OwnedIdentityGeneratedHostingController: UIHostingController<OwnedIdentityGeneratedView> {
    
    init(startUsingOlvidAction: @escaping () -> Void) {
        let view = OwnedIdentityGeneratedView(startUsingOlvidAction: startUsingOlvidAction)
        super.init(rootView: view)
    }
    
    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}

struct OwnedIdentityGeneratedView: View {
    
    let startUsingOlvidAction: () -> Void
    
    var body: some View {
                
        ZStack {
            Color(AppTheme.shared.colorScheme.systemBackground)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .edgesIgnoringSafeArea(.all)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Congratulations!")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .padding(.horizontal)
                        .padding(.top)
                    Spacer()
                }
                ScrollView {
                    VStack(spacing: 0) {
                        HStack { Spacer() }
                        ObvCardView {
                            Text("OWNED_IDENTITY_GENERATED_EXPLANATION")
                                .frame(minWidth: .none,
                                       maxWidth: .infinity,
                                       minHeight: .none,
                                       idealHeight: .none,
                                       maxHeight: .none,
                                       alignment: .center)
                                .font(.body)
                        }
                        .padding(.bottom)
                        OlvidButton(style: .blue, title: Text("START_USING_OLVID")) {
                            startUsingOlvidAction()
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top)
                }
                Spacer()
            }
        }
    }
}

struct OwnedIdentityGeneratedView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            OwnedIdentityGeneratedView(startUsingOlvidAction: {})
                .environment(\.colorScheme, .dark)
            OwnedIdentityGeneratedView(startUsingOlvidAction: {})
                .environment(\.locale, .init(identifier: "fr"))
            OwnedIdentityGeneratedView(startUsingOlvidAction: {})
                .previewDevice(PreviewDevice(rawValue: "iPhone8,4"))
            OwnedIdentityGeneratedView(startUsingOlvidAction: {})
                .environment(\.locale, .init(identifier: "fr"))
                .environment(\.colorScheme, .dark)
                .previewDevice(PreviewDevice(rawValue: "iPhone8,4"))
        }
    }
}
