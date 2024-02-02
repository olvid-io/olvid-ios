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

import CloudKit
import Combine
import ObvUI
import SwiftUI
import ObvUICoreData
import UI_SystemIcon
import UI_SystemIcon_SwiftUI
import ObvDesignSystem


protocol ICloudBackupListViewControllerDelegate: AnyObject {
    func lastCloudBackupForCurrentDeviceWasDeleted()
}


final class ICloudBackupListViewController: UIHostingController<ICloudBackupListView> {

    fileprivate let model: ICloudBackupListViewModel
    init(appBackupDelegate: AppBackupDelegate?) {
        model = ICloudBackupListViewModel(appBackupDelegate: appBackupDelegate)
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

    weak var appBackupDelegate: AppBackupDelegate?

    private var recordIterator: CloudKitBackupRecordIterator

    @Published var lastRecordsCount: Int? = nil
    @Published var operationInProgress: Bool = false
    @Published var cleaningState: Cleaning? = nil

    @Published var records: [CKRecord] = []
    @Published var error: CloudKitError? = nil
    @Published var isLoadingMoreRecords: Bool = false
    @Published var iteratorHasMoreRecords: Bool = false
    @Published var deletingRecords: Set<CKRecord> = Set()

    @Published var fractionCompleted: Double?
    @Published var estimatedTimeRemainingString: String?
    @Published var fractionCompletedString: String?

    private var timerForRefreshingCleaningProgress: Timer?

    enum Cleaning {
        case inProgress
        case terminate
    }

    fileprivate weak var delegate: ICloudBackupListViewControllerDelegate?

    var cancellable = Set<AnyCancellable>()
    private var notificationTokens = [NSObjectProtocol]()

    init(appBackupDelegate: AppBackupDelegate?) {
        self.appBackupDelegate = appBackupDelegate
        self.recordIterator = CloudKitBackupRecordIterator(resultsLimit: nil,
                                                           desiredKeys: [.deviceName, .deviceIdentifierForVendor])
        self.loadMoreRecords(appendResult: false)

        notificationTokens.append(ObvMessengerInternalNotification.observeIncrementalCleanBackupStarts(queue: OperationQueue.main) {
            withAnimation {
                self.cleaningState = .inProgress
                Task {
                    await self.updateProgress()
                }
                guard self.timerForRefreshingCleaningProgress == nil else { return }
                self.timerForRefreshingCleaningProgress = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
                    guard timer.isValid else { return }
                    assert(Thread.isMainThread)
                    Task {
                        await self.updateProgress()
                    }
                }
            }
        })
        notificationTokens.append(ObvMessengerInternalNotification.observeIncrementalCleanBackupTerminates(queue: OperationQueue.main) {
            withAnimation {
                self.cleaningState = .terminate
                self.timerForRefreshingCleaningProgress?.invalidate()
                self.timerForRefreshingCleaningProgress = nil
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(5), execute: {
                withAnimation {
                    self.cleaningState = nil
                }
            })
            self.recordIterator = CloudKitBackupRecordIterator(resultsLimit: nil,
                                                               desiredKeys: [.deviceName, .deviceIdentifierForVendor])
            // Load results from iterator and remove current records
            self.loadMoreRecords(appendResult: false)
        })
    }
    
    deinit {
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    var isFetching: Bool {
        operationInProgress || cleaningState == .inProgress
    }

    func updateProgress() async {
        guard let cleaningProgress = await appBackupDelegate?.cleaningProgress else {
            DispatchQueue.main.async {
                withAnimation {
                    self.fractionCompleted = nil
                    self.estimatedTimeRemainingString = nil
                    self.fractionCompletedString = nil
                }
            }
            return
        }
        let fractionCompleted = Double(cleaningProgress.completedUnitCount) / Double(cleaningProgress.totalUnitCount)
        let estimatedTimeRemainingString: String
        let defaultString = NSLocalizedString("ESTIMATING_TIME_REMAINING", comment: "")
        if let estimatedTimeRemaining = cleaningProgress.estimatedTimeRemaining, estimatedTimeRemaining > 0 {
            estimatedTimeRemainingString = Self.formatterForEstimatedTimeRemaining.string(from: estimatedTimeRemaining) ?? defaultString
        } else {
            estimatedTimeRemainingString = defaultString
        }
        let fractionCompletedString = Self.formatterForProgressPercent.string(from: NSNumber(value: fractionCompleted))

        DispatchQueue.main.async {
            withAnimation {
                self.fractionCompleted = fractionCompleted
                self.estimatedTimeRemainingString = estimatedTimeRemainingString
                self.fractionCompletedString = fractionCompletedString
            }
        }
    }

    static let formatterForEstimatedTimeRemaining: DateComponentsFormatter = {
        let dcf = DateComponentsFormatter()
        dcf.unitsStyle = .short
        dcf.includesApproximationPhrase = true
        dcf.includesTimeRemainingPhrase = true
        dcf.allowedUnits = [.day, .hour, .minute, .second]
        return dcf
    }()

    static let formatterForProgressPercent: NumberFormatter = {
        let nf = NumberFormatter()
        nf.numberStyle = .percent
        nf.minimumIntegerDigits = 0
        nf.maximumIntegerDigits = 3
        nf.maximumFractionDigits = 0
        return nf
    }()

    func loadMoreRecords(appendResult: Bool) {
        DispatchQueue.main.async {
            withAnimation {
                self.isLoadingMoreRecords = true
            }
        }
        Task {
            if let hasNext = recordIterator.hasNext, !hasNext {
                // No more results
                return
            }
            do {
                // Compute the next batch of record
                guard let nextRecords = try await recordIterator.next() else {
                    assertionFailure()
                    return
                }
                // Look if there is more results to load
                let iteratorHasMoreRecords = recordIterator.hasNext ?? true // Should never be nil since next was called at least once
                DispatchQueue.main.async {
                    withAnimation {
                        if appendResult {
                            self.records += nextRecords
                        } else {
                            self.records = nextRecords
                        }
                        self.isLoadingMoreRecords = false
                        self.iteratorHasMoreRecords = iteratorHasMoreRecords
                    }
                }
            } catch(let error) {
                // Look if there is more results to load
                let iteratorHasMoreRecords = recordIterator.hasNext ?? true // Should never be nil since next was
                DispatchQueue.main.async {
                    withAnimation {
                        let error = error as? CloudKitError ?? .unknownError(error)
                        self.error = error
                        self.isLoadingMoreRecords = false
                        self.iteratorHasMoreRecords = iteratorHasMoreRecords
                    }
                }
            }
        }
    }

    func delete(_ record: CKRecord, isLastForCurrentDevice: Bool) {
        DispatchQueue.main.async {
            withAnimation {
                self.operationInProgress = true
                self.deletingRecords.insert(record)
            }
        }
        Task {
            do {
                try await appBackupDelegate?.deleteCloudBackup(record: record)
                DispatchQueue.main.async {
                    withAnimation {
                        self.records.removeAll { $0 == record }
                    }
                }
                if isLastForCurrentDevice {
                    self.delegate?.lastCloudBackupForCurrentDeviceWasDeleted()
                }
            } catch(let error) {
                DispatchQueue.main.async {
                    withAnimation {
                        self.error = error as? CloudKitError ?? .unknownError(error)
                    }
                }
            }
            DispatchQueue.main.async {
                withAnimation {
                    self.deletingRecords.remove(record)
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
        Task {
            do {
                try await appBackupDelegate?.checkAccount()
                ObvMessengerInternalNotification.userWantsToStartIncrementalCleanBackup(cleanAllDevices: cleanAllDevices).postOnDispatchQueue()
            } catch(let error) {
                DispatchQueue.main.async {
                    withAnimation {
                        self.error = error as? CloudKitError ?? .unknownError(error)
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
            return String(format: NSLocalizedString("recent backups count", comment: "Header for n recent backups"), count)
        } else {
            return String(format: NSLocalizedString("BACKUP_%llu_COUNT", comment: "Header for n backups"), count)
        }
    }

    private func cleanInProgressTitle(count: Int64) -> String {
        return String(format: NSLocalizedString("%lld_DELETED_BACKUPS", comment: ""), count)
    }


    private var floatingButtonModel: FloatingButtonModel {
        FloatingButtonModel(title: NSLocalizedString("CLEAN_OLD_BACKUPS", comment: ""), systemIcon: .trash, isEnabled: model.records.count > 1 && !model.isFetching) {
            actionSheet = .cleanAction
        }
    }

    func errorView(status: CKAccountStatus) -> some View {
        if let (title, message) = AppBackupManager.CKAccountStatusMessage(status) {
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
                                     canHaveMoreRecords: model.iteratorHasMoreRecords || model.isLoadingMoreRecords ))
                .font(.system(.footnote).smallCaps())
            List {
                Section(footer: Rectangle()
                            .frame(height: 60)
                            .foregroundColor(.clear)) {
                    ForEach(model.records, id: \.recordID.recordName) { record in
                        let cell = RecordView(record: record,
                                              isDeleting: model.deletingRecords.contains(record))
                            .onAppear {
                                if record == model.records.last, model.iteratorHasMoreRecords {
                                    model.loadMoreRecords(appendResult: true)
                                }
                            }
                        cell
                            .swipeActions {
                                Button(role: .destructive) {
                                    deleteAction(record: record)
                                } label: {
                                    Label(CommonString.Word.Delete, systemImage: SystemIcon.trash.systemName)
                                }
                            }
                    }
                    if model.isLoadingMoreRecords {
                        ProgressView()
                            .frame(idealWidth: .infinity, maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
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
                        case .accountError, .operationError, .unknownError, .internalError:
                            errorView(status: .couldNotDetermine)
                        case .accountNotAvailable(let status):
                            errorView(status: status)
                        }
                        Spacer()
                    }
                    Spacer()
                }
            } else {
                let progressView = ProgressView()
                    .foregroundColor(.secondary)
                    .padding()
                ZStack {
                    VStack {
                        if let state = model.cleaningState {
                            VStack {
                                switch state {
                                case .inProgress:
                                    HStack {
                                        Text("DELETION_IN_PROGRESS")
                                        Spacer()
                                        Text(model.fractionCompletedString ?? "")
                                    }
                                    VStack(alignment: .leading) {
                                        ProgressView(value: model.fractionCompleted)
                                        Text(model.estimatedTimeRemainingString ?? "")
                                    }
                                case .terminate:
                                    Text("DELETION_TERMINATED")
                                }
                            }
                            .padding()
                            .font(.system(.footnote).smallCaps())
                            .background(Rectangle()
                                .foregroundColor(Color(AppTheme.shared.colorScheme.systemFill))
                                .frame(width: proxy.size.width, alignment: .center))
                        }
                        recordsList
                    }
                    if model.isFetching {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                progressView
                                    .background(.ultraThinMaterial)
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
                        let devices = Set(model.records.map { record in  record.deviceIdentifierForVendor })
                        // We show the clean button for all device, since we don't know the devices in the computed reesult.
                        if model.iteratorHasMoreRecords || devices.count > 1 {
                            buttons += [ActionSheet.Button.destructive(Text("CLEAN_OLD_BACKUPS_ON_ALL_DEVICES"),
                                                                       action: {
                                model.cleanBackups(cleanAllDevices: true)
                            })]
                            buttons += [ActionSheet.Button.default(Text("CLEAN_OLD_BACKUPS_ON_CURRENT_DEVICE"),
                                                                   action: {
                                model.cleanBackups(cleanAllDevices: false)
                            })]
                        } else {
                            buttons += [ActionSheet.Button.default(Text("Delete"),
                                                                   action: {
                                model.cleanBackups(cleanAllDevices: false)
                            })]
                        }
                        buttons += [ActionSheet.Button.cancel()]
                        return ActionSheet(title: Text("CLEAN_OLD_BACKUPS_TITLE"),
                                           message: Text("CLEAN_OLD_BACKUPS_MESSAGE"),
                                           buttons: buttons)
                    case .cleanLatestAction(let record, let otherDevice):
                        let title = otherDevice ? Text("CLEAN_LATEST_BACKUP_FOR_OTHER_DEVICE_TITLE") : Text("CLEAN_LATEST_BACKUP_FOR_CURRENT_DEVICE_TITLE")
                        let message = otherDevice ? Text("CLEAN_LATEST_BACKUP_FOR_OTHER_DEVICE_MESSAGE") : Text("CLEAN_LATEST_BACKUP_FOR_CURRENT_DEVICE_MESSAGE")
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


private struct RecordView: View {

    let record: CKRecord
    let isDeleting: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let deviceName = record[.deviceName] as? String {
                    Text(deviceName)
                        .font(.system(.headline, design: .rounded))
                }
                Spacer()
                if isDeleting {
                    Text("IS_DELETING")
                        .font(.caption)
                }
            }
            HStack {
                if let identifierForVendor = UIDevice.current.identifierForVendor,
                   identifierForVendor == record.deviceIdentifierForVendor {
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
