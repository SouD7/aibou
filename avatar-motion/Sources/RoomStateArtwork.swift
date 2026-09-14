import AppKit
import SpriteKit

/// Small, cached textures drawn in the room's top-left coordinate system.
/// These overlays preserve the delivered furniture, lighting and perspective.
enum RoomStateArtwork {
    static func texture(in bounds: CGRect, draw: (CGContext) -> Void) -> SKTexture {
        let width = Int(bounds.width), height = Int(bounds.height)
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.translateBy(x: 0, y: bounds.height); context.scaleBy(x: 1, y: -1)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        draw(context)
        return SKTexture(cgImage: context.makeImage()!)
    }

    static func polygon(_ points: [CGPoint], in c: CGContext, fill: String, stroke: String? = nil,
                        width: CGFloat = 1) {
        guard let first = points.first else { return }
        c.beginPath(); c.move(to: first)
        for point in points.dropFirst() { c.addLine(to: point) }
        c.closePath(); c.setFillColor(NSColor(hex: fill).cgColor)
        if let stroke {
            c.setStrokeColor(NSColor(hex: stroke).cgColor); c.setLineWidth(width); c.drawPath(using: .fillStroke)
        } else { c.fillPath() }
    }

    static func rect(_ rect: CGRect, in c: CGContext, fill: String, radius: CGFloat = 0) {
        c.setFillColor(NSColor(hex: fill).cgColor)
        c.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)); c.fillPath()
    }

    static let bedBounds = CGRect(x: 86, y: 451, width: 172, height: 225)
    static func bed(lights: Int) -> SKTexture {
        texture(in: bedBounds) { c in
            // One inset panel replaces all five original headboard cells with four.
            polygon([CGPoint(x: 160,y:456),CGPoint(x:247,y:455),CGPoint(x:250,y:483),CGPoint(x:158,y:484)],
                    in:c,fill:"#455D6B",stroke:"#BEDBEA",width:1.3)
            for i in 0..<4 {
                let x = 166 + CGFloat(i) * 20
                let lit = i < lights
                c.saveGState()
                if lit { c.setShadow(offset:.zero,blur:5,color:NSColor(hex:"#9CE7FF").cgColor) }
                rect(CGRect(x:x,y:459,width:14,height:20),in:c,fill:lit ? "#C3F3FF" : "#263C4D",radius:3)
                c.restoreGState()
                // Perspective of the four cells on the near side of the bed.
                let sx = 91 + CGFloat(i) * 20
                let sy = 596 + CGFloat(i) * 5.8
                let outline = [CGPoint(x:sx,y:sy),CGPoint(x:sx+15,y:sy+4),
                               CGPoint(x:sx+15,y:sy+53),CGPoint(x:sx,y:sy+48)]
                polygon(outline,in:c,fill:"#53687A",stroke:"#D8E3EA",width:1.8)
                let inside = [CGPoint(x:sx+3,y:sy+4),CGPoint(x:sx+12,y:sy+7),
                              CGPoint(x:sx+12,y:sy+48),CGPoint(x:sx+3,y:sy+44)]
                c.saveGState()
                if lit { c.setShadow(offset:.zero,blur:5,color:NSColor(hex:"#95DFFF").cgColor) }
                polygon(inside,in:c,fill:lit ? "#BAF1FF" : "#263C4D")
                c.restoreGState()
            }
        }
    }

    static let bookshelfBounds = CGRect(x:410,y:264,width:260,height:333)
    static func bookshelf(overflow: Bool, books: [String: CGImage]) -> SKTexture {
        texture(in:bookshelfBounds) { c in
            // Draw native-size cutouts: no replacement spine styling or width scaling.
            func place(_ name:String, x:Double, bottom:Double, laidFlat:Bool = false) {
                guard let image = books[name] else { return }
                let width = Double(image.width), height = Double(image.height)
                c.saveGState()
                c.translateBy(x:x + (laidFlat ? height : 0),y:bottom)
                if laidFlat { c.rotate(by: -.pi / 2) }
                c.scaleBy(x:1,y:-1)
                c.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
                c.restoreGState()
            }
            if overflow {
                // Keep the normal books intact; add matching volumes into its open spaces.
                place("book-small",x:540,bottom:330)
                place("book-short",x:549,bottom:331)
                place("book-small",x:565,bottom:332)
                place("book-small",x:578,bottom:333)
                for x in [548.0,564,581] { place("book-middle-short",x:x,bottom:444) }
                place("book-horizontal",x:478,bottom:495)
                place("book-horizontal",x:479,bottom:478)
                for i in 0..<3 { place("book-horizontal",x:604+Double(i%2)*2,bottom:589-Double(i)*17) }
            } else {
                let rows: [[CGPoint]] = [
                    [CGPoint(x:414,y:267),CGPoint(x:597,y:286),CGPoint(x:598,y:358),CGPoint(x:414,y:345)],
                    [CGPoint(x:414,y:372),CGPoint(x:597,y:379),CGPoint(x:598,y:446),CGPoint(x:414,y:446)],
                    [CGPoint(x:414,y:467),CGPoint(x:597,y:465),CGPoint(x:598,y:526),CGPoint(x:414,y:536)]
                ]
                let wiring: [[CGPoint]] = [
                    [CGPoint(x:551,y:280),CGPoint(x:551,y:299),CGPoint(x:565,y:313),CGPoint(x:565,y:358)],
                    [CGPoint(x:563,y:375),CGPoint(x:563,y:395),CGPoint(x:551,y:407),CGPoint(x:551,y:446)],
                    [CGPoint(x:511,y:465),CGPoint(x:511,y:486),CGPoint(x:525,y:500),CGPoint(x:525,y:531)]
                ]
                for (index, quad) in rows.enumerated() {
                    c.saveGState();c.beginPath();c.addLines(between:quad);c.closePath();c.clip()
                    let colors = [NSColor(hex:"#AFB3C0").cgColor,NSColor(hex:"#CDD0D9").cgColor] as CFArray
                    if let gradient = CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors,locations:[0,1]) {
                        c.drawLinearGradient(gradient,start:quad[0],end:quad[2],options:[])
                    }
                    // Thin, softly lit traces follow the original backing's angular wiring.
                    // Clip to each recess and draw before the books so the wiring stays behind them.
                    c.setLineJoin(.round);c.setLineCap(.round);c.setLineWidth(1.1)
                    c.setStrokeColor(NSColor(hex:"#A1E5F3").withAlphaComponent(0.8).cgColor)
                    c.setShadow(offset:.zero,blur:3,color:NSColor(hex:"#6FD8F2").withAlphaComponent(0.4).cgColor)
                    c.beginPath();c.addLines(between:wiring[index]);c.strokePath()
                    c.restoreGState()
                }
                place("book-tall",x:417,bottom:345)
                place("book-white",x:442,bottom:347)
                place("book-short",x:540,bottom:355,laidFlat:true)
                place("book-middle",x:418,bottom:445)
                place("book-middle-white",x:440,bottom:445)
                place("book-middle-short",x:541,bottom:445,laidFlat:true)
                place("book-lower-white",x:418,bottom:533)
                place("book-lower",x:443,bottom:532)
                place("book-lower-right",x:539,bottom:528,laidFlat:true)
            }
        }
    }

    static let deskBounds = CGRect(x:651,y:387,width:503,height:294)
    static func desk(overflow: Bool) -> SKTexture {
        texture(in:deskBounds) { c in
            if overflow {
                // Loose pages beneath the desk, behind the chair's wheels.
                for i in 0..<15 {
                    let x = 832 + Double((i*43)%225), y = 605 + Double((i*19)%64)
                    c.saveGState();c.translateBy(x:x,y:y);c.rotate(by:Double(i%5-2)*0.12)
                    paper(c,x:0,y:0,width:35+Double(i%3)*7,depth:13,index:i)
                    c.restoreGState()
                }
            }
            let stacks: [(Double,Double,Double,Int)] = overflow
                ? [(678,473,56,20),(735,475,48,26),(872,480,60,15),(1030,477,65,30),(1090,474,45,22)]
                : [(681,473,52,7),(876,480,60,5),(1050,477,55,9)]
            for (x,y,width,count) in stacks {
                for layer in 0..<count {
                    paper(c,x:x+Double(layer%3-1)*0.7,y:y-Double(layer)*2.2,
                          width:width,depth:13,index:layer)
                }
            }
        }
    }

    private static func paper(_ c:CGContext,x:Double,y:Double,width:Double,depth:Double,index:Int) {
        c.saveGState();c.setShadow(offset:CGSize(width:0,height:1),blur:2,color:NSColor.black.withAlphaComponent(0.20).cgColor)
        polygon([CGPoint(x:x,y:y),CGPoint(x:x+width,y:y+1),CGPoint(x:x+width-7,y:y-depth),CGPoint(x:x-7,y:y-depth-1)],
                in:c,fill:index%3 == 0 ? "#EDF1F0" : "#DCE3E6",stroke:"#8998A4",width:0.65)
        c.restoreGState()
        for row in 0..<3 {
            c.setStrokeColor(NSColor(hex:"#A9BAC4").cgColor);c.setLineWidth(0.55)
            c.move(to:CGPoint(x:x+4-Double(row),y:y-3-Double(row)*2.7))
            c.addLine(to:CGPoint(x:x+width-10-Double(row),y:y-3-Double(row)*2.7));c.strokePath()
        }
    }

    static let displayBounds = CGRect(x:870,y:367,width:229,height:84)
    static func displayNoise(frame:Int) -> SKTexture {
        texture(in:displayBounds) { c in
            let quad = [CGPoint(x:871,y:380),CGPoint(x:1095,y:370),CGPoint(x:1095,y:448),CGPoint(x:871,y:449)]
            c.beginPath();c.addLines(between:quad);c.closePath();c.clip()
            rect(displayBounds,in:c,fill:"#263138")
            var seed = UInt32(frame+1)*131
            for y in stride(from:367,to:451,by:2) {
                for x in stride(from:870,to:1099,by:3) {
                    seed = seed &* 1664525 &+ 1013904223
                    let gray = CGFloat((seed >> 24)&255)/255
                    c.setFillColor(NSColor(white:gray,alpha:1).cgColor)
                    c.fill(CGRect(x:x,y:y,width:3,height:2))
                }
            }
        }
    }
}
