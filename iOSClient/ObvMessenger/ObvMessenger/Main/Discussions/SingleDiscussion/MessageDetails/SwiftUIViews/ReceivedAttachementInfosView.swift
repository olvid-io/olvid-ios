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


struct AllReceivedFyleMessageJoinWithStatusView: View {
    
    let allReceivedFyleMessageJoinWithStatus: [ReceivedFyleMessageJoinWithStatus]

    var body: some View {
        if !allReceivedFyleMessageJoinWithStatus.isEmpty {
            Section(header: Text("ATTACHMENTS_INFO")) {
                ForEach(allReceivedFyleMessageJoinWithStatus) { attachmentInfo in
                    ReceivedFyleMessageJoinWithStatusView(receivedFyleMessageJoinWithStatus: attachmentInfo)
                }
            }
        }
    }
    
}


fileprivate extension ReceivedFyleMessageJoinWithStatus {
    
    var systemIcon: ObvSystemIcon {
        switch self.status {
        case .downloadable: return .arrowDownCircle
        case .downloading: return .arrowDownCircle
        case .complete: return .arrowDownCircleFill
        case .cancelledByServer: return .exclamationmarkCircle
        }
    }
    
    var isProgressShown: Bool {
        switch self.status {
        case .downloading: return true
        case .downloadable, .complete, .cancelledByServer: return false
        }
    }
    
    var estimatedTimeRemainingString: String {
        let defaultString = NSLocalizedString("ESTIMATING_TIME_REMAINING", comment: "")
        if self.estimatedTimeRemaining == 0 {
            return defaultString
        } else {
            return FyleMessageJoinWithStatus.formatterForEstimatedTimeRemaining.string(from: self.estimatedTimeRemaining) ?? defaultString
        }
    }

}


struct ReceivedFyleMessageJoinWithStatusView: View {
    
    @ObservedObject var receivedFyleMessageJoinWithStatus: ReceivedFyleMessageJoinWithStatus
    
    private var systemIcon: ObvSystemIcon {
        receivedFyleMessageJoinWithStatus.systemIcon
    }
    
    private var filename: String {
        receivedFyleMessageJoinWithStatus.fileName
    }
    
    private var isProgressShown: Bool {
        receivedFyleMessageJoinWithStatus.isProgressShown
    }
    
    private var estimatedTimeRemainingString: String {
        receivedFyleMessageJoinWithStatus.estimatedTimeRemainingString
    }
    
    private var fractionCompleted: Double {
        receivedFyleMessageJoinWithStatus.fractionCompleted
    }
    
    private var throughput: Int {
        receivedFyleMessageJoinWithStatus.throughput
    }
    
    @available(iOS 15, *)
    private var formattedThroughput: String {
        throughput.formatted(.byteCount(style: .file, allowedUnits: [.gb, .mb, .kb], spellsOutZero: false, includesActualByteCount: false)) + "/s"
    }
    
    var body: some View {
        // The ObvLabelAlt view is replicated to prevent an animation glitch when the progress disappears
        if #available(iOS 15, *), isProgressShown {
            VStack(alignment: .leading) {
                ObvLabelAlt(title: filename, systemIcon: systemIcon)
                VStack(alignment: .leading) {
                    ProgressView(value: fractionCompleted)
                    HStack {
                        Text(estimatedTimeRemainingString)
                        Spacer()
                        Text(formattedThroughput)
                    }
                    .font(.footnote)
                    .foregroundColor(Color(.secondaryLabel))
                }.padding(.leading, 44) // 44 is a magic number allowing to (tentatively) align the progress bar with the label's text
            }
        } else {
            ObvLabelAlt(title: filename, systemIcon: systemIcon)
        }
    }
    
}
