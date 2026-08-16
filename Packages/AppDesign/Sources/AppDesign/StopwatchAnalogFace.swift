import SwiftUI

public struct StopwatchAnalogFace: View {
    public let elapsedText: String
    public let endTimeText: String?
    public let secondsAngle: Double
    public let minutesAngle: Double
    public let maxDiameter: CGFloat

    public init(
        elapsedText: String,
        endTimeText: String?,
        secondsAngle: Double,
        minutesAngle: Double,
        maxDiameter: CGFloat = 280
    ) {
        self.elapsedText = elapsedText
        self.endTimeText = endTimeText
        self.secondsAngle = secondsAngle
        self.minutesAngle = minutesAngle
        self.maxDiameter = maxDiameter
    }

    public var body: some View {
        GeometryReader { geometry in
            let diameter = min(maxDiameter, max(120, geometry.size.width - AppSpacing.m * 2))
            VStack(spacing: AppSpacing.s) {
                ZStack {
                    Canvas { context, size in
                        let rect = CGRect(origin: .zero, size: size)
                        drawMainDial(context: context, rect: rect)
                        drawSubDial(context: context, rect: rect)
                        drawHand(context: context, rect: rect, angle: minutesAngle, length: diameter * 0.12, width: 2)
                        drawHand(context: context, rect: rect, angle: secondsAngle, length: diameter * 0.38, width: 2.5)
                    }
                    .frame(width: diameter, height: diameter)

                    VStack(spacing: AppSpacing.xs) {
                        Text(elapsedText)
                            .font(.title2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                    }
                    .accessibilityHidden(true)
                }
                .frame(width: diameter, height: diameter)

                if let endTimeText {
                    Text(endTimeText)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(TimerDisplayTokens.stopwatchEndTimeColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityIdentifier("timer.stopwatchDial")
        }
        .frame(minHeight: min(maxDiameter + 36, maxDiameter * 1.18))
    }

    private var accessibilityLabel: String {
        if let endTimeText {
            return "Stopwatch, elapsed \(elapsedText), \(endTimeText)"
        }
        return "Stopwatch, elapsed \(elapsedText)"
    }

    private func drawMainDial(context: GraphicsContext, rect: CGRect) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let tickInset: CGFloat = 10

        for tick in 0..<60 {
            let isMajor = tick.isMultiple(of: 5)
            let startRadius = radius - (isMajor ? 16 : 9)
            let endRadius = radius - tickInset
            var path = Path()
            path.move(to: point(center: center, radius: startRadius, angle: Double(tick) * 6))
            path.addLine(to: point(center: center, radius: endRadius, angle: Double(tick) * 6))
            context.stroke(
                path,
                with: .color(.secondary.opacity(isMajor ? 0.82 : 0.45)),
                lineWidth: isMajor ? majorTickWidth : minorTickWidth
            )
        }

        for value in stride(from: 5, through: 60, by: 5) {
            let angle = Double(value == 60 ? 0 : value) * 6
            let text = Text("\(value)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            context.draw(text, at: point(center: center, radius: radius - 30, angle: angle), anchor: .center)
        }

        var centerDot = Path()
        centerDot.addEllipse(in: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8))
        context.fill(centerDot, with: .color(TimerDisplayTokens.stopwatchHandColor))
    }

    private func drawSubDial(context: GraphicsContext, rect: CGRect) {
        let center = CGPoint(x: rect.midX, y: rect.midY - rect.height * 0.22)
        let radius = min(rect.width, rect.height) * 0.16
        var circle = Path()
        circle.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        context.stroke(circle, with: .color(.secondary.opacity(0.45)), lineWidth: 1)

        for minute in subDialLabels {
            let angle = Double(minute == 30 ? 0 : minute) / 30 * 360
            let text = Text("\(minute)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            context.draw(text, at: point(center: center, radius: radius - 10, angle: angle), anchor: .center)
        }
    }

    private func drawHand(
        context: GraphicsContext,
        rect: CGRect,
        angle: Double,
        length: CGFloat,
        width: CGFloat
    ) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.move(to: center)
        path.addLine(to: point(center: center, radius: length, angle: angle))
        context.stroke(path, with: .color(TimerDisplayTokens.stopwatchHandColor), lineWidth: width)
    }

    private func point(center: CGPoint, radius: CGFloat, angle: Double) -> CGPoint {
        let radians = (angle - 90) * .pi / 180
        return CGPoint(
            x: center.x + cos(radians) * radius,
            y: center.y + sin(radians) * radius
        )
    }

    private var majorTickWidth: CGFloat {
        #if os(watchOS)
        2.2
        #else
        1.6
        #endif
    }

    private var minorTickWidth: CGFloat {
        #if os(watchOS)
        1.1
        #else
        0.7
        #endif
    }

    private var subDialLabels: [Int] {
        #if os(watchOS)
        [10, 20, 30]
        #else
        [5, 10, 15, 20, 25, 30]
        #endif
    }
}
