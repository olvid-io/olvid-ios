/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
 *
 *  This file is part of Olvid for iOS.
 *
 *  Olvid is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU Affero General Public License, version 3,
 *  as published by the Free Software Foundation.
 *
 *  Olvid is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PART ICULAR PURPOSE.  See the
 *  GNU Affero General Public License for more details.
 *
 *  You should have received a copy of the GNU Affero General Public License
 *  along with Olvid.  If not, see <https://www.gnu.org/licenses/>.
 */

import SwiftUI


struct NewOnboardingHeaderView: View {
    
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    
    var body: some View {
        VStack {
            Image("badge", bundle: nil)
                .resizable()
                .frame(width: 60, height: 60, alignment: .center)
                .padding()
            Text(title)
                .multilineTextAlignment(.center)
                .font(.title)
            if let subtitle {
                Text(subtitle)
                    .multilineTextAlignment(.center)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
}


struct NewOnboardingHeaderView_Previews: PreviewProvider {
    
    static var previews: some View {
        NewOnboardingHeaderView(
            title: "WELCOME_ONBOARDING_TITLE",
            subtitle: "WELCOME_ONBOARDING_SUBTITLE")
        NewOnboardingHeaderView(
            title: "WELCOME_ONBOARDING_TITLE",
            subtitle: "WELCOME_ONBOARDING_SUBTITLE")
        .environment(\.locale, .init(identifier: "fr"))
    }
    
}
