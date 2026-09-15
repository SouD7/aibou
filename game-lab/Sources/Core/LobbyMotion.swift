import Foundation

/// The lobby character only blinks. Body, face position and mouth stay still.
public enum LobbyMotion {
    public static func blink(at time: Double) -> Double {
        let phase = max(0, time).truncatingRemainder(dividingBy: 6.8)
        func pulse(_ center: Double, _ duration: Double) -> Double {
            let distance = abs(phase - center)
            guard distance < duration / 2 else { return 0 }
            return 0.5 + 0.5 * cos(.pi * distance / (duration / 2))
        }
        return max(pulse(2.7, 0.24), pulse(6.05, 0.20))
    }

}
