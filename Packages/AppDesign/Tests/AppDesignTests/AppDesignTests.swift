import SwiftUI
import Testing
@testable import AppDesign

@Suite("AppDesign")
struct AppDesignTests {
    @Test("spacing tokens match the design system")
    func spacingTokens() {
        #expect(AppSpacing.xs == 4)
        #expect(AppSpacing.s == 8)
        #expect(AppSpacing.m == 16)
        #expect(AppSpacing.l == 24)
        #expect(AppSpacing.xl == 32)
        #expect(AppSpacing.xxl == 48)
    }

    @Test("radius and animation tokens match the design system")
    func radiusAndDurationTokens() {
        #expect(AppRadius.small == 6)
        #expect(AppRadius.medium == 10)
        #expect(AppRadius.large == 16)

        #expect(AppDuration.fast == 0.15)
        #expect(AppDuration.normal == 0.25)
        #expect(AppDuration.slow == 0.4)
    }

    @Test("idle timer symbol is a named catalogue entry")
    func timerIdleSymbol() {
        #expect(AppSymbols.Timer.idle == "timer")
    }

    @Test("navigation tab symbols are catalogue entries")
    func navigationTabSymbols() {
        #expect(AppSymbols.Navigation.today == "sun.max")
        #expect(AppSymbols.Navigation.pool == "tray.full")
        #expect(AppSymbols.Navigation.timer == "timer")
        #expect(AppSymbols.Navigation.settings == "gearshape")
    }

    @Test("timer control tones map to expected semantic colors")
    func timerControlToneColors() {
        #expect(TimerControlButton.Tone.positive.color == .green)
        #expect(TimerControlButton.Tone.caution.color == .red)
        #expect(TimerControlButton.Tone.neutral.color == .primary)
    }

    @Test("task timer action bar exposes countdown identity")
    @MainActor
    func taskTimerActionBarIdentifier() {
        let bar = TaskTimerActionBar(
            countdown: "12:00",
            statusText: "Running",
            isPaused: false,
            onPauseResume: {},
            onStop: {}
        )
        #expect(bar.countdown == "12:00")
        #expect(bar.isPaused == false)
    }

    @Test("timer display tokens expose stopwatch colors")
    func timerDisplayTokens() {
        #expect(TimerDisplayTokens.stopwatchHandColor == .orange)
        #expect(TimerDisplayTokens.stopwatchEndTimeColor == .red)
        #expect(TimerDisplayTokens.timerPauseRingColor == .orange)
    }

    @Test("timer countdown row stores plain presentation values")
    @MainActor
    func timerCountdownRowStoresValues() {
        let row = TimerCountdownRow(
            remainingText: "25:00",
            durationText: "25 min",
            isActive: true,
            isPaused: false,
            onPauseResume: {}
        )

        #expect(row.remainingText == "25:00")
        #expect(row.durationText == "25 min")
        #expect(row.isActive)
    }

    @Test("stopwatch analog face stores angle values")
    @MainActor
    func stopwatchAnalogFaceStoresValues() {
        let face = StopwatchAnalogFace(
            elapsedText: "01:05.42",
            endTimeText: "Ends 2:30 PM",
            secondsAngle: 180,
            minutesAngle: 12,
            maxDiameter: 220
        )

        #expect(face.elapsedText == "01:05.42")
        #expect(face.endTimeText == "Ends 2:30 PM")
        #expect(face.secondsAngle == 180)
        #expect(face.minutesAngle == 12)
    }

    @Test("timer display mode pager can be initialized")
    @MainActor
    func timerDisplayModePagerInitializes() {
        let pager = TimerDisplayModePager {
            Text("Timer")
        } stopwatchPage: {
            Text("Stopwatch")
        }

        _ = pager.body
    }
}
