//
//  SessionReportView.swift
//  FootballScanningAI
//
//  PBA V2 — Shareable session report layout (image/PDF). Player name, date, activity, summary, key metrics, coaching insight.
//

import SwiftUI
import UIKit

/// Report layout for sharing as image or PDF. Light background, dark text, fixed size for rendering.
struct SessionReportView: View {
    let session: SessionResult
    let playerName: String

    private var activityName: String { session.activityType.displayName }
    private var dateString: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: session.date)
    }
    private var firstTouchCommitmentPercent: Int? {
        guard let match = session.firstTouchMatchCount, session.totalReps > 0 else { return nil }
        return Int(round(Double(match) / Double(session.totalReps) * 100.0))
    }
    private var preReceiveRatePercent: Int? {
        guard let count = session.preReceiveDecisionCount, session.totalReps > 0 else { return nil }
        return Int(round(Double(count) / Double(session.totalReps) * 100.0))
    }
    private var coachInsightText: String { CoachInsightGenerator.coachInsight(for: session) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Session Report")
                    .font(.title2.bold())
                    .foregroundColor(.black)
                Text(playerName)
                    .font(.headline)
                    .foregroundColor(.black.opacity(0.9))
                Text(dateString)
                    .font(.subheadline)
                    .foregroundColor(.black.opacity(0.7))
                Text(activityName)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.black.opacity(0.85))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 4)

            Divider()
                .background(Color.black.opacity(0.2))

            // Session Summary
            VStack(alignment: .leading, spacing: 8) {
                Text("Session Summary")
                    .font(.headline)
                    .foregroundColor(.black)
                HStack(spacing: 16) {
                    reportRow("Correct decisions", value: "\(session.correctCount)")
                    reportRow("Total reps", value: "\(session.totalReps)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Key Metrics
            VStack(alignment: .leading, spacing: 8) {
                Text("Key Metrics")
                    .font(.headline)
                    .foregroundColor(.black)
                decisionSpeedReportBlock
                if let pct = preReceiveRatePercent {
                    reportRow("Pre-receive decision rate", value: "\(pct)%")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .background(Color.black.opacity(0.2))

            // Coaching Insight
            VStack(alignment: .leading, spacing: 6) {
                Text("Coaching Insight")
                    .font(.headline)
                    .foregroundColor(.black)
                Text(coachInsightText)
                    .font(.subheadline)
                    .foregroundColor(.black.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(width: 400, height: 560)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.black.opacity(0.12), lineWidth: 1)
        )
    }

    private var decisionSpeedReportBlock: some View {
        let c = session.speedCounts
        let bucket = UniversalBlockSummaryHeadline.resolve(fast: c.fast, medium: c.medium, slow: c.slow).bucket
        let line = BlockSummarySpeedCountsFormatting.summaryLine(fast: c.fast, medium: c.medium, slow: c.slow)
        return HStack(alignment: .top, spacing: 12) {
            Text("Decision speed")
                .font(.subheadline)
                .foregroundColor(.black.opacity(0.75))
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(bucket.rawValue.capitalized)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.black)
                Text(line)
                    .font(.caption2)
                    .foregroundColor(.black.opacity(0.55))
                    .onAppear {
                        #if DEBUG
                        SummaryCountsLineDebugLog.log(
                            activity: session.activityType,
                            fast: c.fast,
                            medium: c.medium,
                            slow: c.slow,
                            renderedLine: line
                        )
                        #endif
                    }
            }
        }
    }

    private func reportRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.black.opacity(0.75))
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.black)
        }
    }
}

// MARK: - Export to image and PDF

enum SessionReportExporter {
    /// Renders the session report to a UIImage (for sharing as image). Returns nil if rendering fails.
    static func exportImage(session: SessionResult, playerName: String) -> UIImage? {
        let content = SessionReportView(session: session, playerName: playerName)
        let renderer = ImageRenderer(content: content)
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage
    }

    /// Renders the session report to a PDF file and returns the temporary file URL. Caller should delete the file after sharing.
    static func exportPDF(session: SessionResult, playerName: String) -> URL? {
        let content = SessionReportView(session: session, playerName: playerName)
        let renderer = ImageRenderer(content: content)
        let size = CGSize(width: 400, height: 560)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionReport-\(UUID().uuidString).pdf")
        var mediaBox = CGRect(origin: .zero, size: CGSize(width: size.width + 40, height: size.height + 40))
        guard let consumer = CGDataConsumer(url: tempURL as CFURL),
              let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }
        pdfContext.beginPDFPage(nil)
        pdfContext.translateBy(x: 20, y: 20)
        renderer.render { contentSize, drawInContext in
            drawInContext(pdfContext)
        }
        pdfContext.endPDFPage()
        pdfContext.closePDF()
        return tempURL
    }
}
