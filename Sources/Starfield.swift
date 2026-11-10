import AppKit
import SceneKit
import simd

// SceneKit converts a 2:1 spherical-projection image into an infinitely distant
// background skybox. No star is a scene node or a point inside the arena.
final class ProceduralStarfield {
    let seed: UInt64
    let rotation: simd_quatf
    let phase: Float
    let noiseGrid: [Float]
    let galaxyForward: V3
    let galaxyRight: V3
    let galaxyUp: V3
    private static var cached: [(String,NSImage)] = []
    init(seed: UInt64) {
        self.seed = seed
        var random = Random(state:seed ^ 0x57A2_F1E1_DCAF)
        rotation = simd_quatf(angle:random.range(0,tau),axis:unit(random.vector(1)))
        phase = random.range(0,tau)
        noiseGrid = (0..<(32*32*32)).map { _ in random.next() }
        galaxyForward = unit(random.vector(1))
        galaxyRight = unit(simd_cross(galaxyForward,abs(galaxyForward.y)<0.9 ? V3(0,1,0) : V3(1,0,0)))
        galaxyUp = unit(simd_cross(galaxyRight,galaxyForward))
    }
    func noise(_ p: V3) -> Float {
        let cell = V3(floor(p.x),floor(p.y),floor(p.z)), f = p-cell
        let s = f*f*(V3(repeating:3)-f*2)
        let x = Int(cell.x)&31, y = Int(cell.y)&31, z = Int(cell.z)&31
        let xx = (x+1)&31, yy = (y+1)&31, zz = (z+1)&31
        func value(_ a: Int,_ b: Int,_ c: Int) -> Float { noiseGrid[(c*32+b)*32+a] }
        let a = value(x,y,z)+(value(xx,y,z)-value(x,y,z))*s.x
        let b = value(x,yy,z)+(value(xx,yy,z)-value(x,yy,z))*s.x
        let c = value(x,y,zz)+(value(xx,y,zz)-value(x,y,zz))*s.x
        let d = value(x,yy,zz)+(value(xx,yy,zz)-value(x,yy,zz))*s.x
        let near = a+(b-a)*s.y, far = c+(d-c)*s.y
        return near+(far-near)*s.z
    }
    func glow(_ direction: V3) -> V3 {
        let p = rotation.act(direction)
        let mid = p.x*p.z*0.24+p.x*(p.z*p.z-p.x*p.x)*0.06
        let lane = (p.y-mid)/0.13
        let band = exp(-lane*lane)
        let n1 = noise(p*9+V3(phase,4,7))
        let n2 = noise(p*23+V3(9,phase,2))
        let n3 = noise(p*57+V3(2,11,phase))
        let cloud = n1*0.52+n2*0.31+n3*0.17
        let dust = max(0,min(0.92,(noise(p*19+V3(3,9,phase))-0.38)*2.6))
        let arms = 0.72+0.28*sin((p.x*2+p.z)*5+p.y*12+phase+n1*2)
        let light = band*pow(cloud,1.5)*arms*(1-dust)
        var tint = V3(0.00015,0.00025,0.00075)+V3(0.16,0.19,0.29)*light
        tint += V3(0.015,0.022,0.045)*exp(-lane*lane*0.3)*cloud
        let core = band*pow(max(0,p.z),8)*(0.3+0.6*cloud)*(1-dust*0.6)
        tint += V3(0.15,0.095,0.055)*core
        // A distant inclined two-armed spiral, in addition to the Milky Way band.
        let facing = simd_dot(direction,galaxyForward)
        if facing>0.94 {
            let x = simd_dot(direction,galaxyRight)/facing
            let y = simd_dot(direction,galaxyUp)/(facing*0.58)
            let r = sqrt(x*x+y*y)
            if r<0.28 {
                let angle = atan2(y,x)
                let ridge = pow(0.5+0.5*cos(angle*2-log(max(0.012,r))*4+phase),8)
                let disk = exp(-r*19)*(0.12+ridge*0.9)
                tint += V3(0.30,0.38,0.58)*disk
                tint += V3(0.55,0.39,0.22)*exp(-r*r*1700)
            }
        }
        return tint
    }
    func image(width: Int = 4096) -> NSImage {
        let key = "\(seed)/\(width)"
        if let hit = Self.cached.first(where:{$0.0 == key}) { return hit.1 }
        let height = width/2
        let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:width*4,bitsPerPixel:32)!
        let bytes = bitmap.bitmapData!
        let longitude = (0..<width).map { (sin((Float($0)+0.5)/Float(width)*tau-Float.pi),cos((Float($0)+0.5)/Float(width)*tau-Float.pi)) }
        for y in 0..<height {
            let latitude = Float.pi*(0.5-(Float(y)+0.5)/Float(height))
            let radial = cos(latitude), up = sin(latitude)
            for x in 0..<width {
                let d = V3(longitude[x].0*radial,up,longitude[x].1*radial)
                let c = glow(d), offset = (y*width+x)*4
                // Encode linear radiance into sRGB, with sub-byte dithering to
                // avoid contour bands in very dark interstellar dust.
                let hash = UInt32(truncatingIfNeeded:x &* 73856093 ^ y &* 19349663)
                let dither = Float(hash&255)/255-0.5
                for channel in 0..<3 {
                    let linear = max(0,c[channel])
                    let encoded: Float = linear<=0.0031308 ? linear*12.92 : 1.055*pow(linear,1/2.4)-0.055
                    bytes[offset+channel] = UInt8(max(0,min(255,encoded*255+dither)))
                }
                bytes[offset+3] = 255
            }
        }
        var random = Random(state:seed ^ 0xC05A_05F1)
        let stars = width>=2048 ? 38000 : 500
        let colors = [V3(0.72,0.82,1),V3(1,0.91,0.74),V3(0.94,0.96,1),V3(1,0.69,0.48)]
        for i in 0..<stars {
            let a = random.range(-Float.pi,Float.pi)
            var d: V3
            if i%3 == 0 {
                let latitude = (random.next()+random.next()+random.next()-1.5)*0.18
                d = rotation.inverse.act(V3(sin(a)*cos(latitude),sin(latitude),cos(a)*cos(latitude)))
            } else {
                let y = random.range(-1,1), r = sqrt(max(0,1-y*y))
                d = V3(sin(a)*r,y,cos(a)*r)
            }
            let latitude = asin(max(-1,min(1,d.y)))
            let px = (atan2(d.x,d.z)+Float.pi)/tau*Float(width)-0.5
            let py = (0.5-latitude/Float.pi)*Float(height)-0.5
            let magnitude = random.next(), brightness: Float = magnitude>0.985 ? random.range(0.8,1.5) : random.range(0.16,0.68)
            let radius: Float = width>=2048 ? (magnitude>0.985 ? 0.85 : 0.38) : 0.32
            let rx = radius/max(0.17,cos(latitude)), tint = colors[random.index(colors.count)]
            let xRange = Int(ceil(rx*2.5)), yRange = Int(ceil(radius*2.5))
            for dy in -yRange...yRange { for dx in -xRange...xRange {
                let yy = Int(py)+dy
                guard yy>=0 && yy<height else { continue }
                let xx = ((Int(px)+dx)%width+width)%width
                let sx = (Float(Int(px)+dx)-px)/rx, sy = (Float(yy)-py)/radius
                let intensity = exp(-(sx*sx+sy*sy)*0.65)*brightness
                let offset = (yy*width+xx)*4
                for channel in 0..<3 {
                    bytes[offset+channel] = UInt8(min(255,Float(bytes[offset+channel])+tint[channel]*intensity*255))
                }
            } }
        }
        let image = NSImage(size:NSSize(width:width,height:height)); image.addRepresentation(bitmap)
        Self.cached.append((key,image))
        if Self.cached.count>2 { Self.cached.removeFirst() }
        return image
    }
}

extension Dogfight {
    func makeStarfieldSkybox() {
        // Keep simulation-only fixtures light; rendered reviews and the app use
        // the full 4096x2048 sky. Both use the same directional density function.
        let diagnostic = CommandLine.arguments.contains { $0.hasPrefix("--verify") || $0 == "--combat-benchmark" }
        scene.background.contents = ProceduralStarfield(seed:seed).image(width:diagnostic ? 128 : 4096)
        scene.background.intensity = 1
        scene.background.minificationFilter = .linear
        scene.background.magnificationFilter = .linear
        scene.background.mipFilter = .linear
    }
}
