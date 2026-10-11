import SwiftUI
import UniformTypeIdentifiers
import ImageIO

enum ImageExporter {
    static func png(pixels: [UInt8]) throws -> Data {
        guard let image = ImageRenderer.image(from: pixels),
              let data = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw ExportError.failed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ExportError.failed }
        return data as Data
    }
}

enum ExportError: Error, LocalizedError {
    case failed
    var errorDescription: String? { "无法生成 PNG 图片，请重试。" }
}

struct PNGDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.png] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw ExportError.failed }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct PNGShare: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.data }
            .suggestedFileName("SSTV-Robot36.png")
    }
}
