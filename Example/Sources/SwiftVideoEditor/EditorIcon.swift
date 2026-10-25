// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Small Swift-drawn glyphs for symbols absent from Skip's Android system-image map.
struct EditorIcon: View {
    let name: String
    init(_ name: String) { self.name = name }
    var body: some View {
        #if os(Android)
        if ["film", "arrow.uturn.backward", "arrow.uturn.forward", "arrow.up.right", "backward.end.fill",
            "forward.end.fill", "pause.fill", "scissors", "textformat", "slider.horizontal.3", "music.note", "square.on.square"].contains(name) {
            Path { path in
                func line(_ points: [CGPoint]) {
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() { path.addLine(to: point) }
                }
                switch name {
                case "film":
                    path.addRoundedRect(in: CGRect(x: 2, y: 3, width: 16, height: 14), cornerSize: CGSize(width: 2, height: 2))
                    line([CGPoint(x: 6, y: 3), CGPoint(x: 6, y: 17)])
                    line([CGPoint(x: 14, y: 3), CGPoint(x: 14, y: 17)])
                case "arrow.uturn.backward", "arrow.uturn.forward":
                    let right = name == "arrow.uturn.forward"
                    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: right ? 20 - x : x, y: y) }
                    line([point(7, 3), point(3, 7), point(7, 11)])
                    path.move(to: point(3, 7)); path.addLine(to: point(12, 7))
                    path.addQuadCurve(to: point(12, 17), control: point(22, 12))
                case "arrow.up.right": line([CGPoint(x: 4, y: 16), CGPoint(x: 16, y: 4), CGPoint(x: 6, y: 4)])
                    line([CGPoint(x: 16, y: 4), CGPoint(x: 16, y: 14)])
                case "backward.end.fill", "forward.end.fill":
                    let right = name == "forward.end.fill"
                    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: right ? 20 - x : x, y: y) }
                    line([point(4, 4), point(4, 16)])
                    line([point(16, 4), point(7, 10), point(16, 16), point(16, 4)])
                case "pause.fill":
                    path.addRect(CGRect(x: 5, y: 3, width: 3, height: 14)); path.addRect(CGRect(x: 12, y: 3, width: 3, height: 14))
                case "scissors":
                    path.addEllipse(in: CGRect(x: 2, y: 2, width: 5, height: 5)); path.addEllipse(in: CGRect(x: 2, y: 13, width: 5, height: 5))
                    line([CGPoint(x: 6, y: 6), CGPoint(x: 18, y: 17)])
                    line([CGPoint(x: 6, y: 14), CGPoint(x: 18, y: 3)])
                case "textformat":
                    line([CGPoint(x: 3, y: 4), CGPoint(x: 17, y: 4)])
                    line([CGPoint(x: 10, y: 4), CGPoint(x: 10, y: 17)])
                    line([CGPoint(x: 6, y: 17), CGPoint(x: 14, y: 17)])
                case "slider.horizontal.3":
                    for index in 0..<3 {
                        let y = CGFloat(4 + index * 6), x = CGFloat(index == 1 ? 13 : 7)
                        line([CGPoint(x: 2, y: y), CGPoint(x: 18, y: y)])
                        path.addEllipse(in: CGRect(x: x - 2, y: y - 2, width: 4, height: 4))
                    }
                case "music.note":
                    path.addEllipse(in: CGRect(x: 3, y: 13, width: 6, height: 4))
                    line([CGPoint(x: 9, y: 15), CGPoint(x: 9, y: 3), CGPoint(x: 17, y: 2), CGPoint(x: 17, y: 6), CGPoint(x: 9, y: 7)])
                default:
                    path.addRoundedRect(in: CGRect(x: 2, y: 2, width: 12, height: 12), cornerSize: CGSize(width: 2, height: 2))
                    path.addRoundedRect(in: CGRect(x: 6, y: 6, width: 12, height: 12), cornerSize: CGSize(width: 2, height: 2))
                }
            }.stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)).frame(width: 20, height: 20)
        } else { Image(systemName: name) }
        #else
        Image(systemName: name)
        #endif
    }
}
