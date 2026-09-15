import SwiftUI

/// Dense apparatus controls retain the common material at a size suited to the 1160-point mat.
struct LogicCompactButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 16,weight: .semibold,design: .rounded))
            .padding(.horizontal,8).padding(.vertical,8)
            .foregroundStyle(ExperienceStyle.ink)
            .background(WorkshopChamfer(corner: 8).fill(LinearGradient(colors: primary ? [.white,ExperienceStyle.cyan] : [.white,ExperienceStyle.paper],startPoint: .topLeading,endPoint: .bottomTrailing)))
            .overlay(WorkshopChamfer(corner: 8).strokeBorder(primary ? ExperienceStyle.cyan : ExperienceStyle.muted,lineWidth: 2))
            .overlay(WorkshopChamfer(corner: 6,insetAmount: 3).strokeBorder(.white.opacity(0.6),lineWidth: 1))
            .compositingGroup()
            .shadow(color: .black.opacity(0.4),radius: 0,y: configuration.isPressed ? 1 : 4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1).opacity(enabled ? 1 : 0.4)
    }
}

/// A metal enclosure with a recessed working surface. Its rim stays outside the content area.
struct LogicMachineHousing: View {
    var accent: Color = .cyan
    var active = false
    var body: some View {
        ZStack {
            WorkshopChamfer(corner: 16).fill(LinearGradient(colors: [Color(red: 0.85,green: 0.85,blue: 0.81),.white,Color(red: 0.45,green: 0.48,blue: 0.49)],startPoint: .topLeading,endPoint: .bottomTrailing))
            WorkshopChamfer(corner: 16).strokeBorder(Color.black.opacity(0.8),lineWidth: 3)
            WorkshopChamfer(corner: 12,insetAmount: 8).fill(LinearGradient(colors: [Color(red: 0.11,green: 0.14,blue: 0.17),Color(red: 0.23,green: 0.27,blue: 0.31)],startPoint: .top,endPoint: .bottom))
            WorkshopChamfer(corner: 12,insetAmount: 8).strokeBorder(active ? accent : Color.black.opacity(0.65),lineWidth: 2)
            Canvas { context,size in
                for point in [CGPoint(x: 17,y: 17),CGPoint(x: size.width-17,y: 17),CGPoint(x: 17,y: size.height-17),CGPoint(x: size.width-17,y: size.height-17)] {
                    let rect = CGRect(x: point.x-3.5,y: point.y-3.5,width: 7,height: 7)
                    context.fill(Path(ellipseIn: rect),with: .color(Color(red: 0.30,green: 0.33,blue: 0.36)))
                    var slot = Path(); slot.move(to: CGPoint(x: point.x-2,y: point.y+1));slot.addLine(to: CGPoint(x: point.x+2,y: point.y-1))
                    context.stroke(slot,with: .color(.white.opacity(0.6)),lineWidth: 1)
                }
            }.allowsHitTesting(false)
        }.compositingGroup().shadow(color: .black.opacity(0.45),radius: 0,y: 5)
    }
}

/// Rollers and side rails are real visual boundaries; cards sit in the open centre.
struct LogicConveyorBed: View {
    var vertical = false
    var active = false
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.3))
                if vertical {
                    HStack { rail;Spacer();rail }
                    VStack { roller;Spacer();roller }.padding(.horizontal, 7)
                } else {
                    VStack { horizontalRail;Spacer();horizontalRail }
                    HStack { roller.rotationEffect(.degrees(90)).frame(width: 13);Spacer();roller.rotationEffect(.degrees(90)).frame(width: 13) }.padding(.vertical, 9)
                }
                Canvas { context,size in
                    if vertical {
                        for y in stride(from: 20.0,to: size.height-14,by: 25) {
                            var p=Path();p.move(to: CGPoint(x: 14,y: y));p.addLine(to: CGPoint(x: size.width-14,y: y))
                            context.stroke(p,with: .color(.white.opacity(0.08)),lineWidth: 1)
                        }
                    } else {
                        for x in stride(from: 25.0,to: size.width-14,by: 28) {
                            var p=Path();p.move(to: CGPoint(x: x,y: 13));p.addLine(to: CGPoint(x: x,y: size.height-13))
                            context.stroke(p,with: .color(.white.opacity(0.06)),lineWidth: 1)
                        }
                    }
                }
            }.frame(width: proxy.size.width,height: proxy.size.height)
        }.allowsHitTesting(false)
    }
    private var rail: some View { Capsule().fill(LinearGradient(colors: [.gray,.white,.gray],startPoint: .leading,endPoint: .trailing)).frame(width: 8).overlay(Capsule().stroke(.black.opacity(0.7),lineWidth: 1)) }
    private var horizontalRail: some View { Capsule().fill(LinearGradient(colors: [.gray,.white,.gray],startPoint: .top,endPoint: .bottom)).frame(height: 8).overlay(Capsule().stroke(.black.opacity(0.7),lineWidth: 1)) }
    private var roller: some View { Capsule().fill(LinearGradient(colors: [.black,.gray,.white,.gray,.black],startPoint: .top,endPoint: .bottom)).frame(height: 13).overlay(Capsule().stroke(.black.opacity(0.8),lineWidth: 1)) }
}

struct LogicSignalCable: View {
    var active = false
    var color: Color = .cyan
    var body: some View {
        Canvas { context,size in
            let y=size.height/2
            var p=Path();p.move(to: CGPoint(x: 0,y: y));p.addLine(to: CGPoint(x: size.width,y: y))
            context.stroke(p,with: .color(.black.opacity(0.85)),style: StrokeStyle(lineWidth: 12,lineCap: .round))
            context.stroke(p,with: .color(active ? color : .gray),style: StrokeStyle(lineWidth: 7,lineCap: .round))
            context.stroke(p,with: .color(.white.opacity(active ? 0.6 : 0.15)),style: StrokeStyle(lineWidth: 2,lineCap: .round))
            for x in [4.0,size.width-4] {
                context.fill(Path(ellipseIn: CGRect(x: x-7,y: y-7,width: 14,height: 14)),with: .color(.gray))
                context.fill(Path(ellipseIn: CGRect(x: x-4.5,y: y-4.5,width: 9,height: 9)),with: .color(active ? color : Color(red: 0.2,green: 0.24,blue: 0.27)))
            }
        }.allowsHitTesting(false)
    }
}
