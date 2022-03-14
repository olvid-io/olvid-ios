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
import CloudKit
import Combine

protocol ICloudBackupListViewControllerDelegate: AnyObject {
    func lastCloudBackupForCurrentDeviceWasDeleted()
}


final class ICloudBackupListViewController: UIHostingController<ICloudBackupListView> {

    fileprivate let model: ICloudBackupListViewModel
    init() {
        model = ICloudBackupListViewModel()
        let view = ICloudBackupListView(model: model)
        super.init(rootView: view)
    }

    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var delegate: ICloudBackupListViewControllerDelegate? {
        get { model.delegate }
        set { model.delegate = newValue }
    }

}


fileprivate final class ICloudBackupListViewModel: ObservableObject {

    @Published var lastRecordsCount: Int? = nil
    @Published var recordIterator: AppBackupCoordinator.CKRecordIterator = AppBackupCoordinator.buildAllCloudBackupsIterator()
    @Published var operationInProgress: Bool = false
    @Published var operationError: AppBackupCoordinator.AppBackupError? = nil
    @Published var cleanInProgressCount: Int? = nil
    @Published var cleaningState: Cleaning? = nil

    enum Cleaning {
        case inProgress
        case terminate
    }

    var isFetching: Bool {
        operationInProgress || recordIterator.currentOperation == .initialization || cleaningState == .inProgress
    }

    var isLoadingMoreRecords: Bool {
        recordIterator.currentOperation == .loadMoreRecords
    }

    var error: AppBackupCoordinator.AppBackupError? {
        operationError ?? recordIterator.error
    }

    var records: [CKRecord] {
        recordIterator.records
    }

    var hasMoreRecords: Bool {
        recordIterator.hasMoreRecords
    }

    func loadMoreRecords() {
        recordIterator.loadMoreRecords()
    }

    fileprivate weak var delegate: ICloudBackupListViewControllerDelegate?

    private var anyCancellable: AnyCancellable? = nil
    private var notificationTokens = [NSObjectProtocol]()

    init() {
        anyCancellable = recordIterator.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                withAnimation {
                    self?.objectWillChange.send()
                }
            }
        }
        notificationTokens.append(ObvMessengerInternalNotification.observeIncrementalCleanBackupStarts(queue: OperationQueue.main) { count in
            withAnimation {
                self.cleaningState = .inProgress
                self.cleanInProgressCount = count
            }
        })
        notificationTokens.append(ObvMessengerInternalNotification.observeIncrementalCleanBackupInProgress(queue: OperationQueue.main) { count, _ in
            withAnimation {
                self.cleaningState = .inProgress
                self.cleanInProgressCount = count
            }
        })
        notificationTokens.append(ObvMessengerInternalNotification.observeIncrementalCleanBackupTerminates(queue: OperationQueue.main) { _ in
            withAnimation {
                self.cleaningState = .terminate
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(5), execute: {
                withAnimation {
                    self.cleaningState = nil
                }
            })
            self.update()
        })

    }

    func update() {
        recordIterator.initialize()
    }

    func delete(_ record: CKRecord, isLastForCurrentDevice: Bool) {
        DispatchQueue.main.async {
            withAnimation {
                self.operationInProgress = true
            }
        }
        AppBackupCoordinator.deleteCloudBackup(record: record) { result in
            switch result {
            case .success:
                self.update()
                if isLastForCurrentDevice {
                    self.delegate?.lastCloudBackupForCurrentDeviceWasDeleted()
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    withAnimation {
                        self.operationError = error
                    }
                }
            }
            DispatchQueue.main.async {
                withAnimation {
                    self.operationInProgress = false
                }
            }
        }
    }

    func cleanBackups(cleanAllDevices: Bool) {
        DispatchQueue.main.async {
            withAnimation {
                self.cleaningState = .inProgress
            }
        }
        AppBackupCoordinator.incrementalCleanCloudBackups(cleanAllDevices: cleanAllDevices) { result in
            switch result {
            case .success:
                break
            case .failure(let error):
                DispatchQueue.main.async {
                    withAnimation {
                        self.operationError = error
                    }
                }
            }
            DispatchQueue.main.async {
                withAnimation {
                    self.operationInProgress = false
                }
            }
        }
    }
}


fileprivate enum ICloudBackupListActionSheet: Identifiable {
    case cleanAction
    case cleanLatestAction(_: CKRecord, otherDevice: Bool)

    var id: String {
        switch self {
        case .cleanAction: return "cleanAction"
        case .cleanLatestAction(let record, let otherDevice): return "cleanLatestAction_\(record.recordID.recordName)_\(otherDevice ? "other" : "current")"
        }
    }
}



struct ICloudBackupListView: View {

    @ObservedObject fileprivate var model: ICloudBackupListViewModel
    @State private var actionSheet: ICloudBackupListActionSheet? = nil

    private func numberOfRecordTitle(count: Int, canHaveMoreRecords: Bool) -> String {
        if canHaveMoreRecords {
            return String.localizedStringWithFormat(NSLocalizedString("recent backups count", comment: "Header for n recent backups"), count)
        } else {
            return String.localizedStringWithFormat(NSLocalizedString("backups count", comment: "Header for n backups"), count)
        }
    }

    private func cleanInProgressTitle(count: Int) -> String {
        String.localizedStringWithFormat(NSLocalizedString("clean in progress count", comment: "Header for n backups"), count)
    }


    private var floatingButtonModel: FloatingButtonModel {
        FloatingButtonModel(title: NSLocalizedString("CLEAN_OLD_BACKUPS", comment: ""), systemIcon: .trash, isEnabled: model.records.count > 1 && !model.isFetching) {
            actionSheet = .cleanAction
        }
    }

    func errorView(status: CKAccountStatus) -> some View {
        if let (title, message) = BackupTableViewController.CKAccountStatusMessage(status) {
            return AnyView(VStack {
                Text(title)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.heavy)
                    .lineLimit(1)
                Text(message)
                    .font(.system(.headline, design: .rounded))
                    .multilineTextAlignment(.center)
            })
        } else {
            return AnyView(Text("ERROR"))

        }
    }

    func deleteAction(record: CKRecord) {
        guard let identifierForVendor = UIDevice.current.identifierForVendor else {
            assertionFailure(); return
        }
        var lastRecordsForCurrentDevice: CKRecord?
        var lastRecordsForOtherDevices = [UUID: CKRecord]()

        for record in model.records {
            guard let deviceIdentifierForVendor = record.deviceIdentifierForVendor else { continue }
            if identifierForVendor == deviceIdentifierForVendor {
                if lastRecordsForCurrentDevice == nil {
                    lastRecordsForCurrentDevice = record
                }
            } else {
                if lastRecordsForOtherDevices[deviceIdentifierForVendor] == nil {
                    lastRecordsForOtherDevices[deviceIdentifierForVendor] = record
                }
            }
        }

        if record == lastRecordsForCurrentDevice {
            actionSheet = .cleanLatestAction(record, otherDevice: false)
        } else if lastRecordsForOtherDevices.values.contains(record) {
            actionSheet = .cleanLatestAction(record, otherDevice: true)
        } else {
            model.delete(record, isLastForCurrentDevice: false)
        }
    }

    var recordsList: some View {
        VStack {
            Text(numberOfRecordTitle(count: model.records.count,
                                     canHaveMoreRecords: model.hasMoreRecords || model.isLoadingMoreRecords ))
                .font(.system(.footnote).smallCaps())
            List {
                Section(footer: Rectangle()
                            .frame(height: 60)
                            .foregroundColor(.clear)) {
                    ForEach(model.records, id: \.recordID.recordName) { record in
                        let cell = ICloudBackupView(record: record)
                            .onAppear {
                                if record == model.records.last, model.hasMoreRecords {
                                    model.loadMoreRecords()
                                }
                            }
                        if #available(iOS 15.0, *) {
                            cell
                                .swipeActions {
                                    Button(role: .destructive) {
                                        deleteAction(record: record)
                                    } label: {
                                        Label(CommonString.Word.Delete, systemImage: ObvSystemIcon.trash.systemName)
                                    }
                                }
                        } else {
                            HStack {
                                cell
                                Spacer()
                                Button {
                                    deleteAction(record: record)
                                } label: {
                                    Image(systemIcon: .trash)
                                }
                                .foregroundColor(.red)
                            }
                        }
                    }
                    if model.isLoadingMoreRecords {
                        ObvProgressView()
                            .frame(idealWidth: .infinity, maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .obvListStyle()
            .disabled(model.isFetching || actionSheet != nil)
        }
    }

    var body: some View {
        GeometryReader { proxy in
            if let error = model.error {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        switch error {
                        case .accountError, .operationError:
                            errorView(status: .couldNotDetermine)
                        case .accountNotAvailable(let status):
                            errorView(status: status)
                        }
                        Spacer()
                    }
                    Spacer()
                }
            } else {
                let progressView = ObvProgressView()
                    .foregroundColor(.secondary)
                    .padding()
                ZStack {
                    VStack {
                        if let state = model.cleaningState {
                            VStack {
                                switch state {
                                case .inProgress:
                                    Text("CLEANING_IN_PROGRESS")
                                case .terminate:
                                    Text("CLEANING_TERMINATED")
                                }
                                if let cleanInProgressCount = model.cleanInProgressCount, cleanInProgressCount > 0 {
                                    Text(cleanInProgressTitle(count: cleanInProgressCount))
                                }
                            }
                            .padding()
                            .font(.system(.footnote).smallCaps())
                            .background(Rectangle()
                                            .foregroundColor(.gray)
                                            .frame(width: proxy.size.width, alignment: .center))
                        }
                        recordsList
                    }
                    if model.isFetching {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                if #available(iOS 15.0, *) {
                                    progressView
                                        .background(.ultraThinMaterial)
                                } else {
                                    progressView
                                }
                                Spacer()
                            }
                            Spacer()
                        }
                    }
                    FloatingButtonView(model: floatingButtonModel)
                }
                .actionSheet(item: $actionSheet) { item in
                    switch item {
                    case .cleanAction:
                        var buttons = [ActionSheet.Button]()
                        let devices = Set(model.records.map { record in  record[AppBackupCoordinator.deviceIdentifierForVendorKey] as! String
                        })
                        if model.hasMoreRecords || devices.count > 1 {
                            buttons += [ActionSheet.Button.destructive(Text("CLEAN_OLD_BACKUPS_ON_ALL_DEVICES"),
                                                                       action: {
                                model.cleanBackups(cleanAllDevices: true)
                            })]
                        }
                        buttons += [ActionSheet.Button.default(Text("CLEAN_OLD_BACKUPS_ON_CURRENT_DEVICE"),
                                                               action: {
                            model.cleanBackups(cleanAllDevices: false)
                        })]
                        buttons += [ActionSheet.Button.cancel()]
                        return ActionSheet(title: Text("CLEAN_OLD_BACKUPS_TITLE"),
                                           message: Text("CLEAN_OLD_BACKUPS_MESSAGE"),
                                           buttons: buttons)
                    case .cleanLatestAction(let record, let otherDevice):
                        let title = otherDevice ? Text("CLEAN_LATEST_BACKUPS_FOR_OTHER_DEVICE_TITLE") : Text("CLEAN_LATEST_BACKUPS_FOR_CURRENT_DEVICE_TITLE")
                        let message = otherDevice ? Text("CLEAN_LATEST_BACKUPS_FOR_OTHER_DEVICE_MESSAGE") : Text("CLEAN_LATEST_BACKUPS_FOR_CURRENT_DEVICE_MESSAGE")
                        return ActionSheet(title: title,
                                           message: message,
                                           buttons: [
                                            ActionSheet.Button.default(Text(CommonString.Word.Delete),
                                                                       action: {
                                                                           model.delete(record, isLastForCurrentDevice: !otherDevice)
                                                                           actionSheet = nil
                                                                       }),
                                            ActionSheet.Button.cancel(),
                                           ])
                    }
                }
            }
        }
    }
}


struct ICloudBackupView: View {

    let record: CKRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record[AppBackupCoordinator.deviceNameKey] as! String)
                .font(.system(.headline, design: .rounded))
            HStack {
                if let identifierForVendor = UIDevice.current.identifierForVendor,
                   identifierForVendor.uuidString == record[AppBackupCoordinator.deviceIdentifierForVendorKey] as! String {
                    Text("CURRENT_DEVICE")
                        .font(.system(.callout))
                } else {
                    Text("OTHER_DEVICE")
                        .font(.system(.callout))
                }
                Spacer()
                if let formattedDate = record.creationDate?.relativeFormatted {
                    Text(formattedDate)
                        .font(.system(.callout))
                }
            }
        }
    }

}
