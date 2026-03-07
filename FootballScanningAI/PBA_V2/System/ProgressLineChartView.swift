//
//  ProgressLineChartView.swift
//  FootballScanningAI
//
//  PBA V2 — Simple line chart for session-over-session metrics (decision score, speed, accuracy).
//

import SwiftUI

/// A single data point for the chart: session index (1-based) and value.
struct ChartDataPoint: Identifiable {
    let id = UUID()
    let sessionIndex: Int
    let value: Double
}

/// Line chart with horizontal axis = session number (or date), vertical axis = value.
struct ProgressLineChartView: View {
    let title: String
    let points: [ChartDataPoint]
    let valueLabel: String  // e.g. "%", "s"
    let yAxisRange: (min: Double, max: Double)?  // nil = auto from data
    /// When points.count < 2, show this instead of the chart. Nil = use default generic message.
    var emptyStateMessage: String? = nil

    private var effectiveYRange: (min: Double, max: Double) {
        guard !points.isEmpty else { return (0, 100) }
        if let range = yAxisRange { return range }
        let values = points.map(\.value)
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 100
        let padding = max((maxV - minV) * 0.1, 1)
        return (max(0, minV - padding), maxV + padding)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)

            if points.count < 2 {
                Text(emptyStateMessage ?? "Complete at least 2 training sessions to see your trend.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 24)
            } else {
                chartContent
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var chartContent: some View {
        let range = effectiveYRange
        return GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let paddingLeft: CGFloat = 32
            let paddingRight: CGFloat = 8
            let paddingTop: CGFloat = 8
            let paddingBottom: CGFloat = 24
            let chartW = w - paddingLeft - paddingRight
            let chartH = h - paddingTop - paddingBottom

            ZStack(alignment: .topLeading) {
                // Y-axis labels (min and max)
                VStack {
                    Text(formatValue(range.max))
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                    Spacer()
                    Text(formatValue(range.min))
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                }
                .frame(width: paddingLeft - 4, height: chartH)
                .padding(.top, paddingTop)

                // Line path
                Path { path in
                    let stepX = chartW / CGFloat(max(1, points.count - 1))
                    let scaleY = range.max > range.min ? chartH / CGFloat(range.max - range.min) : 1
                    for (i, pt) in points.enumerated() {
                        let x = paddingLeft + CGFloat(i) * stepX
                        let y = paddingTop + CGFloat(range.max - pt.value) * scaleY
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(
                    LinearGradient(
                        colors: [Color.yellow.opacity(0.9), Color.yellow.opacity(0.5)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                )

                // Dots at each point
                ForEach(Array(points.enumerated()), id: \.element.id) { i, pt in
                    let stepX = chartW / CGFloat(max(1, points.count - 1))
                    let scaleY = range.max > range.min ? chartH / CGFloat(range.max - range.min) : 1
                    let x = paddingLeft + CGFloat(i) * stepX
                    let y = paddingTop + CGFloat(range.max - pt.value) * scaleY
                    Circle()
                        .fill(Color.yellow)
                        .frame(width: 8, height: 8)
                        .position(x: x, y: y)
                }
            }
            .frame(width: w, height: h)
        }
        .frame(height: 160)
        .overlay(alignment: .bottom) {
            // X-axis: session numbers
            if !points.isEmpty {
                HStack(spacing: 0) {
                    ForEach(Array(points.enumerated()), id: \.element.id) { i, pt in
                        Text("S\(pt.sessionIndex)")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.5))
                        if i < points.count - 1 {
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 4)
            }
        }
    }

    private func formatValue(_ v: Double) -> String {
        if valueLabel == "%" {
            return "\(Int(round(v)))%"
        }
        if valueLabel == "s" {
            return String(format: "%.1fs", v)
        }
        return String(format: "%.0f", v)
    }
}
