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

import UIKit
import LocalAuthentication
import OlvidUtils
import ObvTypes
import ObvUI
import ObvUICoreData
import ObvSettings
import ObvDesignSystem


@MainActor
final class PrivacyTableViewController: UITableViewController, ObvErrorMaker {

    static let errorDomain = "PrivacyTableViewController"

    let ownedCryptoId: ObvCryptoId

    private var authenticationMethod: AuthenticationMethod
    private var observationTokens = [NSObjectProtocol]()

    private(set) weak var createPasscodeDelegate: CreatePasscodeDelegate?
    private(set) weak var localAuthenticationDelegate: LocalAuthenticationDelegate?

    let dateComponentsFormatter: DateComponentsFormatter = {
        let df = DateComponentsFormatter()
        df.allowedUnits = [.hour, .minute, .second]
        df.unitsStyle = .full
        return df
    }()

    init(ownedCryptoId: ObvCryptoId, createPasscodeDelegate: CreatePasscodeDelegate, localAuthenticationDelegate: LocalAuthenticationDelegate) {
        self.ownedCryptoId = ownedCryptoId
        self.createPasscodeDelegate = createPasscodeDelegate
        self.localAuthenticationDelegate = localAuthenticationDelegate
        self.authenticationMethod = AuthenticationMethod.bestAvailableAuthenticationMethod()
        super.init(style: Self.settingsTableStyle)

        observeNotifications()
    }

    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func observeNotifications() {
        let token = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) {  _ in
            Task { [weak self] in
                await self?.reload()
            }
        }
        observationTokens += [token]
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = CommonString.Word.Privacy
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.reload()
    }

    private func reload() {
        self.authenticationMethod = AuthenticationMethod.bestAvailableAuthenticationMethod()
        tableView.reloadData()
    }
    
    
    private enum Section: CaseIterable {
        case notificationContentPrivacyStyle
        case localAuthenticationPolicy
        case lockScreenGracePeriod
        case deleteSensitiveMessagesOnBadPasscode
        case hiddenProfileClosePolicy
        static var shown: [Section] {
            var result = [Section]()
            result += [.notificationContentPrivacyStyle, .localAuthenticationPolicy]
            if ObvMessengerSettings.Privacy.localAuthenticationPolicy.lockScreen {
                result += [.lockScreenGracePeriod]
                if ObvMessengerSettings.Privacy.localAuthenticationPolicy.useCustomPasscode {
                    result += [.deleteSensitiveMessagesOnBadPasscode]
                }
            }
            result += [.hiddenProfileClosePolicy]
            return result
        }
        var numberOfItems: Int {
            switch self {
            case .notificationContentPrivacyStyle: return NotificationContentPrivacyStyleItem.shown.count
            case .localAuthenticationPolicy: return LocalAuthenticationPolicyItem.shown.count
            case .lockScreenGracePeriod: return LockScreenGracePeriodItem.shown.count
            case .deleteSensitiveMessagesOnBadPasscode: return DeleteSensitiveMessagesOnBadPasscodeItem.shown.count
            case .hiddenProfileClosePolicy: return HiddenProfileClosePolicyItem.shown.count
            }
        }
        static func shownSectionAt(section: Int) -> Section? {
            return shown[safe: section]
        }
    }
    
    
    private enum NotificationContentPrivacyStyleItem: CaseIterable {
        case hideContent
        static var shown: [NotificationContentPrivacyStyleItem] {
            return NotificationContentPrivacyStyleItem.allCases
        }
        static func shownItemAt(item: Int) -> NotificationContentPrivacyStyleItem? {
            return shown[safe: item]
        }
        var cellIdentifier: String {
            switch self {
            case .hideContent: return "hideContent"
            }
        }
    }
    
    
    private enum LocalAuthenticationPolicyItem: CaseIterable {
        case none
        case deviceOwnerAuthentication
        case biometricsWithCustomPasscodeFallback
        case customPasscode
        static var shown: [LocalAuthenticationPolicyItem] {
            assert(ObvLocalAuthenticationPolicy.allCases.count == LocalAuthenticationPolicyItem.allCases.count)
            return LocalAuthenticationPolicyItem.allCases
        }
        static func shownItemAt(item: Int) -> LocalAuthenticationPolicyItem? {
            return shown[safe: item]
        }
        var cellIdentifier: String {
            switch self {
            case .none: return "none"
            case .deviceOwnerAuthentication: return "deviceOwnerAuthentication"
            case .biometricsWithCustomPasscodeFallback: return "biometricsWithCustomPasscodeFallback"
            case .customPasscode: return "customPasscode"
            }
        }
        var localAuthenticationPolicy: ObvLocalAuthenticationPolicy {
            switch self {
            case .none: return .none
            case .deviceOwnerAuthentication: return .deviceOwnerAuthentication
            case .biometricsWithCustomPasscodeFallback: return .biometricsWithCustomPasscodeFallback
            case .customPasscode: return .customPasscode
            }
        }
    }
    
    
    private enum LockScreenGracePeriodItem: CaseIterable {
        case requireAuthentication
        static var shown: [LockScreenGracePeriodItem] {
            return LockScreenGracePeriodItem.allCases
        }
        static func shownItemAt(item: Int) -> LockScreenGracePeriodItem? {
            return shown[safe: item]
        }
        var cellIdentifier: String {
            switch self {
            case .requireAuthentication: return "requireAuthentication"
            }
        }
    }
    
    
    private enum DeleteSensitiveMessagesOnBadPasscodeItem: CaseIterable {
        case eraseSensitive
        static var shown: [DeleteSensitiveMessagesOnBadPasscodeItem] {
            return DeleteSensitiveMessagesOnBadPasscodeItem.allCases
        }
        static func shownItemAt(item: Int) -> DeleteSensitiveMessagesOnBadPasscodeItem? {
            return shown[safe: item]
        }
        var cellIdentifier: String {
            switch self {
            case .eraseSensitive: return "eraseSensitive"
            }
        }
    }
    
    
    private enum HiddenProfileClosePolicyItem: CaseIterable {
        case hiddenProfileClosePolicyItem
        static var shown: [HiddenProfileClosePolicyItem] {
            return HiddenProfileClosePolicyItem.allCases
        }
        static func shownItemAt(item: Int) -> HiddenProfileClosePolicyItem? {
            return shown[safe: item]
        }
        var cellIdentifier: String {
            switch self {
            case .hiddenProfileClosePolicyItem: return "hiddenProfileClosePolicyItem"
            }
        }
    }
    

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.shown.count
    }
    

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section.shownSectionAt(section: section) else { return 0 }
        return section.numberOfItems
    }
    

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cellInCaseOfError = UITableViewCell(style: .default, reuseIdentifier: nil)

        guard let section = Section.shownSectionAt(section: indexPath.section) else {
            assertionFailure()
            return cellInCaseOfError
        }

        switch section {
            
        case .notificationContentPrivacyStyle:
            guard let item = NotificationContentPrivacyStyleItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return cellInCaseOfError }
            switch item {
            case .hideContent:
                let cell = UITableViewCell(style: .value1, reuseIdentifier: item.cellIdentifier)
                cell.textLabel?.text = Strings.notificationContentPrivacyStyle.title
                switch ObvMessengerSettings.Privacy.hideNotificationContent {
                case .no:
                    cell.detailTextLabel?.text = CommonString.Word.No
                case .partially:
                    cell.detailTextLabel?.text = CommonString.Word.Partially
                case .completely:
                    cell.detailTextLabel?.text = CommonString.Word.Completely
                }
                cell.accessoryType = .disclosureIndicator
                return cell
            }

        case .localAuthenticationPolicy:
            guard let item = LocalAuthenticationPolicyItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return cellInCaseOfError }
            let policy = item.localAuthenticationPolicy
            let cell = UITableViewCell(style: .default, reuseIdentifier: item.cellIdentifier)
            let isPolicyAvailable = policy.isAvailable(whenBestAvailableAuthenticationMethodIs: authenticationMethod)
            let title = policy.title(authenticationMethod: authenticationMethod)
            var configuration = cell.defaultContentConfiguration()
            configuration.text = title
            configuration.textProperties.color = isPolicyAvailable ? AppTheme.shared.colorScheme.label : AppTheme.shared.colorScheme.secondaryLabel
            cell.contentConfiguration = configuration
            if ObvMessengerSettings.Privacy.localAuthenticationPolicy == policy {
                cell.accessoryType = .checkmark
            } else {
                cell.accessoryType = .none
            }
            return cell
            
        case .lockScreenGracePeriod:
            guard let item = LockScreenGracePeriodItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return cellInCaseOfError }
            switch item {
            case .requireAuthentication:
                let cell = UITableViewCell(style: .value1, reuseIdentifier: item.cellIdentifier)
                let gracePeriod = ObvMessengerSettings.Privacy.lockScreenGracePeriod
                let title = CommonString.Title.gracePeriod
                var details: String?
                if gracePeriod == 0 {
                    details = CommonString.Word.Immediately
                } else if let duration = dateComponentsFormatter.string(from: gracePeriod) {
                    details = CommonString.gracePeriodTitle(duration)
                }
                var configuration = cell.defaultContentConfiguration()
                configuration.text = title
                configuration.secondaryText = details
                cell.contentConfiguration = configuration
                cell.accessoryType = .disclosureIndicator
                return cell
            }
            
        case .deleteSensitiveMessagesOnBadPasscode:
            guard let item = DeleteSensitiveMessagesOnBadPasscodeItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return cellInCaseOfError }
            switch item {
            case .eraseSensitive:
                let cell = ObvTitleAndSwitchTableViewCell(reuseIdentifier: item.cellIdentifier)
                cell.title = Strings.lockoutCleanEphemeralTitle
                cell.switchIsOn = ObvMessengerSettings.Privacy.lockoutCleanEphemeral
                cell.blockOnSwitchValueChanged = { (value) in
                    ObvMessengerSettings.Privacy.lockoutCleanEphemeral = value
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(400)) {
                        tableView.reloadRows(at: [indexPath], with: .none) // The footer disappears under iOS 16 if calling reloadData() here
                    }
                }
                return cell
            }
            
        case .hiddenProfileClosePolicy:
            guard let item = HiddenProfileClosePolicyItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return cellInCaseOfError }
            switch item {
            case .hiddenProfileClosePolicyItem:
                let cell = UITableViewCell(style: .value1, reuseIdentifier: item.cellIdentifier)
                let title = CommonString.Title.closeOpenHiddenProfile
                let details: String
                switch ObvMessengerSettings.Privacy.hiddenProfileClosePolicy {
                case .manualSwitching:
                    details = NSLocalizedString("ALERT_CHOOSE_HIDDEN_PROFILE_CLOSE_POLICY_ACTION_MANUAL_SWITCHING", comment: "")
                case .screenLock:
                    details = NSLocalizedString("ALERT_CHOOSE_HIDDEN_PROFILE_CLOSE_POLICY_ACTION_SCREEN_LOCK", comment: "")
                case .background:
                    details = NSLocalizedString("ALERT_CHOOSE_HIDDEN_PROFILE_CLOSE_POLICY_ACTION_BACKGROUND", comment: "")
                }
                var configuration = cell.defaultContentConfiguration()
                configuration.text = title
                configuration.secondaryText = details
                cell.contentConfiguration = configuration
                cell.accessoryType = .disclosureIndicator
                return cell
            }
        }
    }
    

    private func localAuthenticationPolicy(changeTo newPolicy: ObvLocalAuthenticationPolicy, completionHandler: @escaping () -> Void) {
        let currentPolicy = ObvMessengerSettings.Privacy.localAuthenticationPolicy
        guard currentPolicy != newPolicy else {
            DispatchQueue.main.async {
                completionHandler()
            }
            return
        }

        Task {
            do {
                switch currentPolicy {
                case .none:
                    switch newPolicy {
                    case .none: assertionFailure(); return

                    case .deviceOwnerAuthentication:
                        try await requestLocalAuthentication(with: .deviceOwnerAuthentication)

                    case .biometricsWithCustomPasscodeFallback:
                        try await requestLocalAuthentication(with: newPolicy)
                        try await startCustomPasscodeDefinitionWorkflow()

                    case .customPasscode:
                        try await startCustomPasscodeDefinitionWorkflow()
                    }
                case .deviceOwnerAuthentication:
                    switch newPolicy {
                    case .none:
                        try await requestLocalAuthentication(with: .deviceOwnerAuthentication)

                    case .deviceOwnerAuthentication: assertionFailure(); return

                    case .biometricsWithCustomPasscodeFallback:
                        try checkBiometricEnrollement()
                        try await requestLocalAuthentication(with: .deviceOwnerAuthentication)
                        try await startCustomPasscodeDefinitionWorkflow()

                    case .customPasscode:
                        try await requestLocalAuthentication(with: .deviceOwnerAuthentication)
                        try await startCustomPasscodeDefinitionWorkflow()
                    }
                case .biometricsWithCustomPasscodeFallback:
                    switch newPolicy {
                    case .none:
                        try await requestCustomPasscode()
                        await clearCustomPasscode()

                    case .deviceOwnerAuthentication:
                        try await requestCustomPasscode()
                        try await requestLocalAuthentication(with: .deviceOwnerAuthentication)
                        await clearCustomPasscode()

                    case .biometricsWithCustomPasscodeFallback: assertionFailure(); return

                    case .customPasscode:
                        try await requestCustomPasscode()

                    }
                case .customPasscode:
                    switch newPolicy {
                    case .none:
                        try await requestCustomPasscode()
                        await clearCustomPasscode()

                    case .deviceOwnerAuthentication:
                        try await requestCustomPasscode()
                        try await requestLocalAuthentication(with: .deviceOwnerAuthentication)
                        await clearCustomPasscode()

                    case .biometricsWithCustomPasscodeFallback:
                        try await requestCustomPasscode()
                        try await requestLocalAuthentication(with: .biometricsWithCustomPasscodeFallback)

                    case .customPasscode: assertionFailure(); return
                    }
                }
            } catch(let error) {
                showErrorDialog(with: error)
                DispatchQueue.main.async {
                    completionHandler()
                }
                return
            }

            ObvMessengerSettings.Privacy.localAuthenticationPolicy = newPolicy
            DispatchQueue.main.async {
                completionHandler()
            }
        }
    }
    
    
    private func clearSelection(animated: Bool) {
        tableView.indexPathsForSelectedRows?.forEach({ (indexPath) in
            tableView.deselectRow(at: indexPath, animated: animated)
        })
    }


    enum ObvLAError: LocalizedError {
        case biometryNotEnrolled
        case userCancelled
        case internalError
        case lockedOut
        var errorDescription: String {
            switch self {
            case .biometryNotEnrolled:
                return NSLocalizedString("BIOMETRY_NOT_ENROLLED_ERROR_MESSAGE", comment: "")
            case .userCancelled:
                return CommonString.Word.Cancel // Never shown
            case .lockedOut:
                return NSLocalizedString("LOCKED_OUT", comment: "")
            case .internalError:
                return CommonString.Word.Error
            }
        }
    }

    
    private func showErrorDialog(with error: Error) {
        let title: String
        let message: String?
        if let error = error as? ObvLAError {
            // Do not want to show dialog if the user has cancelled
            guard error != .userCancelled else { return }
            message = error.errorDescription
            switch error {
            case .biometryNotEnrolled:
                title = NSLocalizedString("BIOMETRY_NOT_ENROLLED_ERROR_TITLE", comment: "")
            case .userCancelled, .internalError, .lockedOut:
                title = CommonString.Word.Oups
            }
        } else if let code = LAError.Code(rawValue: (error as NSError).code) {
            guard code != .userCancel else { return }
            switch code {
            case .biometryNotEnrolled:
                title = NSLocalizedString("BIOMETRY_NOT_ENROLLED_ERROR_TITLE", comment: "")
                message = NSLocalizedString("BIOMETRY_NOT_ENROLLED_ERROR_MESSAGE", comment: "")
            default:
                title = error.localizedDescription
                message = nil
            }
        } else {
            message = error.localizedDescription
            title = CommonString.Word.Oups
        }
        let alert = UIAlertController(title: title,
                                      message: message,
                                      preferredStyle: .alert)
        let abortAction = UIAlertAction(title: CommonString.Word.Ok, style: .cancel) { [weak self] _ in
            self?.clearSelection(animated: true)
        }
        alert.addAction(abortAction)
        self.present(alert, animated: true)
    }


    private func checkBiometricEnrollement() throws {
        guard AuthenticationMethod.currentBiometricEnrollement() != nil else {
            throw ObvLAError.biometryNotEnrolled
        }
    }

    
    private func requestLocalAuthentication(with policy: ObvLocalAuthenticationPolicy) async throws {
        
        preventPrivacyWindowSceneFromShowingOnNextWillResignActive()
        
        let result = await localAuthenticationDelegate?.performLocalAuthentication(
            customPasscodePresentingViewController: self,
            uptimeAtTheTimeOfChangeoverToNotActiveState: nil,
            localizedReason: Strings.changingSettingRequiresAuthentication,
            policy: policy)
        
        switch result {
        case .authenticated:
            return
        case .cancelled, .lockedOut, .none:
            throw ObvLAError.internalError
        }
        
    }

    
    private func startCustomPasscodeDefinitionWorkflow() async throws {
        let (passcode, passcodeIsPassword) = try await defineCustomPasscode()
        try await saveCustomPasscode(passcode: passcode, passcodeIsPassword: passcodeIsPassword)
    }

    
    private func defineCustomPasscode() async throws -> (passcode: String, passcodeIsPassword: Bool) {
        let passcodeViewController = CreatePasscodeViewController()
        self.present(passcodeViewController, animated: true)
        let result = await passcodeViewController.getResult()
        switch result {
        case .passcode(passcode: let passcode, passcodeIsPassword: let passcodeIsPassword):
            return (passcode, passcodeIsPassword)
        case .cancelled:
            throw ObvLAError.userCancelled
        }
    }

    
    private func requestCustomPasscode() async throws {
        do {
            guard let createPasscodeDelegate = self.createPasscodeDelegate else {
                assertionFailure()
                throw ObvLAError.internalError
            }
            let laResult = await createPasscodeDelegate.requestCustomPasscode(customPasscodePresentingViewController: self)
            switch laResult {
            case .authenticated:
                return
            case .cancelled:
                throw ObvLAError.userCancelled
            case .lockedOut:
                throw ObvLAError.lockedOut
            }
        }
    }

    
    private func clearCustomPasscode() async {
        guard let createPasscodeDelegate = self.createPasscodeDelegate else {
            assertionFailure(); return
        }
        await createPasscodeDelegate.clearPasscode()
    }

    
    private func saveCustomPasscode(passcode: String, passcodeIsPassword: Bool) async throws {
        guard let createPasscodeDelegate = self.createPasscodeDelegate else {
            assertionFailure(); return
        }
        try await createPasscodeDelegate.savePasscode(passcode, passcodeIsPassword: passcodeIsPassword)
    }
    
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let section = Section.shownSectionAt(section: indexPath.section) else { assertionFailure(); return }
        switch section {
        case .notificationContentPrivacyStyle:
            guard let item = NotificationContentPrivacyStyleItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return }
            switch item {
            case .hideContent:
                let vc = NotificationContentPrivacyStyleChooserTableViewController()
                self.navigationController?.pushViewController(vc, animated: true)
            }
        case .localAuthenticationPolicy:
            guard let item = LocalAuthenticationPolicyItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return }
            let policy = item.localAuthenticationPolicy
            localAuthenticationPolicy(changeTo: policy) { [weak self] in
                self?.tableView.reloadData()
                self?.tableView.deselectRow(at: indexPath, animated: true)
            }
        case .lockScreenGracePeriod:
            guard let item = LockScreenGracePeriodItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return }
            switch item {
            case .requireAuthentication:
                let vc = GracePeriodsChooserTableViewController()
                self.navigationController?.pushViewController(vc, animated: true)
            }
        case .deleteSensitiveMessagesOnBadPasscode:
            break
        case .hiddenProfileClosePolicy:
            let vc = HiddenProfileClosePolicyChooserViewController()
            self.navigationController?.pushViewController(vc, animated: true)
        }
    }
    
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let section = Section.shownSectionAt(section: section) else { assertionFailure(); return nil }
        switch section {
        case .notificationContentPrivacyStyle:
            return CommonString.Word.Notifications
        case .localAuthenticationPolicy:
            return Strings.screenLock
        case .lockScreenGracePeriod:
            return nil
        case .deleteSensitiveMessagesOnBadPasscode:
            return nil
        case .hiddenProfileClosePolicy:
            return NSLocalizedString("HIDDEN_PROFILES", comment: "")
        }
    }
    
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard let section = Section.shownSectionAt(section: section) else { assertionFailure(); return nil }
        switch section {
        case .notificationContentPrivacyStyle:
            switch ObvMessengerSettings.Privacy.hideNotificationContent {
            case .no: return Strings.notificationContentPrivacyStyle.explanation.whenNo
            case .partially: return Strings.notificationContentPrivacyStyle.explanation.whenPartially
            case .completely: return Strings.notificationContentPrivacyStyle.explanation.whenCompletely
            }
        case .localAuthenticationPolicy:
            return ObvMessengerSettings.Privacy.localAuthenticationPolicy.explanation(authenticationMethod: authenticationMethod)
        case .lockScreenGracePeriod:
            if ObvMessengerSettings.Privacy.lockScreenGracePeriod == 0 {
                return Strings.noGracePeriodExplanation
            } else {
                guard let duration = dateComponentsFormatter.string(from: ObvMessengerSettings.Privacy.lockScreenGracePeriod) else {
                    assertionFailure(); return nil
                }
                return Strings.gracePeriodExplanation(duration)
            }
        case .deleteSensitiveMessagesOnBadPasscode:
            return Strings.lockoutCleanEphemeralExplanation
        case .hiddenProfileClosePolicy:
            return nil
        }
    }
        
}


fileprivate extension ObvLocalAuthenticationPolicy {


    private enum PasscodeKind {
        case system
        case custom
    }
    

    private enum LocalizedStringKind {
        case title
        case explanation
    }
    

    private func localizedString(for method: AuthenticationMethod, passcodeKind: PasscodeKind, localizedStringKind: LocalizedStringKind) -> String {
        switch (method, passcodeKind, localizedStringKind) {

        case (.none, .system, .title):
            return NSLocalizedString("LOGIN_WITH_TOUCH_ID_FACE_ID_SYSTEM_PASSCODE_TITLE", comment: "")
        case (.none, .system, .explanation):
            return NSLocalizedString("LOGIN_WITH_TOUCH_ID_FACE_ID_SYSTEM_PASSCODE_EXPLANATION", comment: "")
        case (.none, .custom, .title):
            return NSLocalizedString("LOGIN_WITH_TOUCH_ID_FACE_ID_CUSTOM_PASSCODE_TITLE", comment: "")
        case (.none, .custom, .explanation):
            return NSLocalizedString("LOGIN_WITH_TOUCH_ID_FACE_ID_CUSTOM_PASSCODE_EXPLANATION", comment: "")

        case (.passcode, .system, .title):
            return NSLocalizedString("LOGIN_WITH_SYSTEM_PASSCODE_TITLE", comment: "")
        case (.passcode, .system, .explanation):
            return NSLocalizedString("LOGIN_WITH_SYSTEM_PASSCODE_EXPLANATION", comment: "")
        case (.passcode, .custom, .title):
            return NSLocalizedString("LOGIN_WITH_CUSTOM_PASSCODE_TITLE", comment: "")
        case (.passcode, .custom, .explanation):
            return NSLocalizedString("LOGIN_WITH_CUSTOM_PASSCODE_EXPLANATION", comment: "")

        case (.touchID, .system, .title):
            return NSLocalizedString("LOGIN_WITH_TOUCH_ID_SYSTEM_PASSCODE_TITLE", comment: "")
        case (.touchID, .system, .explanation):
            return NSLocalizedString("LOGIN_WITH_TOUCH_ID_SYSTEM_PASSCODE_EXPLANATION", comment: "")
        case (.touchID, .custom, .title):
            return NSLocalizedString("LOGIN_WITH_TOUCH_ID_CUSTOM_PASSCODE_TITLE", comment: "")
        case (.touchID, .custom, .explanation):
            return NSLocalizedString("LOGIN_WITH_TOUCH_ID_CUSTOM_PASSCODE_EXPLANATION", comment: "")

        case (.faceID, .system, .title):
            return NSLocalizedString("LOGIN_WITH_FACE_ID_SYSTEM_PASSCODE_TITLE", comment: "")
        case (.faceID, .system, .explanation):
            return NSLocalizedString("LOGIN_WITH_FACE_ID_SYSTEM_PASSCODE_EXPLANATION", comment: "")
        case (.faceID, .custom, .title):
            return NSLocalizedString("LOGIN_WITH_FACE_ID_CUSTOM_PASSCODE_TITLE", comment: "")
        case (.faceID, .custom, .explanation):
            return NSLocalizedString("LOGIN_WITH_FACE_ID_CUSTOM_PASSCODE_EXPLANATION", comment: "")

        }
    }
    

    func title(authenticationMethod method: AuthenticationMethod) -> String {
        switch self {
        case .none: return CommonString.Word.None
        case .deviceOwnerAuthentication:
            return localizedString(for: method, passcodeKind: .system, localizedStringKind: .title)
        case .biometricsWithCustomPasscodeFallback:
            var method = method
            if method == .passcode {
                method = .none // We only want biometry in this case
            }
            return localizedString(for: method, passcodeKind: .custom, localizedStringKind: .title)
        case .customPasscode:
            return localizedString(for: .passcode, passcodeKind: .custom, localizedStringKind: .title)
        }
    }


    func explanation(authenticationMethod method: AuthenticationMethod) -> String {
        switch self {
        case .none:
            return NSLocalizedString("NO_AUTHENTICATION_EXPLANATION", comment: "")
        case .deviceOwnerAuthentication:
            return localizedString(for: method, passcodeKind: .system, localizedStringKind: .explanation)
        case .biometricsWithCustomPasscodeFallback:
            return localizedString(for: method, passcodeKind: .custom, localizedStringKind: .explanation)
        case .customPasscode:
            return localizedString(for: .passcode, passcodeKind: .custom, localizedStringKind: .explanation)
        }
    }

}
