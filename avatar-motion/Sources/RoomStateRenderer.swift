import SpriteKit

/// Independent state overlays sit above the animated room and below the avatar.
final class RoomStateRenderer: SKNode {
    static let fanFramesPerRevolution = 12
    static let fastFanRevolutionsPerSecond = 5.0
    private let canvas: Point2
    private let bounds: [String: [Double]]
    private var textures: [String: SKTexture] = [:]
    private var nodes: [String: SKSpriteNode] = [:]
    private var lastState: RoomVisualState?
    private(set) var fanFrameIndex = 0
    private(set) var computeFrameIndex = 0
    private(set) var displayFrameIndex = 0

    init(directory: URL, canvas: Point2) throws {
        struct AssetManifest: Decodable { let bounds: [String: [Double]] }
        self.canvas = canvas
        bounds = try JSONDecoder().decode(AssetManifest.self,
            from: Data(contentsOf:directory.appendingPathComponent("manifest.json"))).bounds
        super.init()
        name = "room-states"; zPosition = -5
        for (key, box) in bounds {
            guard box.count == 4, box.allSatisfy(\.isFinite),
                  box[2] > box[0], box[3] > box[1],
                  let image = NSImage(contentsOf:directory.appendingPathComponent(key+".png")),
                  let cg = image.cgImage(forProposedRect:nil,context:nil,hints:nil) else {
                throw ManifestError.resourceMissing("RoomStates/\(key)")
            }
            textures[key] = SKTexture(cgImage:cg)
            if key.hasPrefix("compute-") || key == "network-lamp" {
                for (name,color) in [("yellow",(1.0,0.73,0.14)),("red",(1.0,0.18,0.16))] {
                    textures[key+"-"+name] = SKTexture(cgImage:Self.recolored(cg,to:color))
                }
            }
        }
        let bookNames = ["book-tall","book-white","book-short","book-small","book-middle","book-middle-white",
                         "book-middle-short","book-lower","book-lower-white","book-lower-right","book-horizontal"]
        var books: [String:CGImage] = [:]
        for name in bookNames { books[name] = try requiredTexture(name).cgImage() }
        for count in 0...4 { add("bed-\(count)",texture:RoomStateArtwork.bed(lights:count),bounds:RoomStateArtwork.bedBounds) }
        add("bookshelf-sparse",texture:RoomStateArtwork.bookshelf(overflow:false,books:books),bounds:RoomStateArtwork.bookshelfBounds)
        add("bookshelf-overflow",texture:RoomStateArtwork.bookshelf(overflow:true,books:books),bounds:RoomStateArtwork.bookshelfBounds)
        add("desk-stacked",texture:RoomStateArtwork.desk(overflow:false),bounds:RoomStateArtwork.deskBounds)
        add("desk-overflow",texture:RoomStateArtwork.desk(overflow:true),bounds:RoomStateArtwork.deskBounds)
        for frame in 0..<8 { textures["noise-\(frame)"] = RoomStateArtwork.displayNoise(frame:frame) }
        add("display",texture:textures["noise-0"]!,bounds:RoomStateArtwork.displayBounds)
        for id in ["fan-1","fan-2"] { add(id,texture:try requiredTexture(id+"-00"),bounds:try assetBounds(id+"-00")) }
        add("network",texture:try requiredTexture("network-lamp"),bounds:try assetBounds("network-lamp"))
        add("compute",texture:try requiredTexture("compute-00"),bounds:try assetBounds("compute-00"))
        add("chair",texture:try requiredTexture("chair"),bounds:try assetBounds("chair"))
        nodes["chair"]?.zPosition = 1
        apply(state:RoomVisualState(),time:0,reducedMotion:false)
    }

    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func requiredTexture(_ key:String) throws -> SKTexture {
        guard let texture = textures[key] else { throw ManifestError.resourceMissing("RoomStates/\(key)") }
        return texture
    }

    private func assetBounds(_ key:String) throws -> CGRect {
        guard let box = bounds[key] else { throw ManifestError.resourceMissing("RoomStates/\(key)") }
        return CGRect(x:box[0],y:box[1],width:box[2]-box[0],height:box[3]-box[1])
    }

    private func add(_ name:String,texture:SKTexture,bounds:CGRect) {
        let node = SKSpriteNode(texture:texture,size:bounds.size)
        node.name = name; node.position = CGPoint(x:bounds.midX,y:canvas.y-bounds.midY)
        node.isHidden = true; addChild(node); nodes[name] = node
    }

    func apply(state:RoomVisualState,time:Double,reducedMotion:Bool) {
        let t = reducedMotion || !time.isFinite ? 0 : max(0,time)
        if state != lastState {
            for count in 0...4 { nodes["bed-\(count)"]?.isHidden = count != state.bedLights }
            nodes["bookshelf-sparse"]?.isHidden = state.bookshelf.rawValue != "sparse"
            nodes["bookshelf-overflow"]?.isHidden = state.bookshelf.rawValue != "overflow"
            nodes["desk-stacked"]?.isHidden = state.desk.rawValue != "stacked"
            nodes["desk-overflow"]?.isHidden = state.desk.rawValue != "overflow"
            nodes["chair"]?.isHidden = state.desk.rawValue == "normal"
            nodes["display"]?.isHidden = state.display.rawValue != "staticNoise"
            lastState = state
        }
        let fast = state.fans.rawValue == "fast"
        fanFrameIndex = state.fans.rawValue == "stopped" ? 0 : Int(floor(t * (fast ? Self.fastFanRevolutionsPerSecond * Double(Self.fanFramesPerRevolution) : 10) + 1e-9)) % Self.fanFramesPerRevolution
        for id in ["fan-1","fan-2"] {
            let key = id + (fast ? "-fast-" : "-") + String(format:"%02d",fanFrameIndex)
            nodes[id]?.texture = textures[key]; nodes[id]?.isHidden = false
        }
        computeFrameIndex = Int(floor(t*10)) % 12
        let computeKey = String(format:"compute-%02d",computeFrameIndex)
        nodes["compute"]?.texture = textures[computeKey + (state.compute.rawValue == "cyan" ? "" : "-"+state.compute.rawValue)]
        nodes["compute"]?.isHidden = false
        nodes["network"]?.texture = textures["network-lamp" + (state.network.rawValue == "cyan" ? "" : "-"+state.network.rawValue)]
        nodes["network"]?.isHidden = false
        displayFrameIndex = Int(floor(t*18)) % 8
        nodes["display"]?.texture = textures["noise-\(displayFrameIndex)"]
    }

    private static func recolored(_ image:CGImage,to color:(Double,Double,Double)) -> CGImage {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating:0,count:width*height*4)
        return pixels.withUnsafeMutableBytes { bytes in
            let context = CGContext(data:bytes.baseAddress,width:width,height:height,bitsPerComponent:8,
                bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),
                bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
            let data = bytes.bindMemory(to:UInt8.self)
            for i in stride(from:0,to:data.count,by:4) {
                let r = Double(data[i]), g = Double(data[i+1]), b = Double(data[i+2])
                guard b > r + 12, b > g * 0.85 else { continue }
                let floor = min(r,g,b), chroma = max(r,g,b)-floor
                data[i] = UInt8(min(255,floor+chroma*color.0))
                data[i+1] = UInt8(min(255,floor+chroma*color.1))
                data[i+2] = UInt8(min(255,floor+chroma*color.2))
            }
            return context.makeImage()!
        }
    }
}
