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

import Foundation


public final class ObvDisplayableLogs {

    private let internalQueue = DispatchQueue(label: "ObvDisplayableLogs internal queue")
    private var checkIfDisplayableLogsAreEnabled: () -> Bool = { return false }
    private var containerURLForDisplayableLogs: URL?
    
    public static let shared = ObvDisplayableLogs()
    

    private init() {}
    
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
    
    
    public func doEnableRunningLogs(_ value: @escaping () -> Bool) {
        internalQueue.async { [weak self] in
            guard let self else { return }
            checkIfDisplayableLogsAreEnabled = value
        }
    }
    
    public func setContainerURLForDisplayableLogs(to url: URL) {
        internalQueue.async { [weak self] in
            guard let self else { return }
            assert(containerURLForDisplayableLogs == nil, "In practice, we expect to set this value exactly once")
            containerURLForDisplayableLogs = url
        }
    }
    
    
    public func log(_ string: String) {
        guard checkIfDisplayableLogsAreEnabled() else { return }
        let now = Date()
        let dateFormatterForLog = self.dateFormatterForLog
        let dateFormatterForFilename = self.dateFormatterForFilename
        guard let logURL = self.logURL else { assertionFailure(); return }
        internalQueue.async {
            guard let data = dateFormatterForLog.string(from: now).appending(" - ").appending(string).appending("\n").data(using: .utf8) else { return }
            if let fh = try? FileHandle(forWritingTo: logURL) {
                defer { try? fh.close() }
                _ = try? fh.seekToEnd()
                fh.write(data)
            } else {
                guard let firstline = dateFormatterForFilename.string(from: now).appending("\n").data(using: .utf8) else { return }
                try? firstline.write(to: logURL)
                if let fh = try? FileHandle(forWritingTo: logURL) {
                    defer { try? fh.close() }
                    _ = try? fh.seekToEnd()
                    fh.write(data)
                }
            }
        }
    }
    
    
    public func getLogNSURL(_ logFilename: String) -> NSURL? {
        guard let logURL = try? logURL(for: logFilename) else { return nil }
        let fm = FileManager.default
        guard fm.fileExists(atPath: logURL.path) else { return nil }
        return logURL as NSURL
    }
    
    
    private var logFilename: String {
        "\(dateFormatterForFilename.string(from: Date()))-olvid.log"
    }
    
    private func dateFromLogFilename(_ filename: String) -> Date? {
        let dateAsString = filename.replacingOccurrences(of: "-olvid.log", with: "")
        return dateFormatterForFilename.date(from: dateAsString)
    }

    private func logURL(for logFilename: String) throws -> URL {
        guard let containerURLForDisplayableLogs else {
            assertionFailure()
            throw ObvError.containerURLForDisplayableLogsIsNil
        }
        return containerURLForDisplayableLogs.appendingPathComponent(logFilename, isDirectory: false)
    }
    
    private var logURL: URL? {
        try? logURL(for: logFilename)
    }
    
    
    public func getAvailableLogs() throws -> [String] {
        guard let containerURLForDisplayableLogs else {
            throw ObvError.containerURLForDisplayableLogsIsNil
        }
        let fm = FileManager.default
        let items = try fm.contentsOfDirectory(atPath: containerURLForDisplayableLogs.path).sorted().reversed() as [String]
        return items
    }
    
    
    public func getContentOfLog(logFilename: String) throws -> String {
        let logURL = try logURL(for: logFilename)
        return try String(contentsOf: logURL, encoding: .utf8)
    }
    
    
    public func deleteLog(logFilename: String) throws {
        let fm = FileManager.default
        let logURL = try logURL(for: logFilename)
        try fm.removeItem(at: logURL)
    }
    

    public func getSizeOfLog(logFilename: String) throws -> Int64? {
        let logURL = try logURL(for: logFilename)
        guard let fileAttributes = try? FileManager.default.attributesOfItem(atPath: logURL.path) else { return nil }
        return fileAttributes[FileAttributeKey.size] as? Int64
    }
    
    
    public func deleteLogsOlderThan(date: Date) throws {
        guard let containerURLForDisplayableLogs else {
            throw ObvError.containerURLForDisplayableLogsIsNil
        }
        let fm = FileManager.default
        let availableLogNames = try getAvailableLogs()
        for availableLogName in availableLogNames {
            guard let logDate = dateFromLogFilename(availableLogName) else { continue }
            if logDate < date {
                let url = containerURLForDisplayableLogs.appendingPathComponent(availableLogName)
                guard fm.fileExists(atPath: url.path) else { assertionFailure(); continue }
                try? fm.removeItem(at: url)
            }
        }
    }
    
    
    enum ObvError: Error {
        case containerURLForDisplayableLogsIsNil
    }
}
