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
import os.log
import WebRTC
import OlvidUtils


protocol CreateAndSetLocalDescriptionIfAppropriateOperationDelegate: AnyObject {
    func getReconnectAnswerCounter(op: CreateAndSetLocalDescriptionIfAppropriateOperation) async -> Int
    func getReconnectOfferCounter(op: CreateAndSetLocalDescriptionIfAppropriateOperation) async -> Int
    func incrementReconnectOfferCounter(op: CreateAndSetLocalDescriptionIfAppropriateOperation) async
}


final class CreateAndSetLocalDescriptionIfAppropriateOperation: AsyncOperationWithSpecificReasonForCancel<CreateAndSetLocalDescriptionIfAppropriateOperation.ReasonForCancel> {

    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "CreateAndSetLocalDescriptionIfAppropriateOperation")

    private let peerConnection: ObvPeerConnection
    private let gatheringPolicy: OlvidCallGatheringPolicy
    private let maxaveragebitrate: Int?
    private weak var delegate: CreateAndSetLocalDescriptionIfAppropriateOperationDelegate?

    init(peerConnection: ObvPeerConnection, gatheringPolicy: OlvidCallGatheringPolicy, maxaveragebitrate: Int?, delegate: CreateAndSetLocalDescriptionIfAppropriateOperationDelegate) {
        self.peerConnection = peerConnection
        self.gatheringPolicy = gatheringPolicy
        self.maxaveragebitrate = maxaveragebitrate
        self.delegate = delegate
    }

    
    private(set) var gaetheringStateNeedsToBeReset = false
    private(set) var toSend: (filteredSessionDescription: RTCSessionDescription, reconnectCounter: Int, peerReconnectCounterToOverride: Int)?
    
    override func main() async {

        os_log("☎️ [WebRTCOperation][CreateAndSetLocalDescriptionIfAppropriateOperation] Start", log: Self.log, type: .info)
        defer { os_log("☎️ [WebRTCOperation][CreateAndSetLocalDescriptionIfAppropriateOperation] Finish", log: Self.log, type: .info) }

        guard let delegate else { assertionFailure(); return finish() }
        
        // Check that the current state is not closed
        
        guard peerConnection.connectionState != .closed else {
            os_log("☎️ [WebRTCOperation][CreateAndSetLocalDescriptionIfAppropriateOperation] Since the peer connection is in a closed state, we do not negotiate", log: Self.log, type: .info)
            return finish()
        }

        // Create session description
        
        os_log("☎️ [WebRTCOperation][CreateAndSetLocalDescriptionIfAppropriateOperation] Creating session description", log: Self.log, type: .info)

        let sessionDescription: RTCSessionDescription?
        do {
            sessionDescription = try await createLocalDescriptionIfAppropriateForCurrentSignalingState()
        } catch {
            assertionFailure()
            return cancel(withReason: .localDescriptionCreationFailed(error: error))
        }
        
        guard let sessionDescription else {
            // No need to set a local decription
            os_log("☎️ [WebRTCOperation][CreateAndSetLocalDescriptionIfAppropriateOperation] No need to set a local description", log: Self.log, type: .info)
            return finish()
        }

        // Filter the session description we just created

        let filteredSessionDescription: RTCSessionDescription
        do {
            os_log("☎️ Filtering SDP...", log: Self.log, type: .info)
            filteredSessionDescription = try self.filterSdpDescriptionAudioCodec(rtcSessionDescription: sessionDescription)
            //os_log("☎️ Filtered SDP: %{public}@", log: Self.log, type: .info, filteredSessionDescription.sdp)
        } catch {
            return cancel(withReason: .filterLocalSessionDescriptionFailed(error: error))
        }
        
        // Set the filtered session description
        
        do {
            os_log("☎️ [WebRTCOperation][CreateAndSetLocalDescriptionIfAppropriateOperation] Setting local (filtered) SDP...", log: Self.log, type: .info)
            try await peerConnection.setLocalDescription(filteredSessionDescription)
            os_log("☎️ [WebRTCOperation][CreateAndSetLocalDescriptionIfAppropriateOperation] The filtered SDP was set", log: Self.log, type: .info)
        } catch {
            assertionFailure()
            os_log("☎️ [WebRTCOperation][CreateAndSetLocalDescriptionIfAppropriateOperation] Failed to set the filtered SDP", log: Self.log, type: .fault)
            return cancel(withReason: .setLocalDescriptionFailed(error: error))
        }


        switch gatheringPolicy {
        case .gatherOnce:
            gaetheringStateNeedsToBeReset = true
        case .gatherContinually:
            switch filteredSessionDescription.type {
            case .offer:
                let reconnectAnswerCounter = await delegate.getReconnectAnswerCounter(op: self)
                let reconnectOfferCounter = await delegate.getReconnectOfferCounter(op: self)
                os_log("☎️ [WebRTCOperation][CreateAndSetLocalDescriptionIfAppropriateOperation] We will send the SDP as an offer (reconnectCounter=%d, peerReconnectCounterToOverride=%d)", log: Self.log, type: .info, reconnectOfferCounter, reconnectAnswerCounter)
                toSend = (filteredSessionDescription, reconnectOfferCounter, reconnectAnswerCounter)
            case .answer:
                let reconnectAnswerCounter = await delegate.getReconnectAnswerCounter(op: self)
                os_log("☎️ [WebRTCOperation][CreateAndSetLocalDescriptionIfAppropriateOperation] We will send the SDP as an answer (reconnectCounter=%d, peerReconnectCounterToOverride=-1)", log: Self.log, type: .info, reconnectAnswerCounter)
                toSend = (filteredSessionDescription, reconnectAnswerCounter, -1)
            case .prAnswer, .rollback:
                assertionFailure()
            @unknown default:
                assertionFailure()
            }
        }

        return finish()

    }
    
    
    private func createLocalDescriptionIfAppropriateForCurrentSignalingState() async throws -> RTCSessionDescription? {
        os_log("☎️ [WebRTCOperation][CreateAndSetLocalDescriptionIfAppropriateOperation] Calling Create Local Description if appropriate for the current signaling state", log: Self.log, type: .info)
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        switch peerConnection.signalingState {
        case .stable:
            os_log("☎️ [WebRTCOperation][CreateAndSetLocalDescriptionIfAppropriateOperation] We are in a stable state --> create offer", log: Self.log, type: .info)
            await delegate.incrementReconnectOfferCounter(op: self)
            let offer = try await peerConnection.offer(for: constraints)
            return offer
        case .haveRemoteOffer:
            os_log("☎️ [WebRTCOperation][CreateAndSetLocalDescriptionIfAppropriateOperation] We are in a haveRemoteOffer state --> create answer", log: Self.log, type: .info)
            let answer = try await peerConnection.answer(for: constraints)
            return answer
        case .haveLocalOffer, .haveLocalPrAnswer, .haveRemotePrAnswer, .closed:
            os_log("☎️ [WebRTCOperation][CreateAndSetLocalDescriptionIfAppropriateOperation] We are neither in a stable or a haveRemoteOffer state, we do not create any offer", log: Self.log, type: .info)
            return nil
        @unknown default:
            assertionFailure()
            return nil
        }
    }

    
    // MARK: - Filtering session descriptions

    private static let audioCodecs = Set(["opus", "PCMU", "PCMA", "telephone-event", "red"])

    
    /// This method returns a session description containing the same medias than the received one, but with a filtered audio description
    private func filterSdpDescriptionAudioCodec(rtcSessionDescription: RTCSessionDescription) throws -> RTCSessionDescription {

        let sessionDescription = rtcSessionDescription.sdp
        
        let mediaStartAudio = try NSRegularExpression(pattern: "^m=audio\\s+", options: .anchorsMatchLines)
        let mediaStart = try NSRegularExpression(pattern: "^m=", options: .anchorsMatchLines)
        let lines = sessionDescription.split(whereSeparator: { $0.isNewline }).map({String($0)})
        var audioSectionStarted = false
        var audioLines = [String]()
        var filteredLines = [String]()
        for line in lines {
            if audioSectionStarted {
                let isFirstLineOfAnotherMediaSection = mediaStart.numberOfMatches(in: line, options: [], range: NSRange(location: 0, length: line.count)) > 0
                if isFirstLineOfAnotherMediaSection {
                    audioSectionStarted = false
                    // The audio section has ended, we can process all the audio lines we gathered
                    let filteredAudioLines = try processAudioLines(audioLines)
                    filteredLines.append(contentsOf: filteredAudioLines)
                    filteredLines.append(line)
                } else {
                    audioLines.append(line)
                }
            } else {
                let isFirstLineOfAudioSection = mediaStartAudio.numberOfMatches(in: line, options: [], range: NSRange(location: 0, length: line.count)) > 0
                if isFirstLineOfAudioSection {
                    audioSectionStarted = true
                    audioLines.append(line)
                } else {
                    filteredLines.append(line)
                }
            }
        }
        if audioSectionStarted {
            // In case the audio section was the last section of the session description
            audioSectionStarted = false
            let filteredAudioLines = try processAudioLines(audioLines)
            filteredLines.append(contentsOf: filteredAudioLines)
        }
        let filteredSessionDescription = filteredLines.joined(separator: "\r\n").appending("\r\n")
        return RTCSessionDescription(type: rtcSessionDescription.type, sdp: filteredSessionDescription)
    }

    
    private func processAudioLines(_ audioLines: [String]) throws -> [String] {

        let rtpmapPattern = try NSRegularExpression(pattern: "^a=rtpmap:([0-9]+)\\s+([^\\s/]+)", options: .anchorsMatchLines)

        // First pass
        var formatsToKeep = Set<String>()
        var opusFormat: String?
        for line in audioLines {
            guard let result = rtpmapPattern.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.count)) else { continue }
            let formatRange = result.range(at: 1)
            let codecRange = result.range(at: 2)
            let format = (line as NSString).substring(with: formatRange)
            let codec = (line as NSString).substring(with: codecRange)
            guard Self.audioCodecs.contains(codec) else { continue }
            formatsToKeep.insert(format)
            if codec == "opus" {
                opusFormat = format
            }
        }

        assert(opusFormat != nil)

        // Second pass
        // 1. Rewrite the first line (only keep the formats to keep)
        var processedAudioLines = [String]()
        do {
            let firstLine = try NSRegularExpression(pattern: "^(m=\\S+\\s+\\S+\\s+\\S+)\\s+(([0-9]+\\s*)+)$", options: .anchorsMatchLines)
            guard let result = firstLine.firstMatch(in: audioLines[0], options: [], range: NSRange(location: 0, length: audioLines[0].count)) else {
                throw ObvError.couldNotFindExpectedMatchInSDP
            }
            let processedFirstLine = (audioLines[0] as NSString)
                .substring(with: result.range(at: 1))
                .appending(" ")
                .appending(
                    (audioLines[0] as NSString)
                        .substring(with: result.range(at: 2))
                        .split(whereSeparator: { $0.isWhitespace })
                        .map({String($0)})
                        .filter({ formatsToKeep.contains($0) })
                        .joined(separator: " "))
            processedAudioLines.append(processedFirstLine)
        }
        // 2. Filter subsequent lines
        let rtpmapOrOptionPattern = try NSRegularExpression(pattern: "^a=(rtpmap|fmtp|rtcp-fb):([0-9]+)\\s+", options: .anchorsMatchLines)

        for i in 1..<audioLines.count {
            let line = audioLines[i]
            guard let result = rtpmapOrOptionPattern.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.count)) else {
                processedAudioLines.append(line)
                continue
            }
            let lineTypeRange = result.range(at: 1)
            let lineType = (line as NSString).substring(with: lineTypeRange)
            let formatRange = result.range(at: 2)
            let format = (line as NSString).substring(with: formatRange)
            guard formatsToKeep.contains(format) else { continue }
            if let opusFormat = opusFormat, format == opusFormat, "ftmp" == lineType {
                let modifiedLine = line.appending(self.additionalOpusOptions)
                processedAudioLines.append(modifiedLine)
            } else {
                processedAudioLines.append(line)
            }
        }
        return processedAudioLines
    }

    
    private var additionalOpusOptions: String {
        var options = [(name: String, value: String)]()
        options.append(("cbr", "1"))
        if let maxaveragebitrate {
            options.append(("maxaveragebitrate", "\(maxaveragebitrate)"))
        }
        let optionsAsString = options.reduce("") { $0.appending(";\($1.name)=\($1.value)") }
        debugPrint(optionsAsString)
        return optionsAsString
    }

    
    // MARK: - Errors
    
    enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case localDescriptionCreationFailed(error: Error)
        case filterLocalSessionDescriptionFailed(error: Error)
        case setLocalDescriptionFailed(error: Error)
        
        var logType: OSLogType {
            return .fault
        }
    }

    
    enum ObvError: Error {
        case couldNotFindExpectedMatchInSDP
        case delegateIsNil
    }
    
}
