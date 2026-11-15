import AppKit
import SceneKit
import simd

// Model-space plating wraps the hull without relying on an external texture.
private let imperialPlating = """
#pragma declaration
float imperialHash(float2 cell) {
    float3 p = fract(cell.xyx*0.1031);
    p += dot(p,p.yzx+33.33);
    return fract((p.x+p.y)*p.z);
}
#pragma body
float3 p = (scn_node.inverseModelViewTransform*float4(_surface.position,1.0)).xyz;
float2 plate = p.xz/float2(8.4,13.6);
plate.x += 0.5*fmod(floor(plate.y)+100.0,2.0);
float2 st = fract(plate);
float2 edge = min(st,1.0-st);
float seam = smoothstep(0.012,0.035,min(edge.x,edge.y));
float wear = imperialHash(floor(plate));
float grain = imperialHash(floor(p.xz*3.6+p.y));
float footprint = max(length(dfdx(p)),length(dfdy(p)));
float visible = 1.0-smoothstep(0.6,2.0,footprint);
_surface.diffuse.rgb *= (0.88+wear*0.21)*(1.0-(1.0-seam)*0.37*visible);
_surface.diffuse.rgb *= 1.0+(grain-0.5)*0.073*(1.0-smoothstep(0.08,0.32,footprint));
_surface.roughness = 0.64+0.25*wear;
"""

// The armor, its cutout and the hangar all use the same model-space dimensions.
private enum ImperialHull {
    static let bow: Float = -117
    static let stern: Float = 97
    static let hangarFront: Float = -12
    static let hangarBack: Float = 47
    static let hangarHalfWidth: Float = 18.4
    static let launchPort = V3(11,-10.8,15)

    static func fraction(_ z: Float) -> Float { (z-bow)/(stern-bow) }
    static func width(_ z: Float) -> Float { 0.35+64.5*fraction(z) }
    static func deck(_ x: Float, _ z: Float, upper: Bool) -> V3 {
        let middle = max(0,1-abs(x)/width(z))
        let slope = upper ? 2.6+14.8*middle : -(3.5+13.0*middle)
        return V3(x,slope*fraction(z)+0.14*(upper ? 1 : -1),z)
    }
    static func trenchEdge(_ z: Float, side: Float, upper: Bool) -> V3 {
        var p = deck(width(z)*side,z,upper:upper)
        p.x *= 0.969
        p.y += fraction(z)*(upper ? -0.72 : 0.72)
        return p
    }
}

extension Carrier {
    static var imperialLaunchPort: V3 { ImperialHull.launchPort }
}

// Accumulate the hull panels and small parallel fittings into a few draw calls.
private struct ImperialDetailMesh {
    private var vertices: [SCNVector3] = []
    private var normals: [SCNVector3] = []

    mutating func quad(_ a: V3, _ b: V3, _ c: V3, _ d: V3, outward: V3) {
        for triangle in [[a,b,c],[a,c,d]] {
            var points = triangle
            var normal = unit(simd_cross(points[1]-points[0],points[2]-points[0]))
            if simd_dot(normal,outward)<0 { points.swapAt(1,2); normal = -normal }
            vertices.append(contentsOf:points.map(SCNVector3.init))
            normals.append(contentsOf:Array(repeating:SCNVector3(normal),count:3))
        }
    }

    mutating func block(center p: V3, size: V3) {
        let x = V3(size.x*0.5,0,0), y = V3(0,size.y*0.5,0), z = V3(0,0,size.z*0.5)
        for direction: Float in [-1,1] {
            let end = p+x*direction
            quad(end-y-z,end+y-z,end+y+z,end-y+z,outward:x*direction)
            let roof = p+y*direction
            quad(roof-x-z,roof+x-z,roof+x+z,roof-x+z,outward:y*direction)
            let wall = p+z*direction
            quad(wall-x-y,wall+x-y,wall+x+y,wall-x+y,outward:z*direction)
        }
    }

    func makeNode(_ surface: SCNMaterial) -> SCNNode {
        let geometry = SCNGeometry(
            sources:[SCNGeometrySource(vertices:vertices),SCNGeometrySource(normals:normals)],
            elements:[SCNGeometryElement(indices:Array(0..<Int32(vertices.count)),primitiveType:.triangles)]
        )
        return node(geometry,surface)
    }
}

func imperialCarrier() -> SCNNode {
    let ship = SCNNode()
    let armor = material(color(0.42,0.45,0.49),metal:0.34)
    armor.shaderModifiers = [.surface:imperialPlating]
    let steel = material(color(0.37,0.41,0.45),metal:0.40)
    let trim = material(color(0.49,0.54,0.58),metal:0.46)
    let machinery = material(color(0.16,0.19,0.23),metal:0.45)
    let recess = material(color(0.066,0.078,0.092),metal:0.30)
    let window = material(color(0.60,0.72,0.82),emission:color(1.4,1.8,2.2))
    let deckLight = material(color(0.82,0.89,0.94),emission:color(2.1,2.5,3.0))
    let amber = material(color(0.87,0.44,0.14),emission:color(1.8,0.57,0.13))
    var random = Random(state:0x4953_4431)

    // The dorsal and ventral plates meet a recessed service trench at the edge.
    var shell = ImperialDetailMesh(), trench = ImperialDetailMesh()
    var fittings = ImperialDetailMesh(), plating = ImperialDetailMesh(), windows = ImperialDetailMesh()
    let sections = [ImperialHull.bow,ImperialHull.hangarFront,ImperialHull.hangarBack,ImperialHull.stern]
    for (front,back) in zip(sections,sections.dropFirst()) {
        for side: Float in [-1,1] {
            let frontEdge = ImperialHull.width(front)*side
            let backEdge = ImperialHull.width(back)*side
            for upper in [true,false] {
                let hasOpening = !upper && front == ImperialHull.hangarFront
                let inner = hasOpening ? side*ImperialHull.hangarHalfWidth : 0
                let a = ImperialHull.deck(inner,front,upper:upper)
                let b = ImperialHull.deck(frontEdge,front,upper:upper)
                let c = ImperialHull.deck(backEdge,back,upper:upper)
                let d = ImperialHull.deck(inner,back,upper:upper)
                shell.quad(a,b,c,d,outward:V3(0,upper ? 1 : -1,0))
                let insetFront = ImperialHull.trenchEdge(front,side:side,upper:upper)
                let insetBack = ImperialHull.trenchEdge(back,side:side,upper:upper)
                shell.quad(b,insetFront,insetBack,c,outward:V3(side,0,-0.3))
            }
            trench.quad(ImperialHull.trenchEdge(front,side:side,upper:true),ImperialHull.trenchEdge(back,side:side,upper:true),
                        ImperialHull.trenchEdge(back,side:side,upper:false),ImperialHull.trenchEdge(front,side:side,upper:false),
                        outward:V3(side,0,-0.3))
        }
    }
    for z in [ImperialHull.bow,ImperialHull.stern] {
        let edge = ImperialHull.width(z)
        for (left,right) in [(-edge,Float(0)),(Float(0),edge)] {
            trench.quad(ImperialHull.deck(left,z,upper:true),ImperialHull.deck(right,z,upper:true),
                        ImperialHull.deck(right,z,upper:false),ImperialHull.deck(left,z,upper:false),
                        outward:V3(0,0,z<0 ? -1 : 1))
        }
    }
    for side: Float in [-1,1] {
        for row in 0..<67 {
            let z = -61+Float(row)*2.30
            let x = side*(ImperialHull.width(z)*0.979-0.32)
            let y = random.range(-1.7,1.33)*ImperialHull.fraction(z)
            fittings.block(center:V3(x,y,z),size:V3(random.range(0.55,1.36),random.range(0.38,1.18),random.range(0.85,2.1)))
            if row%3 != 1 {
                windows.block(center:V3(x+side*0.64,y+0.13,z),size:V3(0.16,0.13,random.range(0.24,0.66)))
            }
        }
        for row in 0..<16 {
            let z = -78+Float(row)*10.6
            for lane in [Float(0.48),0.83] {
                let halfWidth = ImperialHull.width(z)
                let p = ImperialHull.deck(side*halfWidth*lane,z,upper:true)
                plating.block(center:p+V3(0,0.2,0),size:V3(random.range(1.4,3.3),0.62,random.range(2.4,5.7)))
            }
        }
    }
    ship.addChildNode(shell.makeNode(armor))
    ship.addChildNode(trench.makeNode(recess))

    // Successively narrower decks with sloped armor and rows of lit compartments.
    ship.addChildNode(armoredLoft([(8,16,3,8),(21,37,5,8),(77,46,6,9),(91,44,5,9)],mat:steel))
    let decks: [(Float,Float,Float,Float,Float)] = [(11,41,5,90,13),(24,34,19,84,8),(32,26,32,80,6)]
    for (y,halfWidth,front,back,height) in decks {
        let inset: Float = 4
        let lower = [V3(-halfWidth,y,front+10),V3(0,y,front),V3(halfWidth,y,front+10),
                     V3(halfWidth,y,back),V3(-halfWidth,y,back)]
        let upper = [V3(-halfWidth+inset,y+height,front+14),V3(0,y+height,front+4),V3(halfWidth-inset,y+height,front+14),
                     V3(halfWidth-inset,y+height,back-3),V3(-halfWidth+inset,y+height,back-3)]
        ship.addChildNode(hullMesh(lower+upper,faces:[[0,1,2,3,4],[5,6,7,8,9],[0,1,6,5],[1,2,7,6],[2,3,8,7],[3,4,9,8],[4,0,5,9]],mat:armor))
        for side: Float in [-1,1] {
            for z in stride(from:front+15,to:back-1,by:3.1) {
                let x = side*(halfWidth-0.74)
                fittings.block(center:V3(x,y+1.4,z),size:V3(2.4,random.range(1.2,3.5),random.range(1.0,2.8)))
                plating.block(center:V3(side*(halfWidth-1.7),y+2.9,z),size:V3(2.1,0.4,2.8))
                windows.block(center:V3(x+side*1.24,y+1.8,z),size:V3(0.14,0.20,random.range(0.20,1.05)))
            }
            for column in 1...11 {
                let t = Float(column)/12
                let p = V3(side*halfWidth*t,y+2.4,front+10*t)
                fittings.block(center:p,size:V3(2.3,random.range(2.1,4.1),3.6))
                windows.block(center:p-V3(0,0.2,1.84),size:V3(random.range(0.48,1.21),0.24,0.14))
            }
        }
    }

    ship.addChildNode(armoredLoft([(51,5,12,43),(59,9,13,44),(76,9,13,45),(86,5,12,44)],mat:steel))
    ship.addChildNode(armoredLoft([(48,15,2,54),(55,25,4,56),(65,25,4.5,56),(73,21,3.8,56)],mat:armor))
    ship.addChildNode(box(V3(20,2,13),trim,V3(0,61,62),chamfer:0.7))
    ship.addChildNode(box(V3(12,0.9,1.6),steel,V3(0,65,63),chamfer:0.25))
    for side: Float in [-1,1] {
        ship.addChildNode(box(V3(1.1,4,1.2),steel,V3(side*4.1,63,63),chamfer:0.18))
        ship.addChildNode(cylinder(2.5,1.4,recess,V3(side*18,60.4,63)))
        ship.addChildNode(segment(V3(side*18,59,63),V3(side*18,65,63),radius:1.4,mat:trim))
        let dome = SCNSphere(radius:3.65)
        dome.segmentCount = 10
        dome.isGeodesic = true
        ship.addChildNode(node(dome,trim,V3(side*18,65.8,63)))
        for row in 0..<12 {
            let z = 53+Float(row)*1.6
            let x = side*24.5
            fittings.block(center:V3(x,54.8,z),size:V3(1.1,1.5,random.range(0.55,1.23)))
            windows.block(center:V3(x+side*0.57,55.5,z),size:V3(0.12,0.18,0.53))
        }
        for i in 0..<14 {
            windows.block(center:V3(side*(0.9+Float(i)*1.31),55.25,52+Float(i)*0.25),size:V3(0.5,0.23,0.7))
        }
        for row in 0..<4 {
            let z = 25+Float(row)*13
            let x = side*(43+Float(row)*3.1)
            let p = ImperialHull.deck(x,z,upper:true)+V3(0,1.05,0)
            ship.addChildNode(box(V3(6.8,2.8,7.1),steel,p,chamfer:0.7))
            for barrel: Float in [-1,1] {
                ship.addChildNode(segment(p+V3(barrel*1.1,0.9,-2.4),p+V3(barrel*1.1,1.85,-8.5),radius:0.46,mat:trim))
            }
        }
    }

    addImperialHangar(to:ship,steel:steel,recess:recess,light:deckLight,amber:amber)
    addImperialEngines(to:ship,steel:steel,trim:trim,recess:recess)
    ship.addChildNode(fittings.makeNode(machinery))
    ship.addChildNode(plating.makeNode(steel))
    ship.addChildNode(windows.makeNode(window))
    return ship
}

private func addImperialHangar(to ship: SCNNode, steel: SCNMaterial, recess: SCNMaterial, light: SCNMaterial, amber: SCNMaterial) {
    let front = ImperialHull.hangarFront, back = ImperialHull.hangarBack
    let side = ImperialHull.hangarHalfWidth, ceiling: Float = 1.6
    var interior = ImperialDetailMesh(), frames = ImperialDetailMesh(), lamps = ImperialDetailMesh()
    var markers = ImperialDetailMesh(), servicePanels = ImperialDetailMesh()
    for sign: Float in [-1,1] {
        let x = side*sign
        let lowerFront = ImperialHull.deck(x,front,upper:false)
        let lowerBack = ImperialHull.deck(x,back,upper:false)
        interior.quad(lowerFront,lowerBack,V3(x,ceiling,back),V3(x,ceiling,front),outward:V3(-sign,0,0))
        for z in stride(from:front+1,to:back,by:4.0) {
            let edge = ImperialHull.deck(x,z,upper:false).y
            frames.block(center:V3(x-sign*0.18,(edge+ceiling)*0.5,z),size:V3(0.9,ceiling-edge,0.9))
            lamps.block(center:V3(x-sign*0.68,edge+0.40,z+0.7),size:V3(0.44,0.35,2.0))
            if Int((z-front)/4)%3 == 0 {
                markers.block(center:V3(x-sign*1.35,edge-0.07,z),size:V3(0.54,0.21,0.9))
            }
        }
        for z in [front,back] {
            let a = ImperialHull.deck(0,z,upper:false), b = ImperialHull.deck(x,z,upper:false)
            let inward: Float = z == front ? 1 : -1
            interior.quad(a,b,V3(x,ceiling,z),V3(0,ceiling,z),outward:V3(0,0,inward))
            let wall = z+inward*0.54
            for column in 0..<5 {
                let panelX = sign*(2.15+Float(column)*3.55)
                let sill = ImperialHull.deck(panelX,z,upper:false).y
                let height = ceiling-sill-1.9
                servicePanels.block(center:V3(panelX,sill+0.8+height*0.5,wall),size:V3(2.95,height,0.65))
                frames.block(center:V3(panelX,ceiling-1.5,wall+inward*0.36),size:V3(3.1,0.58,0.44))
                markers.block(center:V3(panelX,ceiling-2.48,wall+inward*0.36),size:V3(0.65,0.18,0.11))
                for row in 0..<3 {
                    let y = sill+1.2+Float(row)*0.53
                    frames.block(center:V3(panelX,y,wall+inward*0.33),size:V3(2.2,0.13,0.23))
                }
            }
        }
    }
    interior.quad(V3(-side,ceiling,front),V3(side,ceiling,front),V3(side,ceiling,back),V3(-side,ceiling,back),outward:V3(0,-1,0))
    for z in stride(from:front+3,to:back,by:6) {
        frames.block(center:V3(0,ceiling-0.43,z),size:V3(2*side,1.05,1.2))
        for x: Float in [-11,0,11] {
            lamps.block(center:V3(x,ceiling-1.02,z+0.15),size:V3(3.0,0.24,0.58))
        }
    }
    ship.addChildNode(interior.makeNode(recess))
    ship.addChildNode(servicePanels.makeNode(steel))
    ship.addChildNode(frames.makeNode(steel))
    ship.addChildNode(lamps.makeNode(light))
    ship.addChildNode(markers.makeNode(amber))

    // The smaller forward service recess and aft ventral dome break up the keel.
    ship.addChildNode(box(V3(14,1.7,11),recess,V3(0,-4.92,-47),chamfer:0.6))
    ship.addChildNode(box(V3(11,0.3,0.75),light,V3(0,-5.82,-49)))
    let dome = SCNSphere(radius:1)
    dome.segmentCount = 24
    let array = node(dome,steel,V3(0,-9.8,72))
    array.simdScale = V3(14,7.3,14)
    ship.addChildNode(array)
}

private func addImperialEngines(to ship: SCNNode, steel: SCNMaterial, trim: SCNMaterial, recess: SCNMaterial) {
    let ion = material(color(0.45,0.70,0.99),emission:color(1.1,2.1,3.5))
    let core = material(color(0.83,0.94,1),emission:color(2.05,3.0,4.2))
    var grilles = ImperialDetailMesh(), brackets = ImperialDetailMesh()
    for i in 0..<39 {
        let x = -58+Float(i)*3.05
        let height = 11.5*(1-abs(x)/66)+2.2
        grilles.block(center:V3(x,0,97.6),size:V3(2.0,height*1.63,2.2))
        brackets.block(center:V3(x,height*0.71,98.55),size:V3(1.72,0.78,1.25))
        brackets.block(center:V3(x,-height*0.71,98.55),size:V3(1.72,0.78,1.25))
    }
    ship.addChildNode(grilles.makeNode(recess))
    ship.addChildNode(brackets.makeNode(steel))

    let engines: [(Float,Float,Float,Float)] = [
        (-37,0,10.3,12),(0,-1.25,12.6,14),(37,0,10.3,12),
        (-17,-7.1,4.65,8),(-17,7.1,4.65,8),(17,-7.1,4.65,8),(17,7.1,4.65,8)
    ]
    for (x,y,radius,depth) in engines {
        let p = V3(x,y,99)
        let end = p+V3(0,0,depth)
        let profile: [(Float,Float)] = [(0,0.71),(1.1,0.83),(depth-2,1),(depth,0.95),
                                       (depth,0.84),(depth-1.6,0.79),(3.8,0.39)]
        var bell = ImperialDetailMesh(), flutes = ImperialDetailMesh()
        let sectors = 48
        for i in 0..<sectors {
            let a = Float(i)*tau/Float(sectors), b = Float(i+1)*tau/Float(sectors)
            let va = V3(cos(a),sin(a),0), vb = V3(cos(b),sin(b),0)
            func point(_ ring: (Float,Float), _ direction: V3) -> V3 { p+V3(0,0,ring.0)+direction*ring.1*radius }
            for ring in 0..<(profile.count-1) {
                let lo = profile[ring], hi = profile[ring+1]
                let normal = ring == 3 ? V3(0,0,1) : (va+vb)*(ring<3 ? 1 : -1)
                bell.quad(point(lo,va),point(lo,vb),point(hi,vb),point(hi,va),outward:normal)
            }
            if i%2 == 0 {
                let root = (point(profile[6],va)+point(profile[6],vb))*0.5
                let lip = (point(profile[4],va)+point(profile[4],vb))*0.5
                let edge = (va-vb)*radius*0.13
                flutes.quad(root+edge,root-edge,lip-edge,lip+edge,outward:-(va+vb))
            }
        }
        ship.addChildNode(bell.makeNode(steel))
        ship.addChildNode(flutes.makeNode(trim))
        let rim = node(SCNTorus(ringRadius:CGFloat(radius*0.89),pipeRadius:CGFloat(radius*0.065)),trim,end-V3(0,0,0.18))
        rim.simdEulerAngles.x = .pi/2
        ship.addChildNode(rim)
        ship.addChildNode(cylinder(CGFloat(radius*0.43),0.91,recess,p+V3(0,0,3.57)))
        ship.addChildNode(cylinder(CGFloat(radius*0.34),0.48,ion,p+V3(0,0,4.10)))
        ship.addChildNode(cylinder(CGFloat(radius*0.20),0.28,core,p+V3(0,0,4.47)))
    }
}
