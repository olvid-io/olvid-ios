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
import OSLog
import WebRTC
import ObvAppCoreConstants


actor RTCDataBufferHandler {
    
    private var numberOfLastSentJSonMessage: UInt32?
    private static let maxDataChannelMessageSize: UInt32 = 64*1024 // 65_536
    private static let headerSize: UInt32 = 17

    struct MessageAndChunkNumber: Hashable {
        let messageNumber: UInt32
        let chunkNumber: UInt32
    }

    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "RTCDataBufferHandler")
    
    enum HandleReceivedRTCDataBufferResult {
        case receivedSerializedMessage(type: TransferMessageType, serializedMessage: Data)
        case expectingMoreChunks
    }
    
    /// Stores chunks of partially received Json messages.
    ///
    /// This keys of this dictionary are message numbers. Each value is a dictionary keyed by chunk numbers where the values are the
    /// received bytes of the chunk.
    private var partiallyReceivedJsonMessages = [UInt32: [UInt32: Data]]()
    
    private var continuationForMessageAndChunkNumberToAcknowledge: AsyncStream<MessageAndChunkNumber>.Continuation?
    private var messageAndChunkNumberToAcknowledgeOnSetContinuation = [MessageAndChunkNumber]()

}


// MARK: - Splitting a json message to send into multiple RTCDataBuffers

extension RTCDataBufferHandler {
    
    /// Cuts the data to be sent on the data channel in chunks.
    ///
    /// This method returns an async stream of `RTCDataBuffer`s to be sent, in order, on the data channel.
    /// It allows to ensure that even large amount of `Data` can be handled by the peer connection's data channel.
    func createRTCDataBuffersToSend(type: TransferMessageType, serializedMessage: Data) async -> AsyncStream<(MessageAndChunkNumber, RTCDataBuffer)> {
        
        let stream = AsyncStream<(MessageAndChunkNumber, RTCDataBuffer)> { (continuation: AsyncStream<(MessageAndChunkNumber, RTCDataBuffer)>.Continuation) in
            
            defer { continuation.finish() }
            
            let messageNumber: UInt32
            if let numberOfLastSentJSonMessage {
                messageNumber = numberOfLastSentJSonMessage + 1
            } else {
                messageNumber = 0
            }
            numberOfLastSentJSonMessage = messageNumber

            let rawType = type.rawValue
            let blockSize = Self.maxDataChannelMessageSize - Self.headerSize
            let totalChunks = UInt32(1 + (serializedMessage.count-1)/Int(blockSize))

            var offset: UInt32 = 0
            var chunkNumber: UInt32 = 0
            while offset < serializedMessage.count {
                
                let messageAndChunkNumber = MessageAndChunkNumber(messageNumber: messageNumber, chunkNumber: chunkNumber)
                
                let startIndex = serializedMessage.startIndex.advanced(by: Int(offset))
                let endIndex = min(serializedMessage.endIndex, startIndex.advanced(by: Int(blockSize)))
                let chunkBytes: Data = Data([
                    Data([rawType]),
                    messageNumber.to4Bytes(),
                    chunkNumber.to4Bytes(),
                    totalChunks.to4Bytes(),
                    blockSize.to4Bytes(),
                    serializedMessage[startIndex..<endIndex],
                ].joined())
                let rtcDataBuffer = RTCDataBuffer(data: chunkBytes, isBinary: true)
                
                continuation.yield((messageAndChunkNumber, rtcDataBuffer))
                
                offset += blockSize
                chunkNumber += 1
                
            }

        }
        return stream
    }
    
}


// MARK: - Joining received RTCDataBuffers into a json message

extension RTCDataBufferHandler {
    
    /// When an `RTCDataBuffer` is received on the data channel of the peer connection, this method is called to parse it.
    func handleReceivedRTCDataBuffer(_ buffer: RTCDataBuffer) async throws -> HandleReceivedRTCDataBufferResult {
        
        // Determine the ranges of the headers parts
        
        let rangeOfTransferMessageType = buffer.data.startIndex..<buffer.data.startIndex.advanced(by: 1)
        let rangeOfMessageNumber = rangeOfTransferMessageType.endIndex..<rangeOfTransferMessageType.endIndex.advanced(by: 4)
        let rangeOfChunkNumber = rangeOfMessageNumber.endIndex..<rangeOfMessageNumber.endIndex.advanced(by: 4)
        let rangeOfTotalChunks = rangeOfChunkNumber.endIndex..<rangeOfChunkNumber.endIndex.advanced(by: 4)
        let rangeOfBlockSize = rangeOfTotalChunks.endIndex..<rangeOfTotalChunks.endIndex.advanced(by: 4)
        
        guard rangeOfBlockSize.endIndex < buffer.data.endIndex else {
            assertionFailure()
            throw ObvError.bufferIsEmpty
        }
        
        let rangeOfChunk = rangeOfBlockSize.endIndex..<buffer.data.endIndex
        
        // Parse the header
        
        let transferMessageType = try TransferMessageType(buffer.data[rangeOfTransferMessageType])
        let messageNumber: UInt32 = try UInt32.from4Bytes(buffer.data[rangeOfMessageNumber])
        let chunkNumber: UInt32 = try UInt32.from4Bytes(buffer.data[rangeOfChunkNumber])
        let totalChunks: UInt32 = try UInt32.from4Bytes(buffer.data[rangeOfTotalChunks])
        let blockSize: UInt32 = try UInt32.from4Bytes(buffer.data[rangeOfBlockSize])
        let payload: Data = buffer.data[rangeOfChunk]
        
        Self.logger.debug("📰 Parsed RTCDataBuffer of type \(transferMessageType) with messageNumber: \(messageNumber), chunkNumber: \(chunkNumber), totalChunks: \(totalChunks), blockSize: \(blockSize)")

        // Request the sending of an ack for the received chunk (unless the message type is a ack)
        
        if transferMessageType != .ack {
            messageAndChunkNumberToAcknowledgeOnSetContinuation.insert(.init(messageNumber: messageNumber, chunkNumber: chunkNumber), at: 0)
            yieldMessageAndChunkNumberToAcknowledge()
        }
        
        switch totalChunks {
        case 0:
            assertionFailure()
            throw ObvError.unexpectedTotalChunks
        case 1:
            return .receivedSerializedMessage(type: transferMessageType, serializedMessage: payload)
        default:
            var currentChunks = partiallyReceivedJsonMessages[messageNumber, default: [UInt32 : Data]()]
            assert(currentChunks[chunkNumber] == nil, "Should not receive the same chunk twice")
            currentChunks[chunkNumber] = payload
            if currentChunks.count == totalChunks {
                partiallyReceivedJsonMessages.removeValue(forKey: messageNumber)
                var serializedMessage = Data()
                for chunkNumber in 0..<currentChunks.count {
                    guard let chunk = currentChunks[UInt32(chunkNumber)] else {
                        assertionFailure()
                        throw ObvError.couldNotParseValue
                    }
                    serializedMessage += chunk
                }
                return .receivedSerializedMessage(type: transferMessageType, serializedMessage: serializedMessage)
            } else {
                partiallyReceivedJsonMessages[messageNumber] = currentChunks
                return .expectingMoreChunks
            }
        }

    }
    
}


// MARK: - Streaming a list of received chunks to acknowledge

extension RTCDataBufferHandler {
    
    func getAsyncStreamOfReceivedChunksToAcknowledge() -> AsyncStream<MessageAndChunkNumber> {
        let stream = AsyncStream<MessageAndChunkNumber> { (continuation: AsyncStream<MessageAndChunkNumber>.Continuation) in
            continuationForMessageAndChunkNumberToAcknowledge?.finish()
            continuationForMessageAndChunkNumberToAcknowledge = continuation
            yieldMessageAndChunkNumberToAcknowledge()
        }
        return stream
    }
        
    
    private func yieldMessageAndChunkNumberToAcknowledge() {
        guard let continuationForMessageAndChunkNumberToAcknowledge else { return }
        while let messageAndChunkNumberToAcknowledge = messageAndChunkNumberToAcknowledgeOnSetContinuation.popLast() {
            continuationForMessageAndChunkNumberToAcknowledge.yield(messageAndChunkNumberToAcknowledge)
        }
    }
    
}


// MARK: - Errors

extension RTCDataBufferHandler {
    
    enum ObvError: Error {
        case bufferIsEmpty
        case couldNotDetermineTransferMessageType
        case couldNotParseValue
        case unexpectedTotalChunks
    }
    
}


fileprivate extension UInt32 {
    
    func to4Bytes() -> Data {
        var innerData = Data()
        let byteLenght = 4
        for i in 0..<byteLenght {
            innerData.append(UInt8(self >> (8*(byteLenght - 1 - i)) & 0xFF))
        }
        return innerData
    }
    
    static func from4Bytes(_ data: Data) throws -> Self {
        guard data.count == 4 else {
            assertionFailure()
            throw RTCDataBufferHandler.ObvError.couldNotParseValue
        }
        var value: UInt32 = 0
        for i in data.startIndex..<data.endIndex {
            value = (value << 8) | UInt32(data[i])
        }
        return value
    }
    
}


extension RTCDataBufferHandler.MessageAndChunkNumber: CustomStringConvertible {
    
    var description: String {
        return "MessageAndChunkNumber(messageNumber:\(self.messageNumber),chunkNumber:\(self.chunkNumber))"
    }
    
}


extension RTCDataBufferHandler.MessageAndChunkNumber {
    
    var ackData: Data {
        self.messageNumber.to4Bytes() + self.chunkNumber.to4Bytes()
    }
    
    
    init(ackData: Data) throws {
        
        let rangeOfMessageNumber = ackData.startIndex..<ackData.startIndex.advanced(by: 4)
        let rangeOfChunkNumber = rangeOfMessageNumber.endIndex..<rangeOfMessageNumber.endIndex.advanced(by: 4)
        
        guard rangeOfChunkNumber.endIndex == ackData.endIndex else {
            assertionFailure()
            throw RTCDataBufferHandler.ObvError.couldNotParseValue
        }
        
        let messageNumber: UInt32 = try .from4Bytes(Data(ackData[rangeOfMessageNumber]))
        let chunkNumber: UInt32 = try .from4Bytes(Data(ackData[rangeOfChunkNumber]))
        
        self.init(messageNumber: messageNumber, chunkNumber: chunkNumber)
        
    }
    
}
