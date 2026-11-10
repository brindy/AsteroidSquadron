import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Traditional ICNS icons include their own outer spacing. Preserve the chosen
// artwork, fitting it to an 824px footprint on a transparent 1024px canvas.
// This is the compatibility layout for macOS 13+, not an Icon Composer layer.
guard CommandLine.arguments.count == 3,
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath:CommandLine.arguments[1]) as CFURL,nil),
      let artwork = CGImageSourceCreateImageAtIndex(source,0,nil),
      artwork.width == artwork.height, artwork.width >= 1024 else {
    fatalError("Expected a square source icon at least 1024px wide and an output iconset directory")
}
let folder = URL(fileURLWithPath:CommandLine.arguments[2],isDirectory:true)
for points in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels = points*scale
        let context = CGContext(data:nil,width:pixels,height:pixels,bitsPerComponent:8,bytesPerRow:0,
                                space:CGColorSpace(name:CGColorSpace.sRGB)!,
                                bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        let margin = CGFloat(pixels)*100/1024
        context.clear(CGRect(x:0,y:0,width:pixels,height:pixels))
        context.interpolationQuality = .high
        context.draw(artwork,in:CGRect(x:margin,y:margin,width:CGFloat(pixels)-2*margin,height:CGFloat(pixels)-2*margin))
        let suffix = scale == 2 ? "@2x" : ""
        let url = folder.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
        let destination = CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil)!
        CGImageDestinationAddImage(destination,context.makeImage()!,nil)
        precondition(CGImageDestinationFinalize(destination),"Could not write \(url.path)")
    }
}
