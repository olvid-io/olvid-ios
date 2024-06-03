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


final class DisplayableLogsHostingViewController: UIHostingController<DisplayableLogsListView>, DisplayableLogsViewStoreDelegate {
    
    private let store: DisplayableLogsViewStore
    
    init() {
        self.store = DisplayableLogsViewStore()
        let view = DisplayableLogsListView(store: store)
        super.init(rootView: view)
        self.store.delegate = self
    }
    
    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func shareLogAction(_ logFilename: String) {
        guard let url = ObvDisplayableLogs.shared.getLogNSURL(logFilename) else { return }
        let activityViewController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        self.present(activityViewController, animated: true, completion: nil)
    }
    
}


protocol DisplayableLogsViewStoreDelegate: AnyObject {
    func shareLogAction(_ logFilename: String)
}



final class DisplayableLogsViewStore: ObservableObject {
    
    private(set) var logFilenames: [String]
    @Published var changed: Bool

    weak var delegate: DisplayableLogsViewStoreDelegate?
    
    init() {
        self.logFilenames = (try? ObvDisplayableLogs.shared.getAvailableLogs()) ?? []
        self.changed = true
    }
    
    func getLogContentAction(_ logFilename: String) -> String {
        (try? ObvDisplayableLogs.shared.getContentOfLog(logFilename: logFilename)) ?? ""
    }

    func getSizeOfLogAction(_ logFilename: String) -> String? {
        guard let size = try? ObvDisplayableLogs.shared.getSizeOfLog(logFilename: logFilename) else {
            return nil
        }
        return size.formatted(.byteCount(style: .file, allowedUnits: .all, spellsOutZero: true, includesActualByteCount: false))
    }
    
    func deleteLog(_ logFilename: String) {
        try? ObvDisplayableLogs.shared.deleteLog(logFilename: logFilename)
        self.logFilenames = (try? ObvDisplayableLogs.shared.getAvailableLogs()) ?? []
        self.changed.toggle()
    }
    
    func shareLogAction(_ logFilename: String) {
        delegate?.shareLogAction(logFilename)
    }
    
    func getSingleDisplayableLogView(_ filename: String) -> SingleDisplayableLogView {
        guard let logURL = ObvDisplayableLogs.shared.getLogNSURL(filename) else {
            return SingleDisplayableLogView(logURL: nil)
        }
        return SingleDisplayableLogView(logURL: logURL)
    }
    
}



struct DisplayableLogsListView: View {
    
    @ObservedObject var store: DisplayableLogsViewStore

    var body: some View {
        DisplayableLogsListInnerView(logFilenames: store.logFilenames,
                                     getLogContentAction: store.getLogContentAction,
                                     getSizeOfLogAction: store.getSizeOfLogAction,
                                     deleteLogAction: store.deleteLog,
                                     shareAction: store.shareLogAction,
                                     getSingleDisplayableLogView: store.getSingleDisplayableLogView,
                                     changed: $store.changed)
    }
    
}


struct DisplayableLogsListInnerView: View {
    
    let logFilenames: [String]
    let getLogContentAction: (String) -> String
    let getSizeOfLogAction: (String) -> String?
    let deleteLogAction: (String) -> Void
    let shareAction: (String) -> Void
    let getSingleDisplayableLogView: ((String) -> SingleDisplayableLogView)?
    @Binding var changed: Bool

    var body: some View {
        NavigationView {
            List {
                ForEach(logFilenames, id: \.self) { filename in
                    let navigationLink = NavigationLink {
                        getSingleDisplayableLogView?(filename)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(filename)
                                .font(.body)
                            if let size = getSizeOfLogAction(filename) {
                                Text(size)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    navigationLink.swipeActions {
                        Button(role: .destructive) {
                            deleteLogAction(filename)
                        } label: {
                            Image(systemIcon: .trash)
                        }
                        Button {
                            shareAction(filename)
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



struct DisplayableLogsListInnerView_Previews: PreviewProvider {
    
    private static let logFilenames = [
        "2020-12-18-olvid.log",
        "2020-12-19-olvid.log",
        "2020-12-20-olvid.log",
        "2020-12-21-olvid.log",
        "2020-12-22-olvid.log",
        "2020-12-18-olvid.log",
        "2020-12-19-olvid.log",
        "2020-12-20-olvid.log",
        "2020-12-21-olvid.log",
        "2020-12-22-olvid.log",
        "2020-12-18-olvid.log",
        "2020-12-19-olvid.log",
        "2020-12-20-olvid.log",
        "2020-12-21-olvid.log",
        "2020-12-22-olvid.log",
        "2020-12-18-olvid.log",
        "2020-12-19-olvid.log",
        "2020-12-20-olvid.log",
        "2020-12-21-olvid.log",
        "2020-12-22-olvid.log",
        "2020-12-18-olvid.log",
        "2020-12-19-olvid.log",
        "2020-12-20-olvid.log",
        "2020-12-21-olvid.log",
        "2020-12-22-olvid.log",
        "2020-12-18-olvid.log",
        "2020-12-19-olvid.log",
        "2020-12-20-olvid.log",
        "2020-12-21-olvid.log",
        "2020-12-22-olvid.log",
    ]
    
    static var previews: some View {
        DisplayableLogsListInnerView(logFilenames: logFilenames,
                                     getLogContentAction: { str in str },
                                     getSizeOfLogAction: { str in nil },
                                     deleteLogAction: { _ in },
                                     shareAction: { _ in },
                                     getSingleDisplayableLogView: nil,
                                     changed: .constant(false))
    }
}
