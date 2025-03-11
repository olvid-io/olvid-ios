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
import OlvidUtils


final class DisplayableLogsHostingViewController: UIHostingController<DisplayableLogsListView<DisplayableLogsViewStore>>, DisplayableLogsViewStoreDelegate {
    
    private let store: DisplayableLogsViewStore
    
    init() {
        self.store = DisplayableLogsViewStore()
        let view = DisplayableLogsListView(model: store, actions: store)
        super.init(rootView: view)
        self.store.delegate = self
    }
    
    
    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func shareLogAction(_ log: NSURL) {
        let activityViewController = UIActivityViewController(activityItems: [log], applicationActivities: nil)
        // The following check allows to prevent a crash under iPad
        if activityViewController.popoverPresentationController?.sourceView == nil {
            activityViewController.popoverPresentationController?.sourceView = self.view
        }
        self.present(activityViewController, animated: true, completion: nil)
    }
    
}


protocol DisplayableLogsViewStoreDelegate: AnyObject {
    func shareLogAction(_ log: NSURL)
}


@MainActor
final class DisplayableLogsViewStore: ObservableObject, DisplayableLogsListViewModel {
    
    @Published private(set) var logs: [NSURL]

    weak var delegate: DisplayableLogsViewStoreDelegate?
    
    init() {
        self.logs = []
        Task {
            let logs = await (try? ObvDisplayableLogs.shared.getAvailableLogs()) ?? []
            self.logs = logs
        }
    }

}

extension DisplayableLogsViewStore: DisplayableLogsListViewActionsProtocol {
    
    func getSingleDisplayableLogView(_ log: NSURL) -> SingleDisplayableLogView {
        return SingleDisplayableLogView(logURL: log)
    }

    
    func getSizeOfLog(_ log: NSURL) -> String? {
        guard let path = log.path else { assertionFailure(); return nil }
        guard let fileAttributes = try? FileManager.default.attributesOfItem(atPath: path) else { assertionFailure(); return nil }
        guard let size = fileAttributes[FileAttributeKey.size] as? Int64 else { assertionFailure(); return nil }
        return size.formatted(.byteCount(style: .file, allowedUnits: .all, spellsOutZero: true, includesActualByteCount: false))
    }

    
    func deleteLog(_ log: NSURL) async {
        try? FileManager.default.removeItem(at: log as URL)
        self.logs = await (try? ObvDisplayableLogs.shared.getAvailableLogs()) ?? []
    }

    
    func shareLog(_ log: NSURL) {
        assert(delegate != nil)
        delegate?.shareLogAction(log)
    }
    
}


@MainActor
protocol DisplayableLogsListViewModel: ObservableObject {
    var logs: [NSURL] { get }
}


protocol DisplayableLogsListViewActionsProtocol {
    @MainActor func getSingleDisplayableLogView(_ log: NSURL) -> SingleDisplayableLogView
    @MainActor func getSizeOfLog(_ log: NSURL) -> String?
    func deleteLog(_ log: NSURL) async
    @MainActor func shareLog(_ log: NSURL)
}


struct DisplayableLogsListView<Model: DisplayableLogsListViewModel>: View {
    
    @ObservedObject var model: Model
    let actions: DisplayableLogsListViewActionsProtocol
        
    var body: some View {
        NavigationView {
            List {
                ForEach(model.logs, id: \.self) { log in
                    let navigationLink = NavigationLink {
                        actions.getSingleDisplayableLogView(log)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(log.lastPathComponent ?? "-")
                                .font(.body)
                            if let size = actions.getSizeOfLog(log) {
                                Text(size)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    navigationLink.swipeActions {
                        Button(role: .destructive) {
                            Task { await actions.deleteLog(log) }
                        } label: {
                            Image(systemIcon: .trash)
                        }
                        Button {
                            actions.shareLog(log)
                        } label: {
                            Image(systemIcon: .squareAndArrowUp)
                        }
                    }
                }
            }
            .navigationBarTitle("All logs", displayMode: .inline)
        }
    }
    
}
