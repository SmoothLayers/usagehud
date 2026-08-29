import CoreGraphics
import Foundation
import SwiftUI

/// Builds a `Path` from SVG path data.
///
/// The provider marks ship as path strings rather than image assets so they
/// stay vector-crisp at any ring size and tint with the surrounding
/// foreground style, without adding resources to the bundle.
///
/// Supports the full command set used by those marks: moves, lines, horizontal
/// and vertical lines, cubic and quadratic curves (including their smooth
/// forms), elliptical arcs, and close.
enum SVGPath {
    /// Parses `data` in a square viewBox and fits it into `rect`.
    static func path(_ data: String, viewBox: CGFloat, in rect: CGRect) -> Path {
        var builder = Builder(data: data)
        let raw = builder.build()
        guard viewBox > 0 else { return raw }

        let scale = min(rect.width, rect.height) / viewBox
        let transform = CGAffineTransform(translationX: rect.midX - viewBox * scale / 2,
                                          y: rect.midY - viewBox * scale / 2)
            .scaledBy(x: scale, y: scale)
        return raw.applying(transform)
    }

    private struct Builder {
        private let characters: [Character]
        private var index = 0
        private var path = Path()
        private var current = CGPoint.zero
        private var subpathStart = CGPoint.zero
        private var lastCubicControl: CGPoint?
        private var lastQuadControl: CGPoint?

        init(data: String) {
            characters = Array(data)
        }

        mutating func build() -> Path {
            var command: Character?
            while true {
                skipSeparators()
                guard index < characters.count else { break }

                if characters[index].isLetter {
                    command = characters[index]
                    index += 1
                } else if command == nil {
                    break
                } else if command == "M" {
                    // Repeated coordinate pairs after a move are line-tos.
                    command = "L"
                } else if command == "m" {
                    command = "l"
                }

                guard let command, apply(command) else { break }
            }
            return path
        }

        private mutating func apply(_ command: Character) -> Bool {
            let relative = command.isLowercase
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
            }

            switch command {
            case "M", "m":
                guard let x = number(), let y = number() else { return false }
                current = point(x, y)
                subpathStart = current
                path.move(to: current)
                lastCubicControl = nil
                lastQuadControl = nil

            case "L", "l":
                guard let x = number(), let y = number() else { return false }
                current = point(x, y)
                path.addLine(to: current)
                lastCubicControl = nil
                lastQuadControl = nil

            case "H", "h":
                guard let x = number() else { return false }
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current)
                lastCubicControl = nil
                lastQuadControl = nil

            case "V", "v":
                guard let y = number() else { return false }
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current)
                lastCubicControl = nil
                lastQuadControl = nil

            case "C", "c":
                guard let x1 = number(), let y1 = number(),
                      let x2 = number(), let y2 = number(),
                      let x = number(), let y = number() else { return false }
                let control1 = point(x1, y1)
                let control2 = point(x2, y2)
                current = point(x, y)
                path.addCurve(to: current, control1: control1, control2: control2)
                lastCubicControl = control2
                lastQuadControl = nil

            case "S", "s":
                guard let x2 = number(), let y2 = number(),
                      let x = number(), let y = number() else { return false }
                let control1 = reflection(of: lastCubicControl)
                let control2 = point(x2, y2)
                current = point(x, y)
                path.addCurve(to: current, control1: control1, control2: control2)
                lastCubicControl = control2
                lastQuadControl = nil

            case "Q", "q":
                guard let x1 = number(), let y1 = number(),
                      let x = number(), let y = number() else { return false }
                let control = point(x1, y1)
                current = point(x, y)
                path.addQuadCurve(to: current, control: control)
                lastQuadControl = control
                lastCubicControl = nil

            case "T", "t":
                guard let x = number(), let y = number() else { return false }
                let control = reflection(of: lastQuadControl)
                current = point(x, y)
                path.addQuadCurve(to: current, control: control)
                lastQuadControl = control
                lastCubicControl = nil

            case "A", "a":
                guard let rx = number(), let ry = number(), let rotation = number(),
                      let largeArc = flag(), let sweep = flag(),
                      let x = number(), let y = number() else { return false }
                let end = point(x, y)
                addArc(to: end, rx: rx, ry: ry, rotation: rotation, largeArc: largeArc, sweep: sweep)
                current = end
                lastCubicControl = nil
                lastQuadControl = nil

            case "Z", "z":
                path.closeSubpath()
                current = subpathStart
                lastCubicControl = nil
                lastQuadControl = nil

            default:
                return false
            }
            return true
        }

        private func reflection(of control: CGPoint?) -> CGPoint {
            guard let control else { return current }
            return CGPoint(x: 2 * current.x - control.x, y: 2 * current.y - control.y)
        }

        /// Endpoint-to-centre arc conversion, then split into cubic segments of
        /// at most a quarter turn each (W3C SVG implementation notes F.6).
        private mutating func addArc(
            to end: CGPoint,
            rx: CGFloat,
            ry: CGFloat,
            rotation: CGFloat,
            largeArc: Bool,
            sweep: Bool
        ) {
            let start = current
            guard rx != 0, ry != 0, start != end else {
                path.addLine(to: end)
                return
            }

            var radiusX = abs(rx)
            var radiusY = abs(ry)
            let phi = rotation * .pi / 180
            let cosPhi = cos(phi), sinPhi = sin(phi)

            let dx2 = (start.x - end.x) / 2
            let dy2 = (start.y - end.y) / 2
            let x1p = cosPhi * dx2 + sinPhi * dy2
            let y1p = -sinPhi * dx2 + cosPhi * dy2

            // Scale the radii up if they are too small to span the endpoints.
            let lambda = (x1p * x1p) / (radiusX * radiusX) + (y1p * y1p) / (radiusY * radiusY)
            if lambda > 1 {
                let scale = sqrt(lambda)
                radiusX *= scale
                radiusY *= scale
            }

            let sign: CGFloat = largeArc == sweep ? -1 : 1
            let numerator = max(0, radiusX * radiusX * radiusY * radiusY
                - radiusX * radiusX * y1p * y1p
                - radiusY * radiusY * x1p * x1p)
            let denominator = radiusX * radiusX * y1p * y1p + radiusY * radiusY * x1p * x1p
            let coefficient = denominator == 0 ? 0 : sign * sqrt(numerator / denominator)

            let cxp = coefficient * radiusX * y1p / radiusY
            let cyp = -coefficient * radiusY * x1p / radiusX
            let centre = CGPoint(
                x: cosPhi * cxp - sinPhi * cyp + (start.x + end.x) / 2,
                y: sinPhi * cxp + cosPhi * cyp + (start.y + end.y) / 2
            )

            func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
                let dot = ux * vx + uy * vy
                let length = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
                guard length > 0 else { return 0 }
                let value = min(1, max(-1, dot / length))
                return (ux * vy - uy * vx < 0 ? -1 : 1) * acos(value)
            }

            let ux = (x1p - cxp) / radiusX
            let uy = (y1p - cyp) / radiusY
            let vx = (-x1p - cxp) / radiusX
            let vy = (-y1p - cyp) / radiusY

            let startAngle = angle(1, 0, ux, uy)
            var sweepAngle = angle(ux, uy, vx, vy)
            if !sweep, sweepAngle > 0 {
                sweepAngle -= 2 * .pi
            } else if sweep, sweepAngle < 0 {
                sweepAngle += 2 * .pi
            }

            let segments = max(1, Int(ceil(abs(sweepAngle) / (.pi / 2))))
            let delta = sweepAngle / CGFloat(segments)
            // Magic constant for approximating a circular arc with a cubic.
            let alpha = 4.0 / 3.0 * tan(delta / 4)

            var theta = startAngle
            for _ in 0..<segments {
                let next = theta + delta
                let p1 = arcPoint(centre: centre, rx: radiusX, ry: radiusY, cosPhi: cosPhi, sinPhi: sinPhi, angle: theta)
                let p2 = arcPoint(centre: centre, rx: radiusX, ry: radiusY, cosPhi: cosPhi, sinPhi: sinPhi, angle: next)
                let d1 = arcDerivative(rx: radiusX, ry: radiusY, cosPhi: cosPhi, sinPhi: sinPhi, angle: theta)
                let d2 = arcDerivative(rx: radiusX, ry: radiusY, cosPhi: cosPhi, sinPhi: sinPhi, angle: next)
                path.addCurve(
                    to: p2,
                    control1: CGPoint(x: p1.x + alpha * d1.x, y: p1.y + alpha * d1.y),
                    control2: CGPoint(x: p2.x - alpha * d2.x, y: p2.y - alpha * d2.y)
                )
                theta = next
            }
        }

        private func arcPoint(centre: CGPoint, rx: CGFloat, ry: CGFloat, cosPhi: CGFloat, sinPhi: CGFloat, angle: CGFloat) -> CGPoint {
            let x = rx * cos(angle), y = ry * sin(angle)
            return CGPoint(x: centre.x + cosPhi * x - sinPhi * y, y: centre.y + sinPhi * x + cosPhi * y)
        }

        private func arcDerivative(rx: CGFloat, ry: CGFloat, cosPhi: CGFloat, sinPhi: CGFloat, angle: CGFloat) -> CGPoint {
            let dx = -rx * sin(angle), dy = ry * cos(angle)
            return CGPoint(x: cosPhi * dx - sinPhi * dy, y: sinPhi * dx + cosPhi * dy)
        }

        // MARK: Scanning

        private mutating func skipSeparators() {
            while index < characters.count, characters[index] == " " || characters[index] == ","
                || characters[index] == "\n" || characters[index] == "\t" || characters[index] == "\r" {
                index += 1
            }
        }

        /// Arc flags are single characters and may be packed against the next
        /// number, so they cannot go through the number scanner.
        private mutating func flag() -> Bool? {
            skipSeparators()
            guard index < characters.count, let value = characters[index].wholeNumberValue, value == 0 || value == 1 else {
                return nil
            }
            index += 1
            return value == 1
        }

        private mutating func number() -> CGFloat? {
            skipSeparators()
            let start = index
            if index < characters.count, characters[index] == "-" || characters[index] == "+" {
                index += 1
            }
            var sawDot = false
            while index < characters.count {
                let character = characters[index]
                if character.isNumber {
                    index += 1
                } else if character == ".", !sawDot {
                    // A second dot begins the next number: "1.5.3" is 1.5 then .3
                    sawDot = true
                    index += 1
                } else if character == "e" || character == "E" {
                    index += 1
                    if index < characters.count, characters[index] == "-" || characters[index] == "+" {
                        index += 1
                    }
                } else {
                    break
                }
            }
            guard index > start, let value = Double(String(characters[start..<index])) else {
                index = start
                return nil
            }
            return CGFloat(value)
        }
    }
}
