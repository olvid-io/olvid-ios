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

final class UserNotificationsSubscriberHostingController: UIHostingController<UserNotificationsSubscriberView> {
    
    weak var delegate: LocalNotificationsSubscriberViewControllerDelegate?

    init(subscribeToLocalNotificationsAction: @escaping () -> Void) {
        let view = UserNotificationsSubscriberView(subscribeToLocalNotificationsAction: subscribeToLocalNotificationsAction)
        super.init(rootView: view)
    }
    
    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}

struct UserNotificationsSubscriberView: View {
    
    var subscribeToLocalNotificationsAction: () -> Void

    var body: some View {
                
        ZStack {
            Color(AppTheme.shared.colorScheme.systemBackground)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .edgesIgnoringSafeArea(.all)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Almost there!")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Spacer()
                }
                ObvCardView {
                    Text("SUBSCRIBING_TO_USER_NOTIFICATIONS_EXPLANATION")
                        .frame(minWidth: .none,
                               maxWidth: .infinity,
                               minHeight: .none,
                               idealHeight: .none,
                               maxHeight: .none,
                               alignment: .center)
                        .font(.body)
                }
                OlvidButton(style: .blue, title: Text("CONTINUE")) {
                    subscribeToLocalNotificationsAction()
                }
                Spacer()
            }.padding()
        }
    }
}


struct UserNotificationsSubscriberView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            UserNotificationsSubscriberView(subscribeToLocalNotificationsAction: {})
            UserNotificationsSubscriberView(subscribeToLocalNotificationsAction: {})
                .environment(\.colorScheme, .dark)
                .environment(\.locale, .init(identifier: "fr"))
        }
    }
}
