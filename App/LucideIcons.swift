// GENERATED FILE — do not edit by hand.
// Source: Lucide 1.56.0 (https://lucide.dev), ISC License — see ThirdPartyNotices.md.
// To add or remove icons, edit scripts/lucide/icons.txt and run: bash scripts/update-lucide.sh

import SwiftUI

/// Lucide icons bundled with Centwise. Raw values are the official Lucide names.
enum Lucide: String, CaseIterable, Sendable {
    case chevronLeft = "chevron-left"
    case chevronRight = "chevron-right"
    case plus = "plus"
    case circlePlus = "circle-plus"
    case circleMinus = "circle-minus"
    case check = "check"
    case search = "search"
    case circleX = "circle-x"
    case settings = "settings"
    case pencilLine = "pencil-line"
    case upload = "upload"
    case download = "download"
    case fileDown = "file-down"
    case shieldCheck = "shield-check"
    case circleAlert = "circle-alert"
    case textAlignStart = "text-align-start"
    case listFilter = "list-filter"
    case layoutGrid = "layout-grid"
    case wallet = "wallet"
    case calendar = "calendar"
}

extension Lucide {
    /// Geometry on Lucide's 24×24 grid. `stroke` is drawn with the icon's
    /// stroke width; `fill` holds the few solid dots some icons use.
    var paths: (stroke: Path, fill: Path) {
        var s = Path()
        var f = Path()
        switch self {
        case .chevronLeft:
            s.move(to: P(15, 18))
            s.addLine(to: P(9, 12))
            s.addLine(to: P(15, 6))
        case .chevronRight:
            s.move(to: P(9, 18))
            s.addLine(to: P(15, 12))
            s.addLine(to: P(9, 6))
        case .plus:
            s.move(to: P(5, 12))
            s.addLine(to: P(19, 12))
            s.move(to: P(12, 5))
            s.addLine(to: P(12, 19))
        case .circlePlus:
            s.addEllipse(in: R(2, 2, 20, 20))
            s.move(to: P(8, 12))
            s.addLine(to: P(16, 12))
            s.move(to: P(12, 8))
            s.addLine(to: P(12, 16))
        case .circleMinus:
            s.addEllipse(in: R(2, 2, 20, 20))
            s.move(to: P(8, 12))
            s.addLine(to: P(16, 12))
        case .check:
            s.move(to: P(20, 6))
            s.addLine(to: P(9, 17))
            s.addLine(to: P(4, 12))
        case .search:
            s.move(to: P(21, 21))
            s.addLine(to: P(16.66, 16.66))
            s.addEllipse(in: R(3, 3, 16, 16))
        case .circleX:
            s.addEllipse(in: R(2, 2, 20, 20))
            s.move(to: P(15, 9))
            s.addLine(to: P(9, 15))
            s.move(to: P(9, 9))
            s.addLine(to: P(15, 15))
        case .settings:
            s.move(to: P(9.671, 4.136))
            s.addCurve(to: P(12.0005, 2.0174), control1: P(9.7852, 2.9348), control2: P(10.7939, 2.0174))
            s.addCurve(to: P(14.33, 4.136), control1: P(13.2071, 2.0174), control2: P(14.2158, 2.9348))
            s.addCurve(to: P(15.4915, 5.9567), control1: P(14.3972, 4.8959), control2: P(14.8307, 5.5754))
            s.addCurve(to: P(17.649, 6.051), control1: P(16.1523, 6.3379), control2: P(16.9574, 6.3731))
            s.addCurve(to: P(20.6425, 7.0111), control1: P(18.7452, 5.5533), control2: P(20.0402, 5.9686))
            s.addCurve(to: P(19.979, 10.084), control1: P(21.2448, 8.0536), control2: P(20.9577, 9.3829))
            s.addCurve(to: P(18.983, 11.9995), control1: P(19.3547, 10.522), control2: P(18.983, 11.2369))
            s.addCurve(to: P(19.979, 13.915), control1: P(18.983, 12.7621), control2: P(19.3547, 13.477))
            s.addCurve(to: P(20.6425, 16.9879), control1: P(20.9577, 14.6161), control2: P(21.2448, 15.9454))
            s.addCurve(to: P(17.649, 17.948), control1: P(20.0402, 18.0304), control2: P(18.7452, 18.4457))
            s.addCurve(to: P(15.4915, 18.0423), control1: P(16.9574, 17.6259), control2: P(16.1523, 17.6611))
            s.addCurve(to: P(14.33, 19.863), control1: P(14.8307, 18.4236), control2: P(14.3972, 19.1031))
            s.addCurve(to: P(12.0005, 21.9816), control1: P(14.2158, 21.0642), control2: P(13.2071, 21.9816))
            s.addCurve(to: P(9.671, 19.863), control1: P(10.7939, 21.9816), control2: P(9.7852, 21.0642))
            s.addCurve(to: P(8.5092, 18.0417), control1: P(9.6039, 19.1028), control2: P(9.1703, 18.423))
            s.addCurve(to: P(6.351, 17.948), control1: P(7.8481, 17.6604), control2: P(7.0427, 17.6254))
            s.addCurve(to: P(3.3575, 16.9879), control1: P(5.2548, 18.4457), control2: P(3.9598, 18.0304))
            s.addCurve(to: P(4.021, 13.915), control1: P(2.7552, 15.9454), control2: P(3.0423, 14.6161))
            s.addCurve(to: P(5.017, 11.9995), control1: P(4.6453, 13.477), control2: P(5.017, 12.7621))
            s.addCurve(to: P(4.021, 10.084), control1: P(5.017, 11.2369), control2: P(4.6453, 10.522))
            s.addCurve(to: P(3.359, 7.0127), control1: P(3.0437, 9.3826), control2: P(2.7574, 8.0544))
            s.addCurve(to: P(6.35, 6.051), control1: P(3.9606, 5.971), control2: P(5.254, 5.5551))
            s.addCurve(to: P(8.5075, 5.9567), control1: P(7.0416, 6.3731), control2: P(7.8467, 6.3379))
            s.addCurve(to: P(9.669, 4.136), control1: P(9.1683, 5.5754), control2: P(9.6018, 4.8959))
            s.addEllipse(in: R(9, 9, 6, 6))
        case .pencilLine:
            s.move(to: P(13, 21))
            s.addLine(to: P(21, 21))
            s.move(to: P(15, 5))
            s.addLine(to: P(19, 9))
            s.move(to: P(21.174, 6.812))
            s.addCurve(to: P(21.1745, 2.8255), control1: P(22.275, 5.7113), control2: P(22.2752, 3.9265))
            s.addCurve(to: P(17.188, 2.825), control1: P(20.0738, 1.7245), control2: P(18.289, 1.7243))
            s.addLine(to: P(3.842, 16.174))
            s.addCurve(to: P(3.342, 17.004), control1: P(3.6098, 16.4055), control2: P(3.4381, 16.6905))
            s.addLine(to: P(2.021, 21.356))
            s.addCurve(to: P(2.1468, 21.853), control1: P(1.9683, 21.5322), control2: P(2.0167, 21.7231))
            s.addCurve(to: P(2.644, 21.978), control1: P(2.2769, 21.9829), control2: P(2.4679, 22.0309))
            s.addLine(to: P(6.997, 20.658))
            s.addCurve(to: P(7.827, 20.161), control1: P(7.3102, 20.5628), control2: P(7.5952, 20.3921))
            s.closeSubpath()
        case .upload:
            s.move(to: P(12, 3))
            s.addLine(to: P(12, 15))
            s.move(to: P(17, 8))
            s.addLine(to: P(12, 3))
            s.addLine(to: P(7, 8))
            s.move(to: P(21, 15))
            s.addLine(to: P(21, 19))
            s.addCurve(to: P(19, 21), control1: P(21, 20.1046), control2: P(20.1046, 21))
            s.addLine(to: P(5, 21))
            s.addCurve(to: P(3, 19), control1: P(3.8954, 21), control2: P(3, 20.1046))
            s.addLine(to: P(3, 15))
        case .download:
            s.move(to: P(12, 15))
            s.addLine(to: P(12, 3))
            s.move(to: P(21, 15))
            s.addLine(to: P(21, 19))
            s.addCurve(to: P(19, 21), control1: P(21, 20.1046), control2: P(20.1046, 21))
            s.addLine(to: P(5, 21))
            s.addCurve(to: P(3, 19), control1: P(3.8954, 21), control2: P(3, 20.1046))
            s.addLine(to: P(3, 15))
            s.move(to: P(7, 10))
            s.addLine(to: P(12, 15))
            s.addLine(to: P(17, 10))
        case .fileDown:
            s.move(to: P(6, 22))
            s.addCurve(to: P(4, 20), control1: P(4.8954, 22), control2: P(4, 21.1046))
            s.addLine(to: P(4, 4))
            s.addCurve(to: P(6, 2), control1: P(4, 2.8954), control2: P(4.8954, 2))
            s.addLine(to: P(14, 2))
            s.addCurve(to: P(15.704, 2.706), control1: P(14.6394, 1.999), control2: P(15.2527, 2.2531))
            s.addLine(to: P(19.292, 6.294))
            s.addCurve(to: P(20, 8), control1: P(19.7461, 6.7454), control2: P(20.001, 7.3597))
            s.addLine(to: P(20, 20))
            s.addCurve(to: P(18, 22), control1: P(20, 21.1046), control2: P(19.1046, 22))
            s.closeSubpath()
            s.move(to: P(14, 2))
            s.addLine(to: P(14, 7))
            s.addCurve(to: P(15, 8), control1: P(14, 7.5523), control2: P(14.4477, 8))
            s.addLine(to: P(20, 8))
            s.move(to: P(12, 18))
            s.addLine(to: P(12, 12))
            s.move(to: P(9, 15))
            s.addLine(to: P(12, 18))
            s.addLine(to: P(15, 15))
        case .shieldCheck:
            s.move(to: P(20, 13))
            s.addCurve(to: P(12.34, 21.95), control1: P(20, 18), control2: P(16.5, 20.5))
            s.addCurve(to: P(11.67, 21.94), control1: P(12.1222, 22.0238), control2: P(11.8855, 22.0203))
            s.addCurve(to: P(4, 13), control1: P(7.5, 20.5), control2: P(4, 18))
            s.addLine(to: P(4, 6))
            s.addCurve(to: P(5, 5), control1: P(4, 5.4477), control2: P(4.4477, 5))
            s.addCurve(to: P(11.24, 2.28), control1: P(7, 5), control2: P(9.5, 3.8))
            s.addCurve(to: P(12.76, 2.28), control1: P(11.6777, 1.9061), control2: P(12.3223, 1.9061))
            s.addCurve(to: P(19, 5), control1: P(14.51, 3.81), control2: P(17, 5))
            s.addCurve(to: P(20, 6), control1: P(19.5523, 5), control2: P(20, 5.4477))
            s.closeSubpath()
            s.move(to: P(9, 12))
            s.addLine(to: P(11, 14))
            s.addLine(to: P(15, 10))
        case .circleAlert:
            s.addEllipse(in: R(2, 2, 20, 20))
            s.move(to: P(12, 8))
            s.addLine(to: P(12, 12))
            s.move(to: P(12, 16))
            s.addLine(to: P(12.01, 16))
        case .textAlignStart:
            s.move(to: P(21, 5))
            s.addLine(to: P(3, 5))
            s.move(to: P(15, 12))
            s.addLine(to: P(3, 12))
            s.move(to: P(17, 19))
            s.addLine(to: P(3, 19))
        case .listFilter:
            s.move(to: P(2, 5))
            s.addLine(to: P(22, 5))
            s.move(to: P(6, 12))
            s.addLine(to: P(18, 12))
            s.move(to: P(9, 19))
            s.addLine(to: P(15, 19))
        case .layoutGrid:
            s.addRoundedRect(in: R(3, 3, 7, 7), cornerSize: CGSize(width: 1, height: 1), style: .circular)
            s.addRoundedRect(in: R(14, 3, 7, 7), cornerSize: CGSize(width: 1, height: 1), style: .circular)
            s.addRoundedRect(in: R(14, 14, 7, 7), cornerSize: CGSize(width: 1, height: 1), style: .circular)
            s.addRoundedRect(in: R(3, 14, 7, 7), cornerSize: CGSize(width: 1, height: 1), style: .circular)
        case .wallet:
            s.move(to: P(19, 7))
            s.addLine(to: P(19, 4))
            s.addCurve(to: P(18, 3), control1: P(19, 3.4477), control2: P(18.5523, 3))
            s.addLine(to: P(5, 3))
            s.addCurve(to: P(3, 5), control1: P(3.8954, 3), control2: P(3, 3.8954))
            s.addCurve(to: P(5, 7), control1: P(3, 6.1046), control2: P(3.8954, 7))
            s.addLine(to: P(20, 7))
            s.addCurve(to: P(21, 8), control1: P(20.5523, 7), control2: P(21, 7.4477))
            s.addLine(to: P(21, 12))
            s.addLine(to: P(18, 12))
            s.addCurve(to: P(16, 14), control1: P(16.8954, 12), control2: P(16, 12.8954))
            s.addCurve(to: P(18, 16), control1: P(16, 15.1046), control2: P(16.8954, 16))
            s.addLine(to: P(21, 16))
            s.addCurve(to: P(22, 15), control1: P(21.5523, 16), control2: P(22, 15.5523))
            s.addLine(to: P(22, 13))
            s.addCurve(to: P(21, 12), control1: P(22, 12.4477), control2: P(21.5523, 12))
            s.move(to: P(3, 5))
            s.addLine(to: P(3, 19))
            s.addCurve(to: P(5, 21), control1: P(3, 20.1046), control2: P(3.8954, 21))
            s.addLine(to: P(20, 21))
            s.addCurve(to: P(21, 20), control1: P(20.5523, 21), control2: P(21, 20.5523))
            s.addLine(to: P(21, 16))
        case .calendar:
            s.move(to: P(8, 2))
            s.addLine(to: P(8, 5))
            s.move(to: P(16, 2))
            s.addLine(to: P(16, 5))
            s.addRoundedRect(in: R(3, 3, 18, 18), cornerSize: CGSize(width: 2, height: 2), style: .circular)
            s.move(to: P(3, 9))
            s.addLine(to: P(21, 9))
        }
        return (s, f)
    }
}

private func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
private func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }
