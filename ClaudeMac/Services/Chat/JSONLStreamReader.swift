import Foundation

enum JSONLStreamReader {
    static func lines(from pipe: Pipe) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let handle = pipe.fileHandleForReading
            let task = Task.detached(priority: .utility) {
                var buffer = Data()
                while !Task.isCancelled {
                    let chunk = handle.availableData
                    if chunk.isEmpty { break }
                    for byte in chunk {
                        if byte == 10 {
                            if let line = String(data: buffer, encoding: .utf8), !line.isEmpty {
                                continuation.yield(line)
                            }
                            buffer.removeAll(keepingCapacity: true)
                        } else if byte != 13 {
                            buffer.append(byte)
                        }
                    }
                }

                if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8), !line.isEmpty {
                    continuation.yield(line)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
