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


struct HorizontalTitleAndSubtitle: View {
    
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .lineLimit(nil)
            Spacer()
            Text(subtitle)
                .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
        }
        .font(.body)
    }
}




struct HorizontalTitleAndSubtitle_Previews: PreviewProvider {
    
    private static let stores: [(title: String, date: Date)] = [
        ("Steve Jobs", Date()),
        ("Some very very long name just to see what happens in case of overflow", Date()),
    ]
    
    private static let dateFormater: DateFormatter = {
        let df = DateFormatter()
        df.doesRelativeDateFormatting = true
        df.dateStyle = .short
        df.timeStyle = .short
        df.locale = Locale.current
        return df
    }()
    
    static var previews: some View {
        Group {
            HorizontalTitleAndSubtitle(title: stores[0].title,
                                       subtitle: dateFormater.string(from: stores[0].date))
            HorizontalTitleAndSubtitle(title: stores[1].title,
                                       subtitle: dateFormater.string(from: stores[1].date))
        }
        .padding()
        .previewLayout(.fixed(width: 400, height: 130))
    }
}
