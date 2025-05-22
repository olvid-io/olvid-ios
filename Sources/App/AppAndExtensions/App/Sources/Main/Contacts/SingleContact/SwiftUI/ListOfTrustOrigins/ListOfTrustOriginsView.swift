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
import ObvEngine
import ObvUI
import ObvDesignSystem


struct ListOfTrustOriginsView: View {
    
    let trustOrigins: [ObvTrustOrigin]
    
    var body: some View {
        ScrollView {
            ObvCardView {
                VStack(alignment: .leading) {
                    ForEach(trustOrigins, id: \.self) { trustOrigin in
                        TrustOriginCellView(trustOrigin: trustOrigin)
                        if trustOrigin != trustOrigins.last {
                            SeparatorView()
                        }
                    }
                }
            }.padding()
            Spacer()
        }
    }
    
}



// MARK: - Previews

struct ListOfTrustOriginsView_Previews: PreviewProvider {
    
    private static let someDate = Date(timeIntervalSince1970: 1_600_000_000)
    
    static var previews: some View {
        Group {
            ListOfTrustOriginsView(trustOrigins: [
                .direct(timestamp: someDate),
                .introduction(timestamp: someDate, mediator: nil),
                .group(timestamp: someDate, groupOwner: nil),
            ])
        }
    }
    
}
