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

import Foundation
import os.log
import WebRTC
import OlvidUtils



final class CreateAndSetLocalDescriptionIfAppropriateOperation: AsyncOperationWithSpecificReasonForCancel<CreateAndSetLocalDescriptionIfAppropriateOperation.ReasonForCancel> {

    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "CreateAndSetLocalDescriptionIfAppropriateOperation")

    private let peerConnection: ObvPeerConnection
    private let gatheringPolicy: OlvidCallGatheringPolicy
    private(set) var reconnectOfferCounter: Int
    private let reconnectAnswerCounter: Int
    private let maxaveragebitrate: Int?

    init(peerConnection: ObvPeerConnection, gatheringPolicy: OlvidCallGatheringPolicy, reconnectOfferCounter: Int, reconnectAnswerCounter: Int, maxaveragebitrate: Int?) {
        self.peerConnection = peerConnection
        self.gatheringPolicy = gatheringPolicy
        self.reconnectOfferCounter = reconnectOfferCounter
        self.reconnectAnswerCounter = reconnectAnswerCounter
        self.maxaveragebitrate = maxaveragebitrate
    }

    
    private(set) var gaetheringStateNeedsToBeReset = false
    private(set) var toSend: (filteredSessionDescription: RTCSessionDescription, reconnectCounter: Int, peerReconnectCounterToOverride: Int)?
    
    override func main() async {

        os_log("☎️ [WebRTCOperation][CreateAndSetLocalDescriptionIfAppropriateOperation] Start", log: Self.log, type: .info)
        defer { os_log("☎️ [WebRTCOperation][CreateAndSetLocalDescriptionIfAppropriateOperation] Finish", log: Self.log, type: .info) }

        // Check that the current state is not closed
        
        guard peerConnection.connectionState != .closed else {
            os_log("☎️ Since the peer connection is in a closed state, we do not negotiate", log: Self.log, type: .info)
            return finish()
        }

        // Create session description
        
        os_log("☎️ Creating session description", log: Self.log, type: .info)

        let sessionDescription: RTCSessionDescription?
        do {
            sessionDescription = try await createLocalDescriptionIfAppropriateForCurrentSignalingState()
        } catch {
            return cancel(withReason: .localDescriptionCreationFailed(error: error))
        }
        
        guard let sessionDescription else {
            // No need to set a local decription
            os_log("☎️ No need to set a local description", log: Self.log, type: .info)
            return finish()
        }

        // Filter the session description we just created

        let filteredSessionDescription: RTCSessionDescription
        do {
            os_log("☎️ Filtering SDP...", log: Self.log, type: .info)
            filteredSessionDescription = try self.filterSdpDescriptionCodec(rtcSessionDescription: sessionDescription)
            //os_log("☎️ Filtered SDP: %{public}@", log: Self.log, type: .info, filteredSessionDescription.sdp)
        } catch {
            return cancel(withReason: .filterLocalSessionDescriptionFailed(error: error))
        }
        
        // Set the filtered session description
        
        do {
            os_log("☎️ Setting local (filtered) SDP...", log: Self.log, type: .info)
            try await peerConnection.setLocalDescription(filteredSessionDescription)
            os_log("☎️ The filtered SDP was set", log: Self.log, type: .info)
        } catch {
            os_log("☎️ Failed to set the filtered SDP", log: Self.log, type: .fault)
            return cancel(withReason: .setLocalDescriptionFailed(error: error))
        }


        switch gatheringPolicy {
        case .gatherOnce:
            gaetheringStateNeedsToBeReset = true
        case .gatherContinually:
            switch filteredSessionDescription.type {
            case .offer:
                toSend = (filteredSessionDescription, reconnectOfferCounter, reconnectAnswerCounter)
            case .answer:
                toSend = (filteredSessionDescription, reconnectAnswerCounter, -1)
            case .prAnswer, .rollback:
                assertionFailure()
            @unknown default:
                assertionFailure()
            }
        }

        os_log("☎️ Finishing the CreateAndSetLocalDescriptionIfAppropriateOperation", log: Self.log, type: .info)

        return finish()

    }
    
    
    private func createLocalDescriptionIfAppropriateForCurrentSignalingState() async throws -> RTCSessionDescription? {
        os_log("☎️ Calling Create Local Description if appropriate for the current signaling state", log: Self.log, type: .info)
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        switch peerConnection.signalingState {
        case .stable:
            os_log("☎️ We are in a stable state --> create offer", log: Self.log, type: .info)
            reconnectOfferCounter += 1
            let offer = try await peerConnection.offer(for: constraints)
            return offer
        case .haveRemoteOffer:
            os_log("☎️ We are in a haveRemoteOffer state --> create answer", log: Self.log, type: .info)
            let answer = try await peerConnection.answer(for: constraints)
            return answer
        case .haveLocalOffer, .haveLocalPrAnswer, .haveRemotePrAnswer, .closed:
            os_log("☎️ We are neither in a stable or a haveRemoteOffer state, we do not create any offer", log: Self.log, type: .info)
            return nil
        @unknown default:
            assertionFailure()
            return nil
        }
    }

    
    // MARK: - Filtering session descriptions

    private static let audioCodecs = Set(["opus", "PCMU", "PCMA", "telephone-event", "red"])

    
    private func filterSdpDescriptionCodec(rtcSessionDescription: RTCSessionDescription) throws -> RTCSessionDescription {

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
                    // The audio section has ended, we can process all the audio lines with gathered
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
    }
    
}



//final class CreateAndSetLocalDescriptionIfAppropriateOperation: OperationWithSpecificReasonForCancel<CreateAndSetLocalDescriptionIfAppropriateOperation.ReasonForCancel> {
//
//    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "CreateAndSetLocalDescriptionIfAppropriateOperation")
//
//    private let peerConnection: RTCPeerConnection
//    private let gatheringPolicy: GatheringPolicy
//    private(set) var reconnectOfferCounter: Int
//    private let reconnectAnswerCounter: Int
//    private let maxaveragebitrate: Int?
//
//    init(peerConnection: RTCPeerConnection, gatheringPolicy: GatheringPolicy, reconnectOfferCounter: Int, reconnectAnswerCounter: Int, maxaveragebitrate: Int?) {
//        self.peerConnection = peerConnection
//        self.gatheringPolicy = gatheringPolicy
//        self.reconnectOfferCounter = reconnectOfferCounter
//        self.reconnectAnswerCounter = reconnectAnswerCounter
//        self.maxaveragebitrate = maxaveragebitrate
//    }
//
//    
//    private(set) var gaetheringStateNeedsToBeReset = false
//    private(set) var toSend: (filteredSessionDescription: RTCSessionDescription, reconnectCounter: Int, peerReconnectCounterToOverride: Int)?
//    
//    
//    private var _isFinished = false {
//        willSet { willChangeValue(for: \.isFinished) }
//        didSet { didChangeValue(for: \.isFinished) }
//    }
//    
//    
//    final public override var isFinished: Bool { _isFinished }
//
//    
//    final public override func cancel(withReason reason: ReasonForCancel) {
//        super.cancel(withReason: reason)
//        _isFinished = true
//    }
//    
//
//    final public func finish() {
//        _isFinished = true
//    }
//
//    
//    override func main() {
//
//        os_log("☎️ [WebRTCOperation][CreateAndSetLocalDescriptionIfAppropriateOperation] Start", log: Self.log, type: .info)
//        defer { os_log("☎️ [WebRTCOperation][CreateAndSetLocalDescriptionIfAppropriateOperation] Finish", log: Self.log, type: .info) }
//
//        // Check that the current state is not closed
//        
//        guard peerConnection.connectionState != .closed else {
//            os_log("☎️ Since the peer connection is in a closed state, we do not negotiate", log: Self.log, type: .info)
//            return finish()
//        }
//
//        // Create session description
//        
//        os_log("☎️ Creating session description", log: Self.log, type: .info)
//
//        createLocalDescriptionIfAppropriateForCurrentSignalingState { [weak self] sessionDescription, error in
//            guard let self else { return }
//            if let error {
//                return cancel(withReason: .localDescriptionCreationFailed(error: error))
//            }
//                
//            guard let sessionDescription else {
//                // No need to set a local decription
//                os_log("☎️ No need to set a local description", log: Self.log, type: .info)
//                return finish()
//            }
//
//            // Filter the session description we just created
//
//            let filteredSessionDescription: RTCSessionDescription
//            do {
//                os_log("☎️ Filtering SDP...", log: Self.log, type: .info)
//                filteredSessionDescription = try self.filterSdpDescriptionCodec(rtcSessionDescription: sessionDescription)
//                //os_log("☎️ Filtered SDP: %{public}@", log: Self.log, type: .info, filteredSessionDescription.sdp)
//            } catch {
//                return cancel(withReason: .filterLocalSessionDescriptionFailed(error: error))
//            }
//            
//            // Set the filtered session description
//            
//            os_log("☎️ Setting the filtered SDP...", log: Self.log, type: .info)
//
//            peerConnection.setLocalDescription(filteredSessionDescription) { [weak self] error in
//                guard let self else { return }
//                
//                if let error {
//                    return cancel(withReason: .setLocalDescriptionFailed(error: error))
//                }
//                
//                os_log("☎️ The filtered SDP was set", log: Self.log, type: .info)
//
//                switch gatheringPolicy {
//                case .gatherOnce:
//                    gaetheringStateNeedsToBeReset = true
//                case .gatherContinually:
//                    switch filteredSessionDescription.type {
//                    case .offer:
//                        toSend = (filteredSessionDescription, reconnectOfferCounter, reconnectAnswerCounter)
//                    case .answer:
//                        toSend = (filteredSessionDescription, reconnectAnswerCounter, -1)
//                    case .prAnswer, .rollback:
//                        assertionFailure()
//                    @unknown default:
//                        assertionFailure()
//                    }
//                }
//
//                os_log("☎️ Finishing the CreateAndSetLocalDescriptionIfAppropriateOperation", log: Self.log, type: .info)
//
//                return finish()
//                
//            }
//            
//        }
//        
//    }
//    
//    
//    private func createLocalDescriptionIfAppropriateForCurrentSignalingState(_ completionHandler: @escaping RTCCreateSessionDescriptionCompletionHandler) {
//        os_log("☎️ Calling Create Local Description if appropriate for the current signaling state", log: Self.log, type: .info)
//        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
//        switch peerConnection.signalingState {
//        case .stable:
//            os_log("☎️ We are in a stable state --> create offer", log: Self.log, type: .info)
//            reconnectOfferCounter += 1
//            peerConnection.offer(for: constraints, completionHandler: completionHandler)
//        case .haveRemoteOffer:
//            os_log("☎️ We are in a haveRemoteOffer state --> create answer", log: Self.log, type: .info)
//            peerConnection.answer(for: constraints, completionHandler: completionHandler)
//        case .haveLocalOffer, .haveLocalPrAnswer, .haveRemotePrAnswer, .closed:
//            os_log("☎️ We are neither in a stable or a haveRemoteOffer state, we do not create any offer", log: Self.log, type: .info)
//            completionHandler(nil, nil)
//        @unknown default:
//            assertionFailure()
//            completionHandler(nil, nil)
//        }
//    }
//
//    
//    // MARK: - Filtering session descriptions
//
//    private static let audioCodecs = Set(["opus", "PCMU", "PCMA", "telephone-event", "red"])
//
//    
//    private func filterSdpDescriptionCodec(rtcSessionDescription: RTCSessionDescription) throws -> RTCSessionDescription {
//
//        let sessionDescription = rtcSessionDescription.sdp
//        
//        let mediaStartAudio = try NSRegularExpression(pattern: "^m=audio\\s+", options: .anchorsMatchLines)
//        let mediaStart = try NSRegularExpression(pattern: "^m=", options: .anchorsMatchLines)
//        let lines = sessionDescription.split(whereSeparator: { $0.isNewline }).map({String($0)})
//        var audioSectionStarted = false
//        var audioLines = [String]()
//        var filteredLines = [String]()
//        for line in lines {
//            if audioSectionStarted {
//                let isFirstLineOfAnotherMediaSection = mediaStart.numberOfMatches(in: line, options: [], range: NSRange(location: 0, length: line.count)) > 0
//                if isFirstLineOfAnotherMediaSection {
//                    audioSectionStarted = false
//                    // The audio section has ended, we can process all the audio lines with gathered
//                    let filteredAudioLines = try processAudioLines(audioLines)
//                    filteredLines.append(contentsOf: filteredAudioLines)
//                    filteredLines.append(line)
//                } else {
//                    audioLines.append(line)
//                }
//            } else {
//                let isFirstLineOfAudioSection = mediaStartAudio.numberOfMatches(in: line, options: [], range: NSRange(location: 0, length: line.count)) > 0
//                if isFirstLineOfAudioSection {
//                    audioSectionStarted = true
//                    audioLines.append(line)
//                } else {
//                    filteredLines.append(line)
//                }
//            }
//        }
//        if audioSectionStarted {
//            // In case the audio section was the last section of the session description
//            audioSectionStarted = false
//            let filteredAudioLines = try processAudioLines(audioLines)
//            filteredLines.append(contentsOf: filteredAudioLines)
//        }
//        let filteredSessionDescription = filteredLines.joined(separator: "\r\n").appending("\r\n")
//        return RTCSessionDescription(type: rtcSessionDescription.type, sdp: filteredSessionDescription)
//    }
//
//    
//    private func processAudioLines(_ audioLines: [String]) throws -> [String] {
//
//        let rtpmapPattern = try NSRegularExpression(pattern: "^a=rtpmap:([0-9]+)\\s+([^\\s/]+)", options: .anchorsMatchLines)
//
//        // First pass
//        var formatsToKeep = Set<String>()
//        var opusFormat: String?
//        for line in audioLines {
//            guard let result = rtpmapPattern.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.count)) else { continue }
//            let formatRange = result.range(at: 1)
//            let codecRange = result.range(at: 2)
//            let format = (line as NSString).substring(with: formatRange)
//            let codec = (line as NSString).substring(with: codecRange)
//            guard Self.audioCodecs.contains(codec) else { continue }
//            formatsToKeep.insert(format)
//            if codec == "opus" {
//                opusFormat = format
//            }
//        }
//
//        assert(opusFormat != nil)
//
//        // Second pass
//        // 1. Rewrite the first line (only keep the formats to keep)
//        var processedAudioLines = [String]()
//        do {
//            let firstLine = try NSRegularExpression(pattern: "^(m=\\S+\\s+\\S+\\s+\\S+)\\s+(([0-9]+\\s*)+)$", options: .anchorsMatchLines)
//            guard let result = firstLine.firstMatch(in: audioLines[0], options: [], range: NSRange(location: 0, length: audioLines[0].count)) else {
//                throw ObvError.couldNotFindExpectedMatchInSDP
//            }
//            let processedFirstLine = (audioLines[0] as NSString)
//                .substring(with: result.range(at: 1))
//                .appending(" ")
//                .appending(
//                    (audioLines[0] as NSString)
//                        .substring(with: result.range(at: 2))
//                        .split(whereSeparator: { $0.isWhitespace })
//                        .map({String($0)})
//                        .filter({ formatsToKeep.contains($0) })
//                        .joined(separator: " "))
//            processedAudioLines.append(processedFirstLine)
//        }
//        // 2. Filter subsequent lines
//        let rtpmapOrOptionPattern = try NSRegularExpression(pattern: "^a=(rtpmap|fmtp|rtcp-fb):([0-9]+)\\s+", options: .anchorsMatchLines)
//
//        for i in 1..<audioLines.count {
//            let line = audioLines[i]
//            guard let result = rtpmapOrOptionPattern.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.count)) else {
//                processedAudioLines.append(line)
//                continue
//            }
//            let lineTypeRange = result.range(at: 1)
//            let lineType = (line as NSString).substring(with: lineTypeRange)
//            let formatRange = result.range(at: 2)
//            let format = (line as NSString).substring(with: formatRange)
//            guard formatsToKeep.contains(format) else { continue }
//            if let opusFormat = opusFormat, format == opusFormat, "ftmp" == lineType {
//                let modifiedLine = line.appending(self.additionalOpusOptions)
//                processedAudioLines.append(modifiedLine)
//            } else {
//                processedAudioLines.append(line)
//            }
//        }
//        return processedAudioLines
//    }
//
//    
//    private var additionalOpusOptions: String {
//        var options = [(name: String, value: String)]()
//        options.append(("cbr", "1"))
//        if let maxaveragebitrate {
//            options.append(("maxaveragebitrate", "\(maxaveragebitrate)"))
//        }
//        let optionsAsString = options.reduce("") { $0.appending(";\($1.name)=\($1.value)") }
//        debugPrint(optionsAsString)
//        return optionsAsString
//    }
//
//    
//    // MARK: - Errors
//    
//    enum ReasonForCancel: LocalizedErrorWithLogType {
//        
//        case localDescriptionCreationFailed(error: Error)
//        case filterLocalSessionDescriptionFailed(error: Error)
//        case setLocalDescriptionFailed(error: Error)
//        
//        var logType: OSLogType {
//            return .fault
//        }
//    }
//
//    
//    enum ObvError: Error {
//        case couldNotFindExpectedMatchInSDP
//    }
//    
//}
