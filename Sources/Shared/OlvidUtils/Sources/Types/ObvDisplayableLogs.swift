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

import Foundation


public actor ObvDisplayableLogs {

    private var displayableLogsAreEnabled = false
    private var containerURLForDisplayableLogs: URL?
    
    public static let shared = ObvDisplayableLogs()
    
    private init() {}
    
    // MARK: - Public API
    
    nonisolated
    public func doEnableRunningLogs(_ value: Bool) {
        Task { [weak self] in
            await self?.doEnableRunningLogsInternal(value)
        }
    }

    
    nonisolated
    public func setContainerURLForDisplayableLogs(to url: URL) {
        Task { [weak self] in
            await self?.setContainerURLForDisplayableLogsInternal(to: url)
        }
    }
    
    
    nonisolated
    public func log(_ string: String) {
        Task { [weak self] in
            guard let self else { return }
            guard let containerURLForDisplayableLogs = await containerURLForDisplayableLogs else {
                throw ObvError.containerURLForDisplayableLogsIsNil
            }
            guard await displayableLogsAreEnabled else {
                return
            }
            let now = Date()
            let dateFormatterForLog = self.dateFormatterForLog
            let dateFormatterForFilename = self.dateFormatterForFilename
            let logName = "\(dateFormatterForFilename.string(from: Date()))-olvid.log"
            let log = containerURLForDisplayableLogs.appendingPathComponent(logName, isDirectory: false)
            guard let data = dateFormatterForLog.string(from: now).appending(" - ").appending(string).appending("\n").data(using: .utf8) else { return }
            if let fh = try? FileHandle(forWritingTo: log) {
                defer { try? fh.close() }
                _ = try? fh.seekToEnd()
                fh.write(data)
            } else {
                guard let firstline = dateFormatterForFilename.string(from: now).appending("\n").data(using: .utf8) else { return }
                try? firstline.write(to: log)
                if let fh = try? FileHandle(forWritingTo: log) {
                    defer { try? fh.close() }
                    _ = try? fh.seekToEnd()
                    fh.write(data)
                }
            }
        }
    }

    
    public func getAvailableLogs() throws -> [NSURL] {
        guard let containerURLForDisplayableLogs else {
            throw ObvError.containerURLForDisplayableLogsIsNil
        }
        let fm = FileManager.default
        let logs = try fm.contentsOfDirectory(atPath: containerURLForDisplayableLogs.path)
            .sorted()
            .reversed()
            .map({ $0 as String })
            .map({ containerURLForDisplayableLogs.appendingPathComponent($0) as NSURL })
        return logs
    }

    
    public func getSizeOfLog(_ log: NSURL) throws -> Int64? {
        guard let path = log.path else { assertionFailure(); return nil }
        guard let fileAttributes = try? FileManager.default.attributesOfItem(atPath: path) else { assertionFailure(); return nil }
        return fileAttributes[FileAttributeKey.size] as? Int64
    }
    
    
    public func deleteLogsOlderThan(date: Date) throws {
        let fm = FileManager.default
        let logs = try getAvailableLogs()
        for log in logs {
            guard let logDate = dateFromLog(log) else { continue }
            if logDate < date {
                guard let path = log.path else { assertionFailure(); continue }
                guard fm.fileExists(atPath: path) else { assertionFailure(); continue }
                try? fm.removeItem(at: log as URL)
            }
        }
    }

    
    // MARK: - Private API
    
    private let dateFormatterForFilename: DateFormatter = {
        let df = DateFormatter()
        df.timeStyle = .none
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()
    
    
    private let dateFormatterForLog: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss:SSSSZZZZZ"
        return df
    }()
    

    private func doEnableRunningLogsInternal(_ value: Bool) {
        displayableLogsAreEnabled = value
    }
    
    
    private func setContainerURLForDisplayableLogsInternal(to url: URL) {
        assert(containerURLForDisplayableLogs == nil || containerURLForDisplayableLogs == url, "In practice, we expect to set this value exactly once")
        containerURLForDisplayableLogs = url
    }
    

    private func dateFromLog(_ log: NSURL) -> Date? {
        guard let dateAsString = log.lastPathComponent?.replacingOccurrences(of: "-olvid.log", with: "") else { assertionFailure(); return nil }
        return dateFormatterForFilename.date(from: dateAsString)
    }

    
    enum ObvError: Error {
        case containerURLForDisplayableLogsIsNil
    }
}
