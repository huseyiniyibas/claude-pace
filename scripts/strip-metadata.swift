// Removes everything from a PNG except what is needed to draw it: no EXIF, XMP, text
// comments or timestamps. Screenshots and offscreen renders carry such metadata by
// default, and files that get published should not.
//
// It works on the file's chunks and keeps the image data byte for byte, so the pixels
// are exactly what they were. Usage: strip-metadata <file.png>...
import Foundation

/// The chunks that make up the picture and its colours. Everything else is dropped.
let keep: Set<String> = ["IHDR", "PLTE", "tRNS", "IDAT", "IEND", "iCCP", "sRGB", "gAMA", "cHRM", "cICP", "sBIT"]
let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("strip-metadata: \(message)\n".utf8))
    exit(1)
}

for path in CommandLine.arguments.dropFirst() {
    guard let data = FileManager.default.contents(atPath: path), data.count > 8,
          Array(data.prefix(8)) == signature
    else { fail("\(path) is not a PNG") }

    var output = Data(signature)
    var offset = 8
    while offset + 12 <= data.count {
        let length = data[offset..<offset + 4].reduce(0) { ($0 << 8) | Int($1) }
        let type = String(decoding: data[offset + 4..<offset + 8], as: UTF8.self)
        let end = offset + 12 + length   // length + type + data + CRC
        guard end <= data.count else { fail("\(path) is truncated") }
        if keep.contains(type) { output.append(data[offset..<end]) }
        offset = end
    }
    guard FileManager.default.createFile(atPath: path, contents: output) else { fail("cannot write \(path)") }
}
