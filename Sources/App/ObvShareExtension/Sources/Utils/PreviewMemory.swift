/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import CoreGraphics
import Darwin
import os
import OSLog
import ObvAppCoreConstants

/// What the share extension is charged for, and how much of its allowance is left.
///
/// The extension is killed by jetsam when it shares more than a handful of photos, and until this file there was
/// **nothing in the repository that could report a byte** — no `os_proc_available_memory`, no `TASK_VM_INFO`, no
/// `didReceiveMemoryWarning`. The one number ever written down (`PreviewImageCache`'s "measured peak around 80 MB")
/// came from Instruments, by hand, once; the commit that raised the preview cache to 64 MB on the strength of it is
/// very likely what re-introduced the crash. So the first thing to build is the instrument.
///
/// Two questions, and they are **different questions** — say which one you are asking:
///
/// - ``footprint()`` is what the kernel charges us. It is the number jetsam compares against a limit.
/// - ``available()`` is what is left of *this process's* limit. It needs no hardcoded 120 MB, and it is the honest
///   answer on a device whose limit is not what we assumed.
///
/// Both are cheap enough to call on every page change and around every decode.
///
/// **Everything here logs at `.notice`, not `.info`, and that is deliberate.** An `.info` message lives in a memory
/// ring buffer and is never written to the log store, so it is lost unless somebody happened to be streaming at that
/// instant — and the instant that matters here is the one where the extension is killed. `.notice` is persisted, so a
/// run that ends in a jetsam kill can still be read back afterwards with `log collect` or a sysdiagnose. It is also
/// visible in Console without the "Include Info Messages" toggle, which is a silent way to lose a whole walk.
public enum PreviewMemory {

    /// Our physical footprint, in bytes — the quantity jetsam measures.
    ///
    /// `phys_footprint` rather than `resident_size`: resident size counts pages shared with other processes and clean
    /// pages the kernel can take back at will, so it is both larger and less relevant than what we are billed for.
    public static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let outcome = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        guard outcome == KERN_SUCCESS else { return 0 }
        return info.phys_footprint
    }

    /// How many bytes this process may still allocate before it is killed, or nil when the platform declines to say.
    ///
    /// `os_proc_available_memory()` is documented to answer 0 outside a memory-limited process, so a 0 is reported as
    /// *unknown* rather than as *nothing left* — the two would read identically in a log and mean opposite things.
    public static func available() -> Int? {
        let bytes = os_proc_available_memory()
        return bytes > 0 ? bytes : nil
    }

    /// The pair of them, formatted for a log line: `footprint=54.3MB available=61.7MB`.
    ///
    /// Always both, and always in the same order, so a column can be read down a log without parsing.
    public static func description() -> String {
        let availableDescription = available().map { megabytes(UInt64($0)) } ?? "?"
        return "footprint=\(megabytes(footprint())) available=\(availableDescription)"
    }

    /// Reports the footprint at a named point in the launch, so a step can be attributed rather than guessed at.
    ///
    /// It exists for one number: **+22.8 MB between the end of `initialize()` and the start of the item-provider
    /// load**, identical to the decimal with two shared photographs and with nine — so a fixed cost of getting the
    /// screen up, and, once the previews were bounded, the largest single item in the budget. Nothing attributes it,
    /// and it cannot be attributed by reading: the region spans a `UIHostingController`'s first `view` access, an
    /// authentication controller, a deferred `Task`, and SwiftUI's first layout, several of which do not run in
    /// source order.
    public static func mark(_ name: String) {
        logger.notice("📤🧠 mark \(name, privacy: .public) \(description(), privacy: .public)")
    }


    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "PreviewMemory")


    /// Bytes as megabytes to one decimal, without a space, so a log line stays one field per column.
    public static func megabytes(_ bytes: UInt64) -> String {
        String(format: "%.1fMB", Double(bytes) / (1024 * 1024))
    }

    /// What a bitmap of this pixel size will weigh, at four bytes a pixel.
    ///
    /// Predicted *before* the decode, so it can be compared against what the decode actually returned. If the two
    /// disagree, the arithmetic that chose the size is wrong — which is exactly the kind of error that hides behind a
    /// correct-looking preview.
    public static func predictedBytes(forPixelSize pixelSize: CGSize) -> UInt64 {
        UInt64(max(0, pixelSize.width.rounded())) * UInt64(max(0, pixelSize.height.rounded())) * 4
    }


}


// MARK: - The decodes currently allocating

/// How many previews are being decoded **at this instant**.
///
/// This is the field the whole investigation turns on. The hypothesis is that a fast swipe has several bitmaps in
/// flight at once — the prefetch being fire-and-forget, uncancellable, and inserted into the cache before any
/// cancellation check — and that the cache's byte ceiling cannot defend against it, eviction happening only *after* an
/// insert. A counter is the only way to tell that apart from a steady state that merely grew too large.
///
/// **It must show more than one in the baseline run.** If it never does, the hypothesis is wrong and the fix that
/// serialises decodes would be verified against a case that never arose — which is the same trap as a guard that
/// refuses in silence, met from the outside.
@MainActor
public final class DecodesInFlight {

    public static let shared = DecodesInFlight()

    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "PreviewMemory")

    private var count = 0

    private init() {}

    /// Reports a decode about to start, and returns the number in flight **including this one**.
    ///
    /// Every field is written unconditionally: a probe that says nothing when it declines cannot be told from one that
    /// was never called, and that has already cost two rounds of reasoning elsewhere in this codebase.
    public func began(_ kind: String,
                      url: URL,
                      boxInPoints: CGSize,
                      displayScale: CGFloat,
                      sourcePixelSize: CGSize?,
                      aspectRatio: CGFloat?,
                      pixelSize: CGSize,
                      maxPixelSize: Int) -> Int {
        count += 1
        let ratio = aspectRatio.map { String(format: "%.3f", $0) } ?? "?"
        // The size of the file itself, read from its header. Added after the first run on a device showed a *single*
        // decode adding 21.2 MB for a bitmap predicted at 10.7 — so ImageIO's working set is a term in this, and the
        // question it raises is whether that term scales with the source or with the thumbnail. Without this field
        // there is no way to tell those apart.
        let source = sourcePixelSize.map { "\(Int($0.width))x\(Int($0.height))" } ?? "?"
        Self.logger.notice("📤🧠 decode.start \(kind, privacy: .public) \(url.lastPathComponent, privacy: .public) src=\(source, privacy: .public) box=\(Int(boxInPoints.width), privacy: .public)x\(Int(boxInPoints.height), privacy: .public)pt scale=\(Int(displayScale), privacy: .public) ratio=\(ratio, privacy: .public) px=\(Int(pixelSize.width), privacy: .public)x\(Int(pixelSize.height), privacy: .public) maxPixelSize=\(maxPixelSize, privacy: .public) predicted=\(PreviewMemory.megabytes(PreviewMemory.predictedBytes(forPixelSize: pixelSize)), privacy: .public) inFlight=\(self.count, privacy: .public) \(PreviewMemory.description(), privacy: .public)")
        return count
    }

    /// Reports a decode that has finished, whatever became of its result.
    ///
    /// `stillWanted` is what today's code never asks: the result of a decode whose page has scrolled away is inserted
    /// into the cache regardless, which is what lets a fast swipe accumulate. Logging it now says how often that
    /// happens before anything is changed about it.
    public func ended(_ kind: String,
                      url: URL,
                      actualPixelSize: CGSize?,
                      actualBytes: UInt64?,
                      stillWanted: Bool) {
        count = max(0, count - 1)
        let size = actualPixelSize.map { "\(Int($0.width))x\(Int($0.height))" } ?? "nil"
        let bytes = actualBytes.map { PreviewMemory.megabytes($0) } ?? "nil"
        Self.logger.notice("📤🧠 decode.end   \(kind, privacy: .public) \(url.lastPathComponent, privacy: .public) px=\(size, privacy: .public) actual=\(bytes, privacy: .public) stillWanted=\(stillWanted, privacy: .public) inFlight=\(self.count, privacy: .public) \(PreviewMemory.description(), privacy: .public)")
    }

}
