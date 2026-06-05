import Foundation

enum JSONLStreamReader {
    private static let newline: UInt8 = 0x0A
    private static let carriageReturn: UInt8 = 0x0D

    static func lines(from pipe: Pipe) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let handle = pipe.fileHandleForReading
            let task = Task.detached(priority: .utility) {
                var buffer = Data()
                buffer.reserveCapacity(8 * 1024)
                while !Task.isCancelled {
                    let chunk = handle.availableData
                    if chunk.isEmpty { break }
                    appendChunk(chunk, into: &buffer, continuation: continuation)
                }

                if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8), !line.isEmpty {
                    continuation.yield(line)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
                try? handle.close()
            }
        }
    }

    private static func appendChunk(
        _ chunk: Data,
        into buffer: inout Data,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) {
        var cursor = chunk.startIndex
        while cursor < chunk.endIndex {
            if let nlIndex = chunk[cursor..<chunk.endIndex].firstIndex(of: newline) {
                appendStripped(chunk[cursor..<nlIndex], into: &buffer)
                if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8), !line.isEmpty {
                    continuation.yield(line)
                }
                buffer.removeAll(keepingCapacity: true)
                cursor = chunk.index(after: nlIndex)
            } else {
                appendStripped(chunk[cursor..<chunk.endIndex], into: &buffer)
                break
            }
        }
    }

    private static func appendStripped(_ segment: Data.SubSequence, into buffer: inout Data) {
        guard !segment.isEmpty else { return }
        if segment.contains(carriageReturn) {
            buffer.append(contentsOf: segment.lazy.filter { $0 != carriageReturn })
        } else {
            buffer.append(contentsOf: segment)
        }
    }
}
