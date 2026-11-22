import Foundation

public struct ProjectFile: Decodable, Equatable {
    public let path: String
    public let content: String
}

public struct GeneratedProject: Decodable {
    public let files: [ProjectFile]

    public static func parse(_ output: String) throws -> GeneratedProject {
        var text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```"), let firstLine = text.firstIndex(of: "\n"),
           text.hasSuffix("```") {
            text = String(text[text.index(after: firstLine)..<text.index(text.endIndex, offsetBy: -3)])
        }
        guard let data = text.data(using: .utf8), data.count <= 10_000_000,
              let project = try? JSONDecoder().decode(GeneratedProject.self, from: data),
              !project.files.isEmpty, project.files.count <= 1000 else {
            throw ProjectError.invalidOutput
        }
        var paths = Set<String>()
        for file in project.files {
            let parts = file.path.split(separator: "/", omittingEmptySubsequences: false)
            guard !file.path.isEmpty, file.path.utf8.count <= 1024,
                  !file.path.contains("\\"),
                  !file.path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains(":") }) else {
                throw ProjectError.invalidPath(file.path)
            }
            let path = file.path.precomposedStringWithCanonicalMapping.lowercased()
            guard paths.insert(path).inserted else { throw ProjectError.invalidPath(file.path) }
        }
        for path in paths {
            let components = path.split(separator: "/")
            for index in 1..<components.count {
                guard !paths.contains(components.prefix(index).joined(separator: "/")) else {
                    throw ProjectError.invalidPath(path)
                }
            }
        }
        return project
    }

    public func zipData() throws -> Data {
        var result = Data()
        var directory = Data()
        for file in files {
            let name = Data(file.path.utf8)
            let content = Data(file.content.utf8)
            guard let offset = UInt32(exactly: result.count),
                  let size = UInt32(exactly: content.count),
                  let nameLength = UInt16(exactly: name.count) else { throw ProjectError.tooLarge }
            let crc = Self.crc32(content)
            result.u32(0x04034b50); result.u16(20); result.u16(0x0800); result.u16(0)
            result.u16(0); result.u16(0x0021); result.u32(crc); result.u32(size); result.u32(size)
            result.u16(nameLength); result.u16(0); result.append(name); result.append(content)
            directory.u32(0x02014b50); directory.u16(20); directory.u16(20); directory.u16(0x0800)
            directory.u16(0); directory.u16(0); directory.u16(0x0021); directory.u32(crc)
            directory.u32(size); directory.u32(size); directory.u16(nameLength)
            directory.u16(0); directory.u16(0); directory.u16(0); directory.u16(0)
            directory.u32(0); directory.u32(offset); directory.append(name)
        }
        guard let offset = UInt32(exactly: result.count),
              let size = UInt32(exactly: directory.count),
              let count = UInt16(exactly: files.count) else { throw ProjectError.tooLarge }
        result.append(directory)
        result.u32(0x06054b50); result.u16(0); result.u16(0); result.u16(count); result.u16(count)
        result.u32(size); result.u32(offset); result.u16(0)
        return result
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xedb88320 : 0) }
        }
        return crc ^ 0xffffffff
    }
}

public enum ProjectError: LocalizedError {
    case invalidOutput, invalidPath(String), tooLarge
    public var errorDescription: String? {
        switch self {
        case .invalidOutput: return "Het model gaf geen geldig compleet project terug. Probeer een kleinere of duidelijkere opdracht."
        case .invalidPath(let path): return "Ongeldig of dubbel bestandspad: \(path)"
        case .tooLarge: return "Het project is te groot om te exporteren."
        }
    }
}

private extension Data {
    mutating func u16(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value)); append(UInt8(truncatingIfNeeded: value >> 8))
    }
    mutating func u32(_ value: UInt32) {
        u16(UInt16(truncatingIfNeeded: value)); u16(UInt16(truncatingIfNeeded: value >> 16))
    }
}
