/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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
import CoreData
import os.log

/// This class shall only be used under iOS12 or less
class SingleDiscussionSettingsTableViewController: UITableViewController {

    let discussionInViewContext: PersistedDiscussion
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "SingleDiscussionSettingsTableViewController")

    init(discussionInViewContext: PersistedDiscussion) {
        assert(Thread.isMainThread)
        if #available(iOS 13, *) { assertionFailure("This class is intended of iOS 12 or less. Under iOS13 and later, use DiscussionExpirationSettingsHostingViewController") }
        self.discussionInViewContext = discussionInViewContext
        super.init(style: .grouped)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = CommonString.Title.discussionSettings
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        if #available(iOS 13, *) {
            return 2
        } else {
            return 1
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 3
        case 1: return 4
        default: return 0
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            
        switch indexPath.section {
            
        case 0:
            // Read receipts
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.selectionStyle = .none
            switch SendReadReceiptOverrideForRow(indexPath.row) {
            case .none:
                let stringForGeneralSetting = ObvMessengerSettings.Discussions.doSendReadReceipt ? CommonString.Word.Yes : CommonString.Word.No
                cell.textLabel?.text = "\(CommonString.Title.useApplicationDefault) (\(stringForGeneralSetting))"
            case .some(value: let value):
                cell.textLabel?.text = value ? CommonString.Word.Yes : CommonString.Word.No
            }
            if rowForSendReadReceiptOverride(discussionInViewContext.localConfiguration.doSendReadReceipt) == indexPath.row {
                cell.accessoryType = .checkmark
            }
            return cell
            
        case 1:
            // Rich link previews
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.selectionStyle = .none
            switch fetchContentRichURLsMetadataOverrideForRow(indexPath.row) {
            case .none:
                let stringForGeneralSetting: String
                switch ObvMessengerSettings.Discussions.doFetchContentRichURLsMetadata {
                case .never:
                    stringForGeneralSetting = CommonString.Word.Never
                case .withinSentMessagesOnly:
                    stringForGeneralSetting = DiscussionsSettingsTableViewController.Strings.RichLinks.sentMessagesOnly
                case .always:
                    stringForGeneralSetting = CommonString.Word.Always
                }
                cell.textLabel?.text = "\(CommonString.Title.useApplicationDefault) (\(stringForGeneralSetting))"
            case .some(value: let value):
                switch value {
                case .never:
                    cell.textLabel?.text = CommonString.Word.Never
                case .withinSentMessagesOnly:
                    cell.textLabel?.text = DiscussionsSettingsTableViewController.Strings.RichLinks.sentMessagesOnly
                case .always:
                    cell.textLabel?.text = CommonString.Word.Always
                }
            }
            if rowForFetchContentRichURLsMetadataOverride(discussionInViewContext.localConfiguration.doFetchContentRichURLsMetadata) == indexPath.row {
                cell.accessoryType = .checkmark
            }
            return cell

        default:
            assertionFailure()
            return UITableViewCell()
        }
        
    }

    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {

        let discussionObjectID = discussionInViewContext.objectID
        let log = self.log

        switch indexPath.section {

        case 0:
            // Read receipts
            let override = SendReadReceiptOverrideForRow(indexPath.row)
            ObvStack.shared.performBackgroundTask { (context) in
                guard let discussion = try? PersistedDiscussion.get(objectID: discussionObjectID, within: context) else { return }
                discussion.localConfiguration.doSendReadReceipt = override
                do { try context.save(logOnFailure: log) } catch { assertionFailure(); return }
                DispatchQueue.main.async {
                    tableView.reloadSections([0], with: .none)
                }
            }

        case 1:
            // Rich link previews
            let override = fetchContentRichURLsMetadataOverrideForRow(indexPath.row)
            ObvStack.shared.performBackgroundTask { (context) in
                guard let discussion = try? PersistedDiscussion.get(objectID: discussionObjectID, within: context) else { return }
                discussion.localConfiguration.doFetchContentRichURLsMetadata = override
                do { try context.save(logOnFailure: log) } catch { assertionFailure(); return }
                DispatchQueue.main.async {
                    tableView.reloadSections([1], with: .none)
                }
            }
            
        default:
            return
        }
    }

    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0:
            return CommonString.Title.sendReadRecceipts
        case 1:
            return DiscussionsSettingsTableViewController.Strings.RichLinks.title
        default:
            return nil
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard section == 0 else { return nil }
        let override = discussionInViewContext.localConfiguration.doSendReadReceipt
        switch override {
        case .none:
            return ObvMessengerSettings.Discussions.doSendReadReceipt ? DiscussionsSettingsTableViewController.Strings.SendReadRecceipts.explanationWhenYes : DiscussionsSettingsTableViewController.Strings.SendReadRecceipts.explanationWhenNo
        case .some(let value):
            return value ? Strings.SendReadRecceipts.explanationWhenYes : Strings.SendReadRecceipts.explanationWhenNo
        }
    }

    private func rowForSendReadReceiptOverride(_ override: Bool?) -> Int {
        switch override {
        case .none:
            return 0
        case .some(value: let value):
            return value ? 1 : 2
        }
    }
    
    private func SendReadReceiptOverrideForRow(_ row: Int) -> Bool? {
        let override: Bool?
        switch row {
        case 0:
            override = nil
        case 1:
            override = true
        case 2:
            override = false
        default:
            assert(false)
            return false
        }
        assert(row == rowForSendReadReceiptOverride(override))
        return override
    }


    private func rowForFetchContentRichURLsMetadataOverride(_ override: ObvMessengerSettings.Discussions.FetchContentRichURLsMetadataChoice?) -> Int {
        switch override {
        case .none:
            return 0
        case .some(value: let value):
            switch value {
            case .never:
                return 1
            case .withinSentMessagesOnly:
                return 2
            case .always:
                return 3
            }
        }
    }
    
    
    private func fetchContentRichURLsMetadataOverrideForRow(_ row: Int) -> ObvMessengerSettings.Discussions.FetchContentRichURLsMetadataChoice? {
        let override: ObvMessengerSettings.Discussions.FetchContentRichURLsMetadataChoice?
        switch row {
        case 0: override = nil
        case 1: override = .never
        case 2: override = .withinSentMessagesOnly
        case 3: override = .always
        default:
            assertionFailure()
            return .always
        }
        assert(row == rowForFetchContentRichURLsMetadataOverride(override))
        return override
    }
    
}
