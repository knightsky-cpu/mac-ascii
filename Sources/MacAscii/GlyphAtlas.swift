import CoreGraphics
import CoreText
import Metal

final class GlyphAtlas {
    static let glyphs = Array(" .-,'`:;coOP0Q&8%B@#_|/\\")

    let texture: MTLTexture
    let glyphCount: Int
    let cellSize: SIMD2<Int32>

    private init(texture: MTLTexture, glyphCount: Int, cellSize: SIMD2<Int32>) {
        self.texture = texture
        self.glyphCount = glyphCount
        self.cellSize = cellSize
    }

    static func make(device: MTLDevice) -> GlyphAtlas? {
        let cellWidth = 40
        let cellHeight = 64
        let atlasWidth = cellWidth * glyphs.count
        let atlasHeight = cellHeight
        let bytesPerRow = atlasWidth
        var pixels = [UInt8](repeating: 0, count: atlasWidth * atlasHeight)

        guard let context = CGContext(
            data: &pixels,
            width: atlasWidth,
            height: atlasHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.setFillColor(gray: 0.0, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: atlasWidth, height: atlasHeight))
        context.translateBy(x: 0.0, y: CGFloat(atlasHeight))
        context.scaleBy(x: 1.0, y: -1.0)
        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)
        context.setFillColor(gray: 1.0, alpha: 1.0)

        let font = CTFontCreateWithName("Menlo-Bold" as CFString, 50.0, nil)
        let attributes = [
            kCTFontAttributeName: font,
            kCTForegroundColorFromContextAttributeName: true,
        ] as CFDictionary

        for (index, glyph) in glyphs.enumerated() {
            let string = String(glyph) as CFString
            let attributedString = CFAttributedStringCreate(nil, string, attributes)!
            let line = CTLineCreateWithAttributedString(attributedString)
            let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds, .useOpticalBounds])
            let cellRect = CGRect(x: index * cellWidth, y: 0, width: cellWidth, height: cellHeight)
            let x = cellRect.minX + ((cellRect.width - bounds.width) * 0.5) - bounds.minX
            let y = cellRect.minY + ((cellRect.height - bounds.height) * 0.5) - bounds.minY
            context.textPosition = CGPoint(x: x, y: y)
            CTLineDraw(line, context)
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: atlasWidth,
            height: atlasHeight,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }

        texture.replace(
            region: MTLRegionMake2D(0, 0, atlasWidth, atlasHeight),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: bytesPerRow
        )

        return GlyphAtlas(
            texture: texture,
            glyphCount: glyphs.count,
            cellSize: SIMD2(Int32(cellWidth), Int32(cellHeight))
        )
    }
}
