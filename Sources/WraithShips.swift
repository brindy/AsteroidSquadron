import AppKit
import SceneKit
import simd

let wraithHangarMouth = V3(32,-22,-94)

// Smooth shells with curved centerlines. All points are in ship space,
// so the skin pattern flows continuously across overlapping plates and ribs.
private func wraithShell(_ sections: [(z: Float, x: Float, y: Float, width: Float, height: Float)],
                         material: SCNMaterial, slices: Int = 20, openFront: Bool = false) -> SCNNode {
    let steps = 5
    let rings = (sections.count-1)*steps+1
    var points = [V3]()
    var normals = [SCNVector3]()
    var triangles = [Int32]()

    func profile(_ section: Int) -> SIMD4<Float> {
        let s = sections[max(0,min(sections.count-1,section))]
        return SIMD4(s.x,s.y,s.width,s.height)
    }
    for ring in 0..<rings {
        let section = min(sections.count-2,ring/steps)
        let t = Float(ring-section*steps)/Float(steps)
        let start = profile(section), end = profile(section+1)
        let startTangent = (end-profile(section-1))*0.5
        let endTangent = (profile(section+2)-start)*0.5
        let t2 = t*t, t3 = t2*t
        let center = start*(2*t3-3*t2+1)+end*(-2*t3+3*t2)
        let shape = center+startTangent*(t3-2*t2+t)+endTangent*(t3-t2)
        let z = sections[section].z+(sections[section+1].z-sections[section].z)*t
        let progress = Float(ring)/Float(rings-1)
        for slice in 0..<slices {
            let angle = Float(slice)*tau/Float(slices)
            let ridge = 1+0.064*cos(angle*3+progress*5)+0.035*cos(angle*7-progress*12)
            let x = shape.x+cos(angle)*max(0.008,shape.z)*ridge
            let y = shape.y+sin(angle)*max(0.008,shape.w)*ridge
            points.append(V3(x,y,z))
        }
    }
    for ring in 0..<rings {
        for slice in 0..<slices {
            let i = ring*slices+slice
            let next = (slice+1)%slices, previous = (slice+slices-1)%slices
            let around = points[ring*slices+next]-points[ring*slices+previous]
            let lengthwise = points[min(ring+1,rings-1)*slices+slice]-points[max(0,ring-1)*slices+slice]
            normals.append(SCNVector3(unit(simd_cross(around,lengthwise))))
            if ring+1<rings {
                let a = Int32(i), b = Int32(ring*slices+next)
                triangles += [a,b,a+Int32(slices),b,b+Int32(slices),a+Int32(slices)]
            }
        }
    }
    let aft = Int32((rings-1)*slices)
    for slice in 1..<(slices-1) {
        let index = Int32(slice)
        if !openFront { triangles += [0,index+1,index] }
        triangles += [aft,aft+index,aft+index+1]
    }
    let geometry = SCNGeometry(
        sources:[SCNGeometrySource(vertices:points.map { SCNVector3($0) }),SCNGeometrySource(normals:normals)],
        elements:[SCNGeometryElement(indices:triangles,primitiveType:.triangles)]
    )
    return node(geometry,material)
}

private func wraithSkin(_ base: NSColor, frequency: Float, windowStrength: Float = 0) -> SCNMaterial {
    let skin = material(base,metal:0.28)
    skin.roughness.contents = 0.55
    skin.setValue(frequency,forKey:"skinFrequency")
    skin.setValue(windowStrength,forKey:"windowStrength")
    skin.shaderModifiers = [.surface:"""
    #pragma arguments
    float skinFrequency;
    float windowStrength;
    #pragma body
    float3 p = (scn_node.inverseModelViewTransform*float4(_surface.position,1.0)).xyz * skinFrequency;
    float bend = 1.7*sin(p.z*1.3+p.y*1.8) + 0.8*sin(p.x*2.6+p.z*0.71);
    float furrow = sin(p.x*8.3 + p.y*0.61 + bend + 0.7*sin(p.z*3.8));
    float grain = sin(p.z*13.7 + p.x*8.1)*sin(p.y*15.2-p.x*17.7);
    float fold = smoothstep(-0.7,0.9,furrow);
    float patches = 0.72 + 0.28*sin(p.x*1.19-p.z*0.97)*cos(p.y*1.4+p.z*0.77);
    _surface.diffuse.rgb *= 0.73 + fold*0.32*patches + grain*0.10;
    _surface.diffuse.rgb += fold*float3(0.022,0.017,0.039);
    _surface.roughness *= 0.86 + 0.26*fold;
    if (windowStrength > 0.0) {
        float3 grid = float3(p.x*12.0,p.y*9.0,p.z*21.0);
        float3 cell = floor(grid);
        float pin = fract(sin(dot(cell,float3(12.9898,78.233,45.164)))*43758.5453);
        float bands = sin(p.z*8.0+sin(p.x*4.0)) + 0.6*cos(p.y*9.0-p.z);
        float2 port = (fract(grid.xz)-0.5)*float2(1.2,0.85);
        float light = (1.0-smoothstep(0.10,0.24,length(port))) * step(0.71,pin);
        _surface.emission.rgb += float3(1.0,0.75,0.45)*light*smoothstep(0.35,1.2,bands)*windowStrength;
    }
    """]
    return skin
}

func wraithDart() -> SCNNode {
    let ship = SCNNode()
    let shell = wraithSkin(color(0.27,0.30,0.40),frequency:0.86)
    let ridge = wraithSkin(color(0.34,0.36,0.47),frequency:0.86)
    let recess = material(color(0.035,0.043,0.068),metal:0.25)
    let canopy = material(color(0.065,0.10,0.15),metal:0.62)
    canopy.roughness.contents = 0.19
    let exhaust = material(color(1,0.32,0.11),emission:color(3.3,0.68,0.12))
    ship.addChildNode(wraithShell([
        (-7.6,0,-0.11,0.02,0.025),(-5.1,0,-0.09,0.24,0.14),(-3.0,0,-0.04,0.68,0.31),
        (-1.5,0,0.03,1.56,0.47),(0.0,0,0.02,2.66,0.54),(1.65,0,-0.08,3.73,0.52),
        (2.85,0,-0.17,4.25,0.40),(3.57,0,-0.13,3.35,0.32),(4.24,0,0.02,1.28,0.31),
        (4.62,0,0.05,0.71,0.20)
    ],material:shell))
    ship.addChildNode(wraithShell([
        (-2.95,0,0.24,0.12,0.09),(-1.95,0,0.36,0.49,0.22),(-0.45,0,0.50,0.73,0.42),
        (1.12,0,0.46,0.61,0.31),(2.00,0,0.31,0.11,0.065)
    ],material:canopy))
    for side: Float in [-1,1] {
        // Claw tips and arched ribs wrap the cockpit and continue into the wing.
        ship.addChildNode(wraithShell([
            (-1.67,side*1.03,0.19,0.06,0.06),(-0.20,side*2.0,0.13,0.43,0.28),
            (1.55,side*3.63,-0.10,0.60,0.34),(2.83,side*4.37,-0.36,0.47,0.24),
            (3.85,side*4.66,-0.67,0.28,0.15),(4.78,side*4.34,-1.02,0.02,0.025)
        ],material:ridge))
        ship.addChildNode(wraithShell([
            (-2.2,side*0.55,0.35,0.07,0.07),(-1.25,side*0.87,0.60,0.17,0.16),
            (0.08,side*1.04,1.11,0.20,0.20),(1.28,side*1.27,1.01,0.20,0.19),
            (2.42,side*1.75,0.47,0.27,0.20),(3.7,side*2.42,0.07,0.08,0.06)
        ],material:ridge,slices:12))
        ship.addChildNode(wraithShell([
            (-0.7,side*1.11,0.25,0.06,0.04),(0.6,side*1.6,0.49,0.17,0.11),
            (2.25,side*2.50,0.29,0.19,0.12),(3.75,side*2.83,0.03,0.04,0.035)
        ],material:recess,slices:12))
        ship.addChildNode(cylinder(0.27,0.41,recess,V3(side*0.53,0.08,4.48)))
        ship.addChildNode(cylinder(0.16,0.06,exhaust,V3(side*0.53,0.08,4.70)))
        let gun = V3(side*0.50,-0.16,-3.14)
        ship.addChildNode(cylinder(0.14,1.04,recess,gun+V3(0,0,0.55)))
        addMuzzle(to:ship,at:gun,name:side<0 ? "left" : "right")
    }
    return ship
}

func wraithHive() -> SCNNode {
    let ship = SCNNode()
    let skin = wraithSkin(color(0.18,0.22,0.32),frequency:0.106,windowStrength:1.65)
    let ridge = wraithSkin(color(0.27,0.30,0.43),frequency:0.106)
    let recess = material(color(0.034,0.044,0.072),metal:0.22)
    let lights = material(color(0.95,0.82,0.57),emission:color(2.1,1.42,0.59))
    let exhaust = material(color(1,0.38,0.12),emission:color(2.7,0.68,0.13))

    // A low central hull leaves a pair of open trenches between the armored lobes.
    ship.addChildNode(wraithShell([
        (-157,0,-1,0.4,0.55),(-134,0,2,13,8),(-94,0,3,27,13),
        (-45,0,0,24,15),(9,0,-4,20,15),(58,0,-3,29,21),
        (108,0,1,44,20),(137,0,-2,30,14),(155,0,-3,10,5)
    ],material:skin))
    ship.addChildNode(wraithShell([
        (-117,0,7,2,1),(-83,0,14,8,4),(-33,0,15,10,6),(17,0,12,7,4),
        (73,0,18,11,7),(123,0,11,4,2),(148,0,2,1,1)
    ],material:ridge,slices:16))
    for side: Float in [-1,1] {
        ship.addChildNode(wraithShell([
            (-142,side*23,1,0.45,0.45),(-119,side*38,6,10,7),(-84,side*61,10,18,12),
            (-37,side*79,12,24,18),(15,side*83,8,21,22),(68,side*70,2,22,21),
            (112,side*48,-1,22,16),(140,side*32,-3,16,10),(154,side*26,-3,6,4)
        ],material:skin))
        ship.addChildNode(wraithShell([
            (-137,side*27,4,0.7,0.7),(-101,side*48,16,4,4),(-54,side*74,28,6,5),
            (0,side*84,31,8,5),(52,side*77,23,6,5),(106,side*53,15,5,4),(149,side*27,3,0.8,0.8)
        ],material:ridge,slices:14))
        // The inner arch bridges the trench at the bow and stern, with dark
        // cavities beneath it. Thinner side spurs give the outer shell a serrated edge.
        ship.addChildNode(wraithShell([
            (-144,side*8,3,1,1),(-106,side*28,6,6,6),(-65,side*40,17,8,9),
            (-9,side*48,19,7,9),(47,side*45,10,7,6),(101,side*26,7,9,7),(143,side*17,0,2,2)
        ],material:ridge,slices:16))
        for i in 0..<4 {
            let z = Float(i)*26
            let x = 76-Float(i)*7.0
            ship.addChildNode(wraithShell([
                (z-47,side*(x-3),-2,3.8,4),(z-24,side*(x+14),-4,5.8,5.6),
                (z-1,side*(x+23),-12,3.4,3.8),(z+16,side*(x+25),-19,0.18,0.25)
            ],material:skin,slices:12))
        }

        // A hollow, oval launch mouth, with a recessed back and individual lights.
        let mouth = V3(side*wraithHangarMouth.x,wraithHangarMouth.y,wraithHangarMouth.z)
        ship.addChildNode(wraithShell([
            (mouth.z,mouth.x,mouth.y,12.8,6.8),(-84,side*33,-20,15.6,10.0),
            (-67,side*32,-16,16.1,12.6),(-49,side*26,-12,14.5,10.8),
            (-27,side*21,-8,7,6)
        ],material:skin,openFront:true))
        let tunnel = node(SCNTube(innerRadius:7.1,outerRadius:8.8,height:22),recess,mouth+V3(0,0,11))
        tunnel.simdEulerAngles.x = .pi/2
        tunnel.simdScale = V3(1.44,1,0.68)
        ship.addChildNode(tunnel)
        let rim = node(SCNTorus(ringRadius:8.25,pipeRadius:0.81),ridge,mouth)
        rim.simdEulerAngles.x = .pi/2
        rim.simdScale = V3(1.44,1,0.68)
        ship.addChildNode(rim)
        ship.addChildNode(cylinder(7.3,1,recess,mouth+V3(0,0,21.5)))
        for light in 0..<7 {
            let angle = Float(light)*tau/7
            let p = mouth+V3(cos(angle)*10.7,sin(angle)*4.5,0.5)
            ship.addChildNode(cylinder(0.50,1.3,lights,p))
        }
        for i in 0..<3 {
            let port = V3(side*(18+Float(i)*10),-6-Float(i%2)*6,148-Float(i)*3)
            ship.addChildNode(cylinder(4.1,5.2,recess,port))
            ship.addChildNode(cylinder(2.55,0.75,exhaust,port+V3(0,0,2.8)))
        }
    }
    return ship
}
