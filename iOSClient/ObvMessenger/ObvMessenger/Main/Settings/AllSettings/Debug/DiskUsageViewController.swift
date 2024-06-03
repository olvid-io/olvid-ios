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
import ObvSettings
import ObvDesignSystem


final class DiskUsageViewController: UIHostingController<DiskUsageView> {

    private let model: DiskUsageModel

    init() {
        self.model = DiskUsageModel()
        let view = DiskUsageView(model: model)
        super.init(rootView: view)
    }

    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

}


fileprivate class DiskUsageModel: ObservableObject {

    // On Database
    @Published var databaseInfo: DirectoryInfo

    // On App
    @Published var appDirectoryInfos: [URL: DirectoryInfo] = [:]

    // On Engine
    @Published var engineDirectoryInfos: [URL: DirectoryInfo] = [:]
    
    /// Background queue on which we compute the various directory sizes and element counts.
    private let backgroundQueue = OperationQueue()
    
    init() {
        // Database
        self.databaseInfo = DirectoryInfo(title: NSLocalizedString("ATTACHMENTS_INFO", comment: ""), subtitle: nil, computationStatus: .computing)
        ObvStack.shared.performBackgroundTask { context in
            let newStatus: DirectoryInfo.ComputationStatus
            do {
                let allFyles = try Fyle.getAll(within: context)
                let fylesCount = allFyles.count
                let totalSize = allFyles.reduce(0) { $0 + ($1.getFileSize() ?? 0) }
                newStatus = .computed(size: totalSize, count: fylesCount)
            } catch {
                newStatus = .failed
            }
            DispatchQueue.main.async { [weak self] in
                withAnimation {
                    self?.databaseInfo = DirectoryInfo(title: NSLocalizedString("ATTACHMENTS_INFO", comment: ""), subtitle: nil, computationStatus: newStatus)
                }
            }
        }

        for containerURL in ObvUICoreDataConstants.ContainerURL.allCases {
            let url = containerURL.url
            let info = DirectoryInfo(title: containerURL.title, subtitle: containerURL.subtitle, computationStatus: .computing)
            appDirectoryInfos[url] = info
            backgroundQueue.addOperation {
                let newStatus: DirectoryInfo.ComputationStatus
                do {
                    if let size = FileManager.default.directorySize(url) {
                        let count = FileManager.default.directoryCount(url)
                        newStatus = .computed(size: size, count: count)
                    } else {
                        newStatus = .failed
                    }
                }
                let newInfo = DirectoryInfo(title: containerURL.title, subtitle: containerURL.subtitle, computationStatus: newStatus)
                DispatchQueue.main.async { [weak self] in
                    withAnimation {
                        self?.appDirectoryInfos[url] = newInfo
                    }
                }
            }
        }
                

        for name in ["inbox", "outbox", "database", "identityPhotos", "downloadedUserData", "uploadingUserData"] {
            let url = ObvUICoreDataConstants.ContainerURL.mainEngineContainer.url.appendingPathComponent(name, isDirectory: true)
            let info = DirectoryInfo(title: name.capitalized, subtitle: nil, computationStatus: .computing)
            engineDirectoryInfos[url] = info
            backgroundQueue.addOperation {
                let newStatus: DirectoryInfo.ComputationStatus
                do {
                    if let size = FileManager.default.directorySize(url) {
                        let count = FileManager.default.directoryCount(url)
                        newStatus = .computed(size: size, count: count)
                    } else {
                        newStatus = .failed
                    }
                }
                let newInfo = DirectoryInfo(title: name.capitalized, subtitle: nil, computationStatus: newStatus)
                DispatchQueue.main.async { [weak self] in
                    withAnimation {
                        self?.engineDirectoryInfos[url] = newInfo
                    }
                }
            }
        }

    }
}

fileprivate struct DirectoryInfo {
    
    enum ComputationStatus {
        case computing
        case computed(size: Int64, count: Int?)
        case failed
    }
    
    let title: String
    let subtitle: String?
    let computationStatus: ComputationStatus

}

struct DiskUsageView: View {

    private func compareURL(url1: URL, url2: URL) -> Bool {
        return url1.absoluteString < url2.absoluteString
    }

    @ObservedObject fileprivate var model: DiskUsageModel

    private func elementCountFormatter(_ count: Int) -> String {
        return String.localizedStringWithFormat(NSLocalizedString("NUMBER_OF_ELEMENTS", comment: ""), count)
    }

    fileprivate func diskInfoView(_ info: DirectoryInfo) -> some View {
        DiskInfoView(info: info,
                     elementCountFormatter: elementCountFormatter)
    }

    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("About")) {
                    Text("ABOUT_DISKUSAGEVIEW_\(UIDevice.current.model)")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                Section(header: Text("REFERENCED_BY_DATABASE")) {
                    DiskInfoView(info: model.databaseInfo, elementCountFormatter: elementCountFormatter)
                }
                Section(header: Text("APP_DIRECTORIES")) {
                    ForEach(model.appDirectoryInfos.keys.sorted(by: compareURL), id: \.self) { url in
                        if let info = model.appDirectoryInfos[url] {
                            diskInfoView(info)
                        }
                    }
                }
                Section(header: Text("ENGINE_DIRECTORIES")) {
                    ForEach(model.engineDirectoryInfos.keys.sorted(by: compareURL), id: \.self) { url in
                        if let info = model.engineDirectoryInfos[url] {
                            diskInfoView(info)
                        }
                    }
                }
            }
            .navigationBarTitle(Text("DISK_USAGE"), displayMode: .inline)
            .navigationBarItems(leading: Button(action: { presentationMode.wrappedValue.dismiss() }, label: {
                Image(systemIcon: .xmarkCircleFill)
                    .font(Font.system(size: 24, weight: .semibold, design: .default))
                    .foregroundColor(Color(AppTheme.shared.colorScheme.tertiaryLabel))
            }))
        }
    }
}

private struct DiskInfoView: View {

    let info: DirectoryInfo
    let elementCountFormatter: (Int) -> String
    
    private var titleView: some View {
        VStack(alignment: .leading) {
            Text(info.title)
                .lineLimit(1)
            if let subtitle = info.subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var valueView: some View {
        switch info.computationStatus {
        case .computing:
            ProgressView()
        case .failed:
            Image(systemIcon: .exclamationmarkCircle)
        case .computed(size: let size, count: let count):
            VStack(alignment: .trailing) {
                Text(size.formatted(.byteCount(style: .file, allowedUnits: .all, spellsOutZero: true, includesActualByteCount: false)))
                if let count = count {
                    Text(elementCountFormatter(count))
                }
            }
            .font(.footnote)
        }
    }

    var body: some View {
        HStack {
            titleView
            Spacer()
            valueView
                .foregroundColor(.secondary)
        }
    }
}

fileprivate extension URL {
    var fileSize: Int64? {
        do {
            let val = try self.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            guard let size = val.totalFileAllocatedSize ?? val.fileAllocatedSize else {
                return nil
            }
            return Int64(size)
        } catch {
            return nil
        }
    }
}

fileprivate extension FileManager {
    func directorySize(_ dir: URL) -> Int64? {
        guard let enumerator = self.enumerator(at: dir, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey], options: [], errorHandler: { (_, error) -> Bool in
            return false
        }) else {
            return nil
        }
        var bytes: Int64 = 0
        for case let url as URL in enumerator {
            bytes += url.fileSize ?? 0
        }
        return bytes
    }

    func directoryCount(_ dir: URL) -> Int? {
        guard let contents = try? self.contentsOfDirectory(atPath: dir.path) else {
            return nil
        }
        return contents.count

    }
}
