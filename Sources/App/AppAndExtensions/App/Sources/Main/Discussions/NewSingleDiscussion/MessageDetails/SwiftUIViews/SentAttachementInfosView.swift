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


import ObvUI
import ObvUICoreData
import SwiftUI
import ObvSystemIcon


struct AllSentFyleMessageJoinWithStatusView: View {
    
    let allSentFyleMessageJoinWithStatus: [SentFyleMessageJoinWithStatus]

    var body: some View {
        if !allSentFyleMessageJoinWithStatus.isEmpty {
            Section(header: Text("ATTACHMENTS_INFO")) {
                ForEach(allSentFyleMessageJoinWithStatus) { attachmentInfo in
                    SentFyleMessageJoinWithStatusView(sentFyleMessageJoinWithStatus: attachmentInfo)
                }
            }
        }
    }
    
}


fileprivate extension SentFyleMessageJoinWithStatus {
    
    var isProgressShown: Bool {
        switch self.status {
        case .uploadable, .uploading, .downloading:
            return true
        case .complete, .downloadable, .cancelledByServer:
            return false
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


struct SentFyleMessageJoinWithStatusView: View {

    @ObservedObject var sentFyleMessageJoinWithStatus: SentFyleMessageJoinWithStatus
    
    private var filename: String {
        sentFyleMessageJoinWithStatus.fileName
    }
    
    private var symbolIcon: any SymbolIcon {
        return sentFyleMessageJoinWithStatus.getSymbolIcon()
    }

    private var isProgressShown: Bool {
        sentFyleMessageJoinWithStatus.isProgressShown
    }
    
    private var estimatedTimeRemainingString: String {
        sentFyleMessageJoinWithStatus.estimatedTimeRemainingString
    }

    private var fractionCompleted: Double {
        sentFyleMessageJoinWithStatus.fractionCompleted
    }

    private var throughput: Int {
        sentFyleMessageJoinWithStatus.throughput
    }

    private var formattedThroughput: String {
        throughput.formatted(.byteCount(style: .file, allowedUnits: [.gb, .mb, .kb], spellsOutZero: false, includesActualByteCount: false)) + "/s"
    }

    private var attachmentInfosForThisSentFyleMessageJoinWithStatusView: [PersistedAttachmentSentRecipientInfos] {
        return sentFyleMessageJoinWithStatus.sentMessage.unsortedRecipientsInfos
            .sorted(by: { $0.recipientName < $1.recipientName })
            .compactMap { recipientsInfos in
                recipientsInfos.attachmentInfos.first(where: {
                    $0.index == sentFyleMessageJoinWithStatus.index
                })
        }
    }
        
    var body: some View {
        NavigationLink {
            AllPersistedAttachmentSentRecipientInfosView(
                filename: filename,
                allPersistedAttachmentSentRecipientInfos: attachmentInfosForThisSentFyleMessageJoinWithStatusView)
        } label: {
            // The ObvLabelAlt view is replicated to prevent an animation glitch when the progress disappears
            if isProgressShown {
                VStack(alignment: .leading) {
                    ObvLabelAlt(verbatim: filename, symbolIcon: symbolIcon)
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
                ObvLabelAlt(verbatim: filename, symbolIcon: symbolIcon)
            }
        }
    }
    
}


struct AllPersistedAttachmentSentRecipientInfosView: View {
    
    let filename: String
    let allPersistedAttachmentSentRecipientInfos: [PersistedAttachmentSentRecipientInfos]

    var body: some View {
        if !allPersistedAttachmentSentRecipientInfos.isEmpty {
            List {
                Section(header: Text(filename)) {
                    ForEach(allPersistedAttachmentSentRecipientInfos) { infos in
                        PersistedAttachmentSentRecipientInfosView(persistedAttachmentSentRecipientInfos: infos)
                    }
                }
            }
        }
    }
        
}


struct PersistedAttachmentSentRecipientInfosView: View {
    
    @ObservedObject var persistedAttachmentSentRecipientInfos: PersistedAttachmentSentRecipientInfos

    private var name: String {
        persistedAttachmentSentRecipientInfos.messageInfo?.recipientName ?? ""
    }
    
    private var systemIcon: any SymbolIcon {
        persistedAttachmentSentRecipientInfos.status.getSymbolIcon()
    }
    
    var body: some View {
        ObvLabelAlt(verbatim: name, symbolIcon: systemIcon)
    }
    
}
