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
import ObvEngine

final class AutorisationRequesterHostingController: UIHostingController<AutorisationRequesterView> {
    
    enum AutorisationCategory {
        case localNotifications
        case recordPermission
    }
    
    init(autorisationCategory: AutorisationCategory, delegate: AutorisationRequesterHostingControllerDelegate) {
        let view = AutorisationRequesterView(autorisationCategory: autorisationCategory, delegate: delegate)
        super.init(rootView: view)
    }
    
    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}

struct AutorisationRequesterView: View {

    let autorisationCategory: AutorisationRequesterHostingController.AutorisationCategory
    let delegate: AutorisationRequesterHostingControllerDelegate

    private var textBody: Text {
        switch autorisationCategory {
        case .localNotifications:
            return Text("SUBSCRIBING_TO_USER_NOTIFICATIONS_EXPLANATION")
        case .recordPermission:
            return Text("EXPLANATION_WHY_RECORD_PERMISSION_IS_IMPORTANT")
        }
    }
    
    private var textTitle: Text {
        switch autorisationCategory {
        case .localNotifications:
            return Text("TITLE_NEVER_MISS_A_MESSAGE")
        case .recordPermission:
            return Text("TITLE_NEVER_MISS_A_SECURE_CALL")
        }
    }
    
    private var buttonTitle: Text {
        switch autorisationCategory {
        case .localNotifications:
            return Text("BUTON_TITLE_ACTIVATE_NOTIFICATION")
        case .recordPermission:
            return Text("BUTON_TITLE_REQUEST_RECORD_PERMISSION")
        }
    }
    
    var body: some View {
                
        ZStack {
            Color(AppTheme.shared.colorScheme.systemBackground)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .edgesIgnoringSafeArea(.all)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    textTitle
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Spacer()
                }
                ObvCardView {
                    textBody
                        .frame(minWidth: .none,
                               maxWidth: .infinity,
                               minHeight: .none,
                               idealHeight: .none,
                               maxHeight: .none,
                               alignment: .center)
                        .font(.body)
                }
                Spacer()
                OlvidButton(style: .blue, title: buttonTitle) {
                    Task(priority: .userInitiated) {
                        await delegate.requestAutorisation(now: true, for: autorisationCategory)
                    }
                }
                OlvidButton(style: .standardWithBlueText, title: Text(CommonString.Word.Later)) {
                    Task(priority: .userInitiated) {
                        await delegate.requestAutorisation(now: false, for: autorisationCategory)
                    }
                }
            }.padding()
        }
    }
}


struct AutorisationRequesterView_Previews: PreviewProvider {
    
    private final class MocAutorisationRequesterHostingControllerDelegate: AutorisationRequesterHostingControllerDelegate {
        @MainActor
        func requestAutorisation(now: Bool, for autorisationCategory: AutorisationRequesterHostingController.AutorisationCategory) async {}
    }
    
    private static let delegate = MocAutorisationRequesterHostingControllerDelegate()
    
    static var previews: some View {
        Group {
            AutorisationRequesterView(autorisationCategory: .recordPermission, delegate: delegate)
            AutorisationRequesterView(autorisationCategory: .recordPermission, delegate: delegate)
                .environment(\.locale, .init(identifier: "fr"))
            AutorisationRequesterView(autorisationCategory: .localNotifications, delegate: delegate)
            AutorisationRequesterView(autorisationCategory: .localNotifications, delegate: delegate)
                .environment(\.locale, .init(identifier: "fr"))
        }
    }
}
