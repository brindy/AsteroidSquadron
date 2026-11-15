import AppKit
import SceneKit
import simd

enum HaTak {
    static let bayCenter = V3(36,-24,-84)
    static let battery = V3(47,-1.8,-97)

    static func launchPort(side: Float) -> V3 {
        V3(side*bayCenter.x,bayCenter.y,bayCenter.z+0.7)
    }
}

private let haTakPlating = """
#pragma declaration
float hatakHash(float2 p) {
    float3 h = fract(p.xyx*0.1031);
    h += dot(h,h.yzx+33.33);
    return fract((h.x+h.y)*h.z);
}
float hatakPanels(float2 p) {
    float2 tile = p/float2(4.6,7.0);
    tile.x += 0.5*fmod(abs(floor(tile.y)),2.0);
    float2 cell = floor(tile);
    float2 uv = fract(tile);
    float2 edges = min(uv,1.0-uv);
    float seam = smoothstep(0.016,0.043,min(edges.x,edges.y));
    float inset = smoothstep(0.015,0.04,abs(uv.x-0.79))
                 *smoothstep(0.015,0.04,abs(uv.y-0.72));
    return (0.83+0.34*hatakHash(cell))*(0.70+0.30*seam)*(0.86+0.14*inset);
}
#pragma body
float3 p = (scn_node.inverseModelViewTransform*float4(_surface.position,1.0)).xyz;
float3 n = abs(normalize((scn_node.inverseModelViewTransform*float4(_surface.normal,0.0)).xyz));
float3 w = n*n*n*n;
w /= max(0.001,w.x+w.y+w.z);
float panel = dot(w,float3(hatakPanels(p.yz),hatakPanels(p.xz),hatakPanels(p.xy)));
float footprint = max(length(dfdx(p)),length(dfdy(p)));
float detail = 1.0-smoothstep(0.32,2.0,footprint);
_surface.diffuse.rgb *= mix(0.92,panel,detail);
_surface.roughness = mix(0.69,0.92,panel);
"""

private let haTakGold = """
#pragma body
float3 p = (scn_node.inverseModelViewTransform*float4(_surface.position,1.0)).xyz;
float3 n = abs(normalize((scn_node.inverseModelViewTransform*float4(_surface.normal,0.0)).xyz));
float crossFace = n.x>n.z ? p.z : p.x;
float2 band = float2(crossFace*0.41,p.y*0.57);
band.x += fmod(abs(floor(band.y)),2.0)*0.5;
float2 uv = fract(band)-0.5;
float motif = max(abs(uv.x)*1.42+(uv.y+0.42)*0.57,abs(uv.y-0.08)*1.17);
float line = 1.0-smoothstep(0.025,0.091,abs(motif-0.37));
float grain = fract(sin(dot(floor(float2(crossFace,p.y)*3.6),float2(12.9898,78.233)))*43758.5453);
float footprint = max(length(dfdx(p)),length(dfdy(p)));
float detail = 1.0-smoothstep(0.13,1.05,footprint);
float patina = sin(crossFace*0.13+p.y*0.24)*sin(p.y*0.31-crossFace*0.45);
_surface.diffuse.rgb *= 0.9+0.085*patina+detail*(0.27*line+(grain-0.5)*0.23);
_surface.roughness = 0.72-0.16*line*detail;
"""

private func haTakMetal(_ color: NSColor, etched: Bool = false) -> SCNMaterial {
    let metal = material(color,metal:etched ? 0.58 : 0.48)
    metal.roughness.contents = 0.75
    metal.shaderModifiers = [.surface:etched ? haTakGold : haTakPlating]
    return metal
}

private struct HaTakWingSection {
    let z: Float
    let inner: Float
    let outer: Float
    let deck: Float
    let keel: Float

    init(_ z: Float, _ inner: Float, _ outer: Float, _ deck: Float, _ keel: Float) {
        self.z = z; self.inner = inner; self.outer = outer; self.deck = deck; self.keel = keel
    }

    func profile(side: Float) -> [V3] {
        let inset = min(4.8,(outer-inner)*0.20)
        return [V3(side*(inner+inset),deck,z),V3(side*(outer-inset),deck-1.3,z),
                V3(side*outer,deck-4.2,z),V3(side*outer,keel+3,z),
                V3(side*(outer-inset),keel,z),V3(side*(inner+inset),keel,z),
                V3(side*inner,keel+2.5,z),V3(side*inner,deck-3.8,z)]
    }

    func deckPoint(_ fraction: Float, side: Float, lift: Float = 0) -> V3 {
        let inset = min(4.8,(outer-inner)*0.20)
        return V3(side*(inner+inset+(outer-inner-2*inset)*fraction),deck-1.3*fraction+lift,z)
    }
}

private func haTakWing(_ sections: [HaTakWingSection], side: Float,
                       armor: SCNMaterial, walls: SCNMaterial, trim: SCNMaterial) -> SCNNode {
    let rings = sections.map { $0.profile(side:side) }
    let vertices = rings.flatMap { $0 }
    var triangles: [[Int32]] = [[],[],[]]
    var positions: [SCNVector3] = []
    var normals: [SCNVector3] = []

    func face(_ ids: [Int], facing outward: V3, material: Int) {
        for i in 1..<(ids.count-1) {
            var triangle = [ids[0],ids[i],ids[i+1]]
            var normal = unit(simd_cross(vertices[triangle[1]]-vertices[triangle[0]],
                                         vertices[triangle[2]]-vertices[triangle[0]]))
            if simd_dot(normal,outward)<0 { triangle.swapAt(1,2); normal = -normal }
            let index = Int32(positions.count)
            triangles[material] += [index,index+1,index+2]
            positions += triangle.map { SCNVector3(vertices[$0]) }
            normals += Array(repeating:SCNVector3(normal),count:3)
        }
    }

    face(Array(0..<8),facing:V3(0,0,-1),material:1)
    face(Array((vertices.count-8)..<vertices.count),facing:V3(0,0,1),material:1)
    let directions = [V3(0,1,0),V3(side,1,0),V3(side,0,0),V3(side,-1,0),
                      V3(0,-1,0),V3(-side,-1,0),V3(-side,0,0),V3(-side,1,0)]
    let surfaces = [0,0,1,2,1,2,1,0]
    for ring in 0..<(rings.count-1) {
        for edge in directions.indices {
            let a = ring*8+edge, b = ring*8+(edge+1)%8
            face([a,b,b+8,a+8],facing:directions[edge],material:surfaces[edge])
        }
    }
    let geometry = SCNGeometry(sources:[SCNGeometrySource(vertices:positions),SCNGeometrySource(normals:normals)],
                               elements:triangles.map { SCNGeometryElement(indices:$0,primitiveType:.triangles) })
    geometry.materials = [armor,walls,trim]
    return SCNNode(geometry:geometry)
}

private func haTakSlab(_ surface: [V3], depth: Float, material: SCNMaterial) -> SCNNode {
    let underside = surface.map { $0-V3(0,depth,0) }
    return hullMesh(surface+underside,
                    faces:[[0,1,2,3],[4,7,6,5],[0,4,5,1],[1,5,6,2],[2,6,7,3],[3,7,4,0]],mat:material)
}

private func haTakRim(_ stations: [(V3,Float)], depth: Float, material: SCNMaterial) -> SCNNode {
    let edges = stations.map { center, width -> (inner: V3, outer: V3) in
        let offset = unit(V3(center.x,0,center.z))*width
        return (center-offset,center+offset)
    }
    let root = SCNNode()
    for (a,b) in zip(edges,edges.dropFirst()) {
        root.addChildNode(haTakSlab([a.inner,a.outer,b.outer,b.inner],depth:depth,material:material))
    }
    return root.flattenedClone()
}

private func haTakPyramid(gold: SCNMaterial, frame: SCNMaterial,
                         dark: SCNMaterial, lights: SCNMaterial) -> SCNNode {
    let root = SCNNode()
    let apex: Float = 65, base: Float = -58, halfWidth: Float = 52
    func point(_ width: Float, _ y: Float, _ offset: Float = 0) -> V3 {
        let w = halfWidth*(apex-y)/(apex-base)
        return V3(width*w,y,-w-offset)
    }
    let rim = [V3(-halfWidth,base,-halfWidth),V3(halfWidth,base,-halfWidth),
               V3(halfWidth,base,halfWidth),V3(-halfWidth,base,halfWidth)]
    root.addChildNode(hullMesh(rim+[V3(0,apex,0)],faces:[[0,1,2,3],[0,4,1],[1,4,2],[2,4,3],[3,4,0]],mat:gold))
    root.addChildNode(box(V3(110,3.4,110),dark,V3(0,base-1.4,0),chamfer:1.1))
    root.addChildNode(box(V3(101,1.1,101),frame,V3(0,base-3.2,0),chamfer:0.45))

    let deckBands: [(Float,Float)] = [(-11,-1),(24,39)]
    var rng = Random(state:0xA73_A0)
    for face in 0..<4 {
        let facade = SCNNode()
        facade.simdEulerAngles.y = Float(face)*Float.pi/2
        func armor(_ a: Float, _ b: Float, _ from: Float, _ to: Float, material: SCNMaterial) {
            let front = [point(a,from,0.75),point(b,from,0.75),point(b,to,0.75),point(a,to,0.75)]
            let back = front.map { $0+V3(0,0,1.1) }
            facade.addChildNode(hullMesh(front+back,
                faces:[[0,1,2,3],[4,7,6,5],[0,4,5,1],[1,5,6,2],[2,6,7,3],[3,7,4,0]],mat:material))
        }
        for (start,end) in deckBands { armor(-1.0,1.0,start,end,material:frame) }
        for x: Float in [-0.84,0,0.84] {
            armor(x-0.08,x+0.08,base+1,-11,material:x == 0 ? frame : dark)
        }
        var glass: [SCNVector3] = []
        for (start,end) in deckBands {
            for y in stride(from:start+2,through:end-1,by:2.3) {
                for col in -11...11 where rng.next()>0.46 {
                    let x = Float(col)/12
                    let width = rng.range(0.14,0.36), height = rng.range(0.10,0.20)
                    let center = point(x+rng.range(-0.023,0.023),y,0.98)
                    let horizontal = V3(width,0,0), vertical = V3(0,height,height*halfWidth/(apex-base))
                    let a = center-horizontal-vertical, b = center-horizontal+vertical
                    let c = center+horizontal+vertical, d = center+horizontal-vertical
                    glass.append(contentsOf:[a,b,c,a,c,d].map(SCNVector3.init))
                }
            }
        }
        let normal = SCNVector3(unit(V3(0,halfWidth/(apex-base),-1)))
        let glassMesh = SCNGeometry(
            sources:[SCNGeometrySource(vertices:glass),
                     SCNGeometrySource(normals:Array(repeating:normal,count:glass.count))],
            elements:[SCNGeometryElement(indices:Array(0..<Int32(glass.count)),primitiveType:.triangles)])
        facade.addChildNode(node(glassMesh,lights))
        root.addChildNode(facade)
    }
    return root
}

func haTakMothership() -> SCNNode {
    let ship = SCNNode()
    let armor = haTakMetal(color(0.31,0.33,0.36))
    let trim = haTakMetal(color(0.38,0.40,0.42))
    let walls = haTakMetal(color(0.21,0.23,0.26))
    let dark = material(color(0.045,0.054,0.066),metal:0.30)
    let gold = haTakMetal(color(0.77,0.51,0.20),etched:true)
    let windows = material(color(0.71,0.76,0.80),emission:color(0.35,0.42,0.5))
    let amber = material(color(0.86,0.48,0.13),emission:color(0.86,0.36,0.08))
    ship.addChildNode(haTakPyramid(gold:gold,frame:walls,dark:dark,lights:windows))

    let sections = [HaTakWingSection(-112,31,49,-8,-17),HaTakWingSection(-105,28,59,-5,-17),
                    HaTakWingSection(-87,25,68,0,-14),HaTakWingSection(-68,19,64,7,-9),
                    HaTakWingSection(-54,13,52,13,-3),HaTakWingSection(-39,8,36,19,4),
                    HaTakWingSection(-25,2,20,24,11),HaTakWingSection(-17,0.8,10,25,16)]
    let neighbour = simd_quatf(angle:-tau/3,axis:V3(0,1,0))
    let outerRim: [(V3,Float)] = [(V3(58,0.4,-81),6),(V3(77,-0.4,-76),8),
                                  (V3(94,-3.4,-61),9.5),(V3(104,-3.4,-46),9.5),
                                  (V3(106,-0.4,-27),8),(neighbour.act(V3(-58,0.4,-81)),6)]
    let lowerRim: [(V3,Float)] = [(V3(0,-29.7,-82),2.2),(V3(26,-30.0,-80),2),
                                  (V3(51,-33.0,-65),2.6),(V3(69,-33.0,-39),2.6),
                                  (V3(82,-30.0,-16),2),(neighbour.act(V3(0,-29.7,-82)),2.2)]
    var rng = Random(state:0xA7_74A5)
    for sector in 0..<3 {
        let superstructure = SCNNode()
        superstructure.simdEulerAngles.y = Float(sector)*tau/3
        let fittings = SCNNode()
        for side: Float in [-1,1] {
            superstructure.addChildNode(haTakWing(sections,side:side,armor:armor,walls:walls,trim:trim))
            // The dark service channels and raised plates follow the deck slope.
            for (a,b) in zip(sections,sections.dropFirst()).dropLast() {
                let channel = [a.deckPoint(0.53,side:side,lift:0.21),a.deckPoint(0.67,side:side,lift:0.21),
                               b.deckPoint(0.67,side:side,lift:0.21),b.deckPoint(0.53,side:side,lift:0.21)]
                fittings.addChildNode(haTakSlab(channel,depth:0.36,material:walls))
                for range: ClosedRange<Float> in [0.12...0.40,0.72...0.88] {
                    let a0 = a.deckPoint(range.lowerBound,side:side,lift:0.52)
                    let a1 = a.deckPoint(range.upperBound,side:side,lift:0.52)
                    let b0 = b.deckPoint(range.lowerBound,side:side,lift:0.52)
                    let b1 = b.deckPoint(range.upperBound,side:side,lift:0.52)
                    let plate = [mix(a0,b0,0.20),mix(a1,b1,0.20),mix(a1,b1,0.82),mix(a0,b0,0.82)]
                    fittings.addChildNode(haTakSlab(plate,depth:0.65,material:armor))
                }
            }
            for (a,b) in zip(sections,sections.dropFirst()).dropLast() {
                for step in 1...5 {
                    let t = Float(step)/6
                    let z = a.z+(b.z-a.z)*t
                    let x = side*(a.outer+(b.outer-a.outer)*t)
                    let y = a.deck+(b.deck-a.deck)*t
                    let width = rng.range(0.24,0.61)
                    fittings.addChildNode(box(V3(0.36,0.38,width),windows,V3(x,y-5.3,z)))
                    if step%2 == 0 {
                        fittings.addChildNode(box(V3(0.75,1.8,0.73),walls,V3(x,y-7.0,z+0.65),chamfer:0.14))
                    }
                }
            }
            let sensor = cylinder(3.9,0.63,trim,V3(side*44,11.65,-57))
            sensor.eulerAngles.x = 0
            fittings.addChildNode(sensor)
            fittings.addChildNode(segment(V3(side*48,-6,-64),V3(side*50,-32.5,-65),radius:1.65,mat:walls))
        }
        superstructure.addChildNode(haTakRim(outerRim,depth:6.0,material:armor))
        superstructure.addChildNode(haTakRim(lowerRim,depth:2.2,material:walls))
        superstructure.addChildNode(fittings.flattenedClone())
        ship.addChildNode(superstructure)
    }

    for side: Float in [-1,1] {
        let bay = SCNNode()
        bay.name = side<0 ? "port Death Glider bay" : "starboard Death Glider bay"
        bay.simdPosition = V3(side*HaTak.bayCenter.x,HaTak.bayCenter.y,HaTak.bayCenter.z)
        bay.addChildNode(box(V3(25,3.7,21),armor,V3(0,5.9,10.5),chamfer:0.65))
        bay.addChildNode(box(V3(25,1.7,21),walls,V3(0,-4.1,10.5),chamfer:0.45))
        bay.addChildNode(box(V3(23,9,2.4),dark,V3(0,0.55,20)))
        for edge: Float in [-1,1] {
            bay.addChildNode(box(V3(2.25,8.5,20),walls,V3(edge*11.8,0.65,10.4),chamfer:0.55))
            bay.addChildNode(box(V3(0.55,7.0,0.62),trim,V3(edge*11.0,0.5,-0.1),chamfer:0.18))
            for z: Float in [0.7,4.1,7.5,10.9,14.3] {
                bay.addChildNode(box(V3(0.55,0.14,1.75),amber,V3(edge*8.4,-3.15,z)))
            }
        }
        ship.addChildNode(bay)
    }
    return ship
}
