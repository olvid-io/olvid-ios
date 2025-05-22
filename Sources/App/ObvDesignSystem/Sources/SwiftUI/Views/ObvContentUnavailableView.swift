/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import ObvSystemIcon


public struct ObvContentUnavailableView: View {
    
    let title: String
    let systemIcon: SystemIcon
    let description: String?
    private let specialCase: SpecialCase?
    
    
    private enum SpecialCase {
        case search
    }

    
    public init(title: String, systemIcon: SystemIcon, description: String?) {
        self.init(title: title, systemIcon: systemIcon, description: description, specialCase: nil)
    }

    
    public static var search: Self {
        // Those localized values are not used under iOS17+
        let title = String(localizedInThisBundle: "CONTENT_UNAVAILABLE_VIEW_FOR_SEARCH_TITLE")
        let description = String(localizedInThisBundle: "CONTENT_UNAVAILABLE_VIEW_FOR_SEARCH_DESCRIPTION")
        return self.init(title: title, systemIcon: .magnifyingglass, description: description, specialCase: .search)
    }
    
    
    private init(title: String, systemIcon: SystemIcon, description: String?, specialCase: SpecialCase?) {
        self.title = title
        self.systemIcon = systemIcon
        self.description = description
        self.specialCase = specialCase
    }

    
    public var body: some View {
        
        if #available(iOS 17, *) {

            switch specialCase {
                
            case .none:
                
                ContentUnavailableView(
                    label: {
                        Label(title: { Text(title) },
                              icon: { Image(systemIcon: systemIcon) })
                    },
                    description: {
                        if let description {
                            Text(description)
                        } else {
                            EmptyView()
                        }
                    })
                
            case .search:

                ContentUnavailableView.search
                
            }
            
        } else {
            
            ContentUnavailableViewForLegacyView(
                title: title,
                systemIcon: systemIcon,
                description: description)
            
        }
        
    }
    
}


/// This view is used for older versions of iOS.
private struct ContentUnavailableViewForLegacyView: View {
    
    let title: String
    let systemIcon: SystemIcon
    let description: String?

    var body: some View {
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
                        .multilineTextAlignment(.center)
                    if let description {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
                Spacer()
            }
        }
    }
    
}



// MARK: - Previews

#if DEBUG

#Preview("en") {
    ObvContentUnavailableView.search
}

#Preview("fr") {
    ObvContentUnavailableView.search
        .environment(\.locale, .init(identifier: "fr"))
}

#endif
