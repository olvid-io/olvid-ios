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


final class ObvDisplayableLogs {

    private let internalQueue = DispatchQueue(label: "ObvDisplayableLogs internal queue")
    
    static let shared = ObvDisplayableLogs()

    private init() {}
    
    private let dateFormatterForFilename: DateFormatter = {
        let df = DateFormatter()
        df.timeStyle = .none
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()
    
    private let dateFormatterForLog: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss:SSSS"
        return df
    }()
    
    
    func log(_ string: String) {
        let now = Date()
        let dateFormatterForLog = self.dateFormatterForLog
        let dateFormatterForFilename = self.dateFormatterForFilename
        if #available(iOS 13.4, *) {
            let logURL = self.logURL
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
    }
    
    func getLogNSURL(_ logFilename: String) -> NSURL? {
        let logURL = ObvMessengerConstants.containerURL.forDisplayableLogs.appendingPathComponent(logFilename, isDirectory: false)
        let fm = FileManager.default
        guard fm.fileExists(atPath: logURL.path) else { return nil }
        return logURL as NSURL
    }
    
    private var logFilename: String {
        "\(dateFormatterForFilename.string(from: Date()))-olvid.log"
    }
    
    private var logURL: URL {
        ObvMessengerConstants.containerURL.forDisplayableLogs.appendingPathComponent(logFilename, isDirectory: false)
    }
    
    func getAvailableLogs() throws -> [String] {
        let fm = FileManager.default
        let directory = ObvMessengerConstants.containerURL.forDisplayableLogs
        let items = try fm.contentsOfDirectory(atPath: directory.path).sorted().reversed() as [String]
        return items
    }
    
    func getContentOfLog(logFilename: String) throws -> String {
        let logURL = ObvMessengerConstants.containerURL.forDisplayableLogs.appendingPathComponent(logFilename, isDirectory: false)
        return try String(contentsOf: logURL, encoding: .utf8)
    }
    
    func deleteLog(logFilename: String) throws {
        let fm = FileManager.default
        let logURL = ObvMessengerConstants.containerURL.forDisplayableLogs.appendingPathComponent(logFilename, isDirectory: false)
        try fm.removeItem(at: logURL)
    }
}
