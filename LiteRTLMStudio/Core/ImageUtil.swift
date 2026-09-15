import AppKit
import Foundation

/// 이미지 축소 단일 진입점 (T-114).
/// `ChatInputBar.downscaled` 로직 이식. Vision 토큰·시간 폭증 방지용 768px JPEG 변환.
enum ImageUtil {
    struct Downscaled {
        let data: Data
        let mime: String
        let note: String
    }

    nonisolated static func downscaledJPEG(_ data: Data, maxSide: CGFloat = 768) -> Downscaled? {
        guard let img = NSImage(data: data) else { return nil }
        let size = img.size
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = NSSize(width: size.width * scale, height: size.height * scale)
        let thumb = NSImage(size: target)
        thumb.lockFocus()
        img.draw(in: NSRect(origin: .zero, size: target))
        thumb.unlockFocus()
        guard let tiff = thumb.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        else { return nil }
        return Downscaled(data: jpeg, mime: "image/jpeg",
                          note: "\(Int(target.width))x\(Int(target.height))")
    }
}
