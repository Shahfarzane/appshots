import Foundation

extension AppshotStore {
    func embedPNGTextChunk(fileURL: URL, key: String, value: String) throws {
        var data = try Data(contentsOf: fileURL)
        let signature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        guard data.starts(with: signature), data.count > 33 else {
            return
        }

        var offset = 8
        var insertOffset: Int?
        while offset + 8 <= data.count {
            let length = Int(data[offset..<offset + 4].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
            let typeStart = offset + 4
            let typeEnd = typeStart + 4
            guard typeEnd <= data.count else { return }
            let type = String(data: data[typeStart..<typeEnd], encoding: .ascii)
            let chunkEnd = offset + 12 + length
            guard chunkEnd <= data.count else { return }

            if type == "IHDR" {
                insertOffset = chunkEnd
                break
            }
            offset = chunkEnd
        }

        guard let insertOffset else {
            return
        }

        let payload = Data("\(key)\u{0}\(value)".utf8)
        var chunk = Data()
        chunk.append(UInt32(payload.count).bigEndianData)
        let typeData = Data("tEXt".utf8)
        chunk.append(typeData)
        chunk.append(payload)
        chunk.append(crc32(typeData + payload).bigEndianData)
        data.insert(contentsOf: chunk, at: insertOffset)
        try data.write(to: fileURL, options: .atomic)
    }

    private func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if crc & 1 == 1 {
                    crc = (crc >> 1) ^ 0xEDB8_8320
                } else {
                    crc >>= 1
                }
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension UInt32 {
    var bigEndianData: Data {
        var value = bigEndian
        return Data(bytes: &value, count: MemoryLayout<UInt32>.size)
    }
}
