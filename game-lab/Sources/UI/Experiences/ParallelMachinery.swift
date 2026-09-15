import SwiftUI

private let parallelSteel = LinearGradient(colors:[Color(white:0.34),Color(white:0.77),Color(white:0.48),Color(white:0.21)],startPoint:.topLeading,endPoint:.bottomTrailing)

struct ParallelMachineHousing: View {
    var body: some View {
        GeometryReader { g in
            ZStack {
                WorkshopChamfer(corner:18).fill(LinearGradient(colors:[Color(white:0.32),ExperienceStyle.dark,Color(white:0.12)],startPoint:.topLeading,endPoint:.bottomTrailing))
                WorkshopChamfer(corner:18).strokeBorder(parallelSteel,lineWidth:9)
                WorkshopChamfer(corner:12,insetAmount:10).strokeBorder(.black.opacity(0.5),lineWidth:3)
                ForEach(0..<4,id:\.self) { i in
                    Circle().fill(Color(white:0.24)).overlay(Circle().strokeBorder(Color(white:0.65),lineWidth:2))
                        .overlay(Rectangle().fill(Color(white:0.5)).frame(width:8,height:2).rotationEffect(.degrees(35)))
                        .frame(width:12,height:12).position(x:i % 2 == 0 ? 14 : g.size.width-14,y:i < 2 ? 14 : g.size.height-14)
                }
            }.compositingGroup().shadow(color:.black.opacity(0.5),radius:0,x:3,y:5)
        }.allowsHitTesting(false)
    }
}

struct ParallelRobotWorker: View {
    var active: Bool
    var tick: Int
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    private var lift: CGFloat { active && tick % 2 == 1 ? -8 : 0 }
    var body: some View {
        ZStack {
            Ellipse().fill(.black.opacity(0.45)).frame(width:58,height:12).offset(y:33)
            RoundedRectangle(cornerRadius:8).fill(parallelSteel).frame(width:43,height:15).offset(y:27)
            Capsule().fill(parallelSteel).frame(width:9,height:21).rotationEffect(.degrees(16)).offset(x:-12,y:21)
            Capsule().fill(parallelSteel).frame(width:9,height:21).rotationEffect(.degrees(-16)).offset(x:12,y:21)
            RoundedRectangle(cornerRadius:13).fill(LinearGradient(colors:[.white,ExperienceStyle.paper,Color(white:0.56)],startPoint:.topLeading,endPoint:.bottomTrailing))
                .frame(width:39,height:39).overlay(RoundedRectangle(cornerRadius:13).strokeBorder(ExperienceStyle.ink,lineWidth:2)).offset(y:6)
            Circle().fill(ExperienceStyle.dark).frame(width:14,height:14).overlay(Circle().strokeBorder(ExperienceStyle.cyan,lineWidth:2)).offset(y:7)
            Path { p in p.move(to:CGPoint(x:13,y:39));p.addLine(to:CGPoint(x:5,y:48));p.addLine(to:CGPoint(x:11,y:56)) }
                .stroke(parallelSteel,style:StrokeStyle(lineWidth:8,lineCap:.round)).frame(width:72,height:79)
            Path { p in p.move(to:CGPoint(x:54,y:37));p.addLine(to:CGPoint(x:64,y:44+lift));p.addLine(to:CGPoint(x:67,y:34+lift)) }
                .stroke(parallelSteel,style:StrokeStyle(lineWidth:9,lineCap:.round)).frame(width:72,height:79)
            Circle().fill(Color(white:0.62)).frame(width:9,height:9).overlay(Circle().strokeBorder(ExperienceStyle.ink,lineWidth:2)).offset(x:27,y:5+lift)
            Image(systemName:"chevron.down").font(.system(size:14,weight:.black)).foregroundStyle(ExperienceStyle.ink).rotationEffect(.degrees(20)).offset(x:31,y:-8+lift)
            Circle().fill(LinearGradient(colors:[.white,ExperienceStyle.paper,Color(white:0.54)],startPoint:.topLeading,endPoint:.bottomTrailing)).frame(width:44,height:41)
                .overlay(Circle().strokeBorder(ExperienceStyle.ink,lineWidth:2)).offset(y:-22)
            RoundedRectangle(cornerRadius:9).fill(ExperienceStyle.dark).frame(width:33,height:24).offset(y:-19)
            HStack(spacing:8) { Capsule().fill(active ? ExperienceStyle.cyan : Color(white:0.65)).frame(width:5,height:10);Capsule().fill(active ? ExperienceStyle.cyan : Color(white:0.65)).frame(width:5,height:10) }.offset(y:-18)
        }.frame(width:72,height:79).scaleEffect(compact ? 0.70 : 0.93)
            .animation(reducedMotion ? nil : .easeInOut(duration:0.26),value:lift)
            .accessibilityLabel(active ? "工程を進めているロボット" : "次の工程を待つロボット")
    }
}

struct ParallelPress: View {
    var active: Bool
    var tick: Int
    var singleDependency: Bool
    var processed: Int
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius:8).fill(Color(white:0.11)).frame(width:232,height:168)
            HStack {
                RoundedRectangle(cornerRadius:4).fill(parallelSteel).frame(width:17,height:165)
                Spacer()
                RoundedRectangle(cornerRadius:4).fill(parallelSteel).frame(width:17,height:165)
            }.frame(width:232)
            HStack(spacing:10) {
                ForEach(0..<4,id:\.self) { i in
                    let lit = active && (!singleDependency || i == processed % 4)
                    VStack(spacing:0) {
                        RoundedRectangle(cornerRadius:5).fill(parallelSteel).frame(width:41,height:51)
                            .overlay(RoundedRectangle(cornerRadius:4).strokeBorder(ExperienceStyle.ink,lineWidth:2))
                            .overlay(alignment:.bottom) { Capsule().fill(lit ? ExperienceStyle.cyan : Color(white:0.37)).frame(width:30,height:5).padding(.bottom,7) }
                        Rectangle().fill(LinearGradient(colors:[Color(white:0.4),.white,Color(white:0.4)],startPoint:.leading,endPoint:.trailing)).frame(width:15,height:35)
                        WorkshopChamfer(corner:3).fill(parallelSteel).frame(width:42,height:17)
                            .overlay(WorkshopChamfer(corner:2,insetAmount:3).fill(lit ? ExperienceStyle.cyan : Color(white:0.26)))
                    }.offset(y:lit && tick % 2 == 1 ? 10 : 0)
                }
            }.offset(y:-5)
            RoundedRectangle(cornerRadius:4).fill(parallelSteel).frame(width:235,height:19)
                .overlay { HStack(spacing:8) { ForEach(0..<3,id:\.self) { _ in Rectangle().fill(ExperienceStyle.amber).frame(width:8,height:13).rotationEffect(.degrees(25)) } } }.offset(y:-75)
            ZStack {
                RoundedRectangle(cornerRadius:5).fill(parallelSteel).frame(width:232,height:29)
                HStack(spacing:8) { ForEach(0..<12,id:\.self) { _ in Capsule().fill(LinearGradient(colors:[.black.opacity(0.7),Color(white:0.59),.black.opacity(0.7)],startPoint:.leading,endPoint:.trailing)).frame(width:8,height:17) } }
                Rectangle().fill(active ? ExperienceStyle.cyan.opacity(0.75) : Color(white:0.34)).frame(width:204,height:3).offset(y:13)
            }.offset(y:69)
        }.frame(width:238,height:176).compositingGroup()
            .animation(reducedMotion ? nil : .easeInOut(duration:0.22),value:tick)
    }
}

struct ParallelTransportChannel: View {
    var active: Bool
    var returning: Bool
    var tick: Int
    var body: some View {
        GeometryReader { g in
            ZStack {
                RoundedRectangle(cornerRadius:7).fill(.black.opacity(0.65)).overlay(RoundedRectangle(cornerRadius:7).strokeBorder(parallelSteel,lineWidth:4))
                VStack { Capsule().fill(parallelSteel).frame(height:5);Spacer();Capsule().fill(parallelSteel).frame(height:5) }.padding(.horizontal,18).padding(.vertical,3)
                HStack(spacing:0) {
                    ForEach(0..<9,id:\.self) { n in
                        ZStack { Rectangle().fill(Color(white:n % 2 == tick % 2 ? 0.21 : 0.16));Image(systemName:returning ? "chevron.left" : "chevron.right").font(.system(size:14,weight:.black)).foregroundStyle(active ? ExperienceStyle.cyan.opacity(0.8) : Color(white:0.28)) }
                            .overlay(alignment:.trailing) { Rectangle().fill(.black.opacity(0.5)).frame(width:2) }
                    }
                }.padding(.horizontal,19).padding(.vertical,10)
                VStack { Rectangle().fill(active ? ExperienceStyle.cyan : .gray.opacity(0.4)).frame(height:3);Spacer();Rectangle().fill(active ? ExperienceStyle.cyan : .gray.opacity(0.4)).frame(height:3) }.padding(.horizontal,19).padding(.vertical,8)
                ForEach(0..<2,id:\.self) { i in
                    Circle().fill(parallelSteel).frame(width:33,height:33)
                        .overlay(Circle().fill(ExperienceStyle.dark).padding(4))
                        .overlay(Circle().fill(active ? ExperienceStyle.cyan : Color(white:0.35)).padding(9))
                        .position(x:i == 0 ? 17 : g.size.width-17,y:g.size.height/2)
                }
                ForEach(1..<4,id:\.self) { i in
                    RoundedRectangle(cornerRadius:3).fill(parallelSteel).frame(width:8,height:g.size.height-2)
                        .overlay(Capsule().fill(ExperienceStyle.ink).frame(width:2,height:15))
                        .position(x:g.size.width*CGFloat(i)/4,y:g.size.height/2)
                }
            }.compositingGroup().shadow(color:.black.opacity(0.45),radius:0,y:4)
        }.allowsHitTesting(false)
    }
}
