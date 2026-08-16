import SwiftUI

public enum AppSymbols {
    public enum Timer {
        public static let idle = "timer"
        public static let pause = "pause.fill"
        public static let resume = "play.fill"
        public static let stop = "stop.fill"
    }

    public enum Tasks {
        public static let complete = "checkmark.circle.fill"
        public static let incomplete = "circle"
        public static let add = "plus"
        public static let scheduleToday = "sun.max"
        public static let delete = "trash"
    }

    public enum Navigation {
        public static let today = "sun.max"
        public static let pool = "tray.full"
        public static let timer = "timer"
        public static let settings = "gearshape"
        public static let taskHub = "checklist"
    }
}
