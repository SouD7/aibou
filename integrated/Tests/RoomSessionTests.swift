import Foundation

@main
struct RoomSessionTests {
    static func main() {
        let origin = Date(timeIntervalSince1970: 1000)
        var session = RoomSession(now: origin)
        precondition(!session.shouldChoosePose(now: origin.addingTimeInterval(29.999)))
        precondition(session.shouldChoosePose(now: origin.addingTimeInterval(30)))
        precondition(!session.shouldChoosePose(now: origin.addingTimeInterval(30)))
        precondition(session.shouldChoosePose(now: origin.addingTimeInterval(60)))
        session.beginConsultation()
        precondition(session.isConsulting && !session.isDemo)
        precondition(!session.shouldChoosePose(now: origin.addingTimeInterval(900)))
        session.endConsultation(now: origin.addingTimeInterval(900))
        precondition(!session.shouldChoosePose(now: origin.addingTimeInterval(929.999)))
        precondition(session.shouldChoosePose(now: origin.addingTimeInterval(930)))
        session.enterDemo()
        precondition(session.isDemo && !session.isConsulting)
        precondition(!session.shouldChoosePose(now: origin.addingTimeInterval(1000)))
        session.leaveDemo(now: origin.addingTimeInterval(1000))
        precondition(!session.shouldChoosePose(now: origin.addingTimeInterval(1029)))
        precondition(session.shouldChoosePose(now: origin.addingTimeInterval(1030)))
        let warning = ComponentWarning(message: "test")
        let warnings = ["fan-1": warning, "fan-2": warning, "bookshelf": warning, "compute": warning]
        session.acknowledge("fan-1")
        session.acknowledge("bookshelf")
        precondition(Set(session.visibleWarnings(warnings).keys) == ["compute"])
        precondition(session.visibleWarnings(["fans": warning]).isEmpty)
        precondition(session.visibleWarnings([:]).isEmpty)
        // Recovery, recurrence, and demo/consultation transitions cannot undo acknowledgement.
        session.enterDemo()
        session.leaveDemo()
        session.beginConsultation()
        session.endConsultation()
        precondition(session.visibleWarnings(["bookshelf": warning]).isEmpty)
        let relaunched = RoomSession(now: origin)
        precondition(relaunched.visibleWarnings(warnings).count == 4)
        print("RoomSessionTests: OK (timer, consultation, demo, acknowledgement, relaunch)")
    }
}
