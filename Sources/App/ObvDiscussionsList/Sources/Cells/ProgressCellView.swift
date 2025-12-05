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
import ObvAppCoreConstants

@MainActor
public protocol ProgressCellViewDataSource: AnyObject, Sendable {
    func getAsyncStreamOfCoordinatorsProgress(_ view: ObvDiscussionsListView) throws -> (streamUUID: UUID, stream: AsyncStream<Double>)
    func finishAsyncStreamOfCoordinatorsProgress(_ view: ObvDiscussionsListView, streamUUID: UUID)
}


struct ProgressCellView: View {
    
    let fractionCompleted: Double
    
    var body: some View {
        VStack(alignment: .leading) {
            ProgressView(value: fractionCompleted)
                .progressViewStyle(LinearProgressViewStyle())
            //.labelsHidden()
            Text("Please hold on, we're working hard in the background to get everything ready for you!")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
    
}
