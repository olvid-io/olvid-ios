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
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Affero General Public License for more details.
 *
 *  You should have received a copy of the GNU Affero General Public License
 *  along with Olvid.  If not, see <https://www.gnu.org/licenses/>.
 */

import SwiftUI
import UniformTypeIdentifiers


/// 2023-02-16 This view controller was coded to display a log during the debugging of the coordinators queue. To be deleted in a near future, together with the notifications testflightUserWantsToDebugCoordinatorsQueue and testflightUserWantsToSeeLogString
final class DebugLogStringViewerViewController: UIHostingController<DebugLogStringViewerView> {
    
    init(logString: String) {
        let view = DebugLogStringViewerView(logString: logString)
        super.init(rootView: view)
    }
    
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}


struct DebugLogStringViewerView: View {
    
    let logString: String
    
    var body: some View {
        ScrollView {
            VStack {
                HStack {
                    Text(logString)
                        .font(.body)
                    Spacer()
                }
                Spacer()
            }.padding()
        }
        .onTapGesture(count: 1) {
            UIPasteboard.general.setValue(logString, forPasteboardType: UTType.plainText.identifier)
            let impactHeavy = UIImpactFeedbackGenerator(style: .medium)
            impactHeavy.impactOccurred()
        }
    }
    
}
