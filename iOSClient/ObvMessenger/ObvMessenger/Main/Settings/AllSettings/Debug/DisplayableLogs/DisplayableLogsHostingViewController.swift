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


@available(iOS 13, *)
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


@available(iOS 13, *)
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
    
    func deleteLog(_ indexSet: IndexSet) {
        for index in indexSet {
            let logFilename = logFilenames[index]
            try? ObvDisplayableLogs.shared.deleteLog(logFilename: logFilename)
            self.logFilenames = (try? ObvDisplayableLogs.shared.getAvailableLogs()) ?? []
            self.changed.toggle()
        }
    }
    
    func shareLogAction(_ logFilename: String) {
        delegate?.shareLogAction(logFilename)
    }
}


@available(iOS 13, *)
struct DisplayableLogsListView: View {
    
    @ObservedObject var store: DisplayableLogsViewStore

    var body: some View {
        DisplayableLogsListInnerView(logFilenames: store.logFilenames,
                                     getLogContentAction: store.getLogContentAction,
                                     deleteLogAction: store.deleteLog,
                                     shareAction: store.shareLogAction,
                                     changed: $store.changed)
    }
    
}

@available(iOS 13, *)
struct DisplayableLogsListInnerView: View {
    
    let logFilenames: [String]
    let getLogContentAction: (String) -> String
    let deleteLogAction: (IndexSet) -> Void
    let shareAction: (String) -> Void
    @Binding var changed: Bool

    var body: some View {
        NavigationView {
            List {
                ForEach(logFilenames, id: \.self) { filename in
                    NavigationLink(destination: SingleDisplayableLogView(content: getLogContentAction(filename), shareAction: { shareAction(filename) })) {
                        HStack {
                            Text(filename)
                                .font(.body)
                        }
                    }
                }
                .onDelete(perform: deleteLogAction)
            }
            .navigationBarTitle("All logs", displayMode: .inline)
        }
    }
}


@available(iOS 13, *)
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
                                     deleteLogAction: { _ in },
                                     shareAction: { _ in },
                                     changed: .constant(false))
    }
}
