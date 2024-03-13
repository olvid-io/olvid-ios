/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import UI_SystemIcon


struct ObvContentUnavailableView: View {
    
    private let title: LocalizedStringKey
    private let systemIcon: SystemIcon
    private let description: Text?
    
    init(_ title: LocalizedStringKey, systemIcon: SystemIcon, description: Text? = nil) {
        self.title = title
        self.systemIcon = systemIcon
        self.description = description
    }

    var body: some View {
        if #available(iOS 17.0, *), true {
            ContentUnavailableView(title, systemImage: systemIcon.systemName, description: description)
        } else {
            VStack(alignment: .center) {
                HStack {
                    Spacer()
                    VStack {
                        Image(systemIcon: systemIcon)
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 8)
                        Text(title)
                            .font(.title2)
                            .bold()
                            .foregroundStyle(.primary)
                        description
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }.padding(.bottom, 16)
                    Spacer()
                }
            }
        }
    }
    
}


struct ObvContentUnavailableView_Previews: PreviewProvider {
    
    static var previews: some View {
        ObvContentUnavailableView("Title", systemIcon: .tray, description: Text("Some description."))
    }
    
}
