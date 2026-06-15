/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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


/// View used both in `LocalNetworkImportView` and in `ZipImportView`.
struct ReceivingDiscussionsListStatusView: View {

    let receivingDiscussionsListStatus: ReceivingDiscussionsListStatus
    let showLine: Bool
    let transferMethod: TransferMethod
    
    private var progressItemState: ProgressItemState {
        switch receivingDiscussionsListStatus {
        case .inProgress:
            return .inProgress
        case .done:
            return .success
        }
    }

    private var subtitle: String {
        switch receivingDiscussionsListStatus {
        case .inProgress:
            return String(localizedInThisBundle: "RECEIVING_DISCUSSION_LIST_01_IN_PROGRESS")
        case .done:
            switch transferMethod {
            case .webRTC, .wifiAware:
                return String(localizedInThisBundle: "RECEIVING_DISCUSSION_LIST_01_FOUND")
            case .zip:
                return String(localizedInThisBundle: "RECEIVING_DISCUSSION_LIST_01_FOUND_IN_ZIP")
            }
        }
    }

    private var subtitleDiscussions: String? {
        switch receivingDiscussionsListStatus {
        case .inProgress:
            return nil
        case .done(numberOfDiscussionsAvailableOnSource: let numberOfDiscussionsAvailableOnSource, numberOfFylesAvailableOnSource: _, totalByteCountAvailableOnSource: _):
            return String(localizedInThisBundle: "RECEIVING_DISCUSSION_LIST_01_FOUND_\(numberOfDiscussionsAvailableOnSource)_DISCUSSIONS")
        }
    }

    private var subtitleAttachments: String? {
        switch receivingDiscussionsListStatus {
        case .inProgress:
            return nil
        case .done(numberOfDiscussionsAvailableOnSource: _, numberOfFylesAvailableOnSource: let numberOfFylesAvailableOnSource, totalByteCountAvailableOnSource: let totalByteCountAvailableOnSource):
            guard numberOfFylesAvailableOnSource > 0 else { return nil }
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useKB, .useMB, .useGB]
            formatter.countStyle = .decimal // 1 KB = 1000 bytes, conventional for transfer rates
            let formattedBytes = formatter.string(fromByteCount: Int64(totalByteCountAvailableOnSource))
            return String(localizedInThisBundle: "RECEIVING_DISCUSSION_LIST_01_FOUND_\(numberOfFylesAvailableOnSource)_ATTACHMENTS_FOR_A_TOTAL_OF_\(formattedBytes)")
        }
    }

    private var title: String {
        switch (transferMethod, receivingDiscussionsListStatus) {
        case (.webRTC, .inProgress), (.wifiAware, .inProgress):
            return String(localizedInThisBundle: "FETCHING_DISCUSSION_LIST_TITLE")
        case (.webRTC, .done), (.wifiAware, .done):
            return String(localizedInThisBundle: "FETCHING_DISCUSSION_LIST_TITLE_DONE")
        case (.zip, .inProgress):
            return String(localizedInThisBundle: "FETCHING_DISCUSSION_LIST_TITLE_ZIP")
        case (.zip, .done):
            return String(localizedInThisBundle: "FETCHING_DISCUSSION_LIST_TITLE_ZIP_DONE")
        }
    }

    var body: some View {
        ProgressItemRowView(state: progressItemState,
                            showLine: showLine,
                            title: title) {
            Text(subtitle)
            if let subtitleDiscussions {
                Label(title: { Text(subtitleDiscussions) }, icon: { Image(systemIcon: .circleFill) })
                    .labelStyle(BulletLabelStyle())
            }
            if let subtitleAttachments {
                Label(title: { Text(subtitleAttachments) }, icon: { Image(systemIcon: .circleFill) })
                    .labelStyle(BulletLabelStyle())
            }
        }
    }

}
