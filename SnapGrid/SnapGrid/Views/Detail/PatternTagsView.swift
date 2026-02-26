import SwiftUI

struct PatternTagsView: View {
    let item: MediaItem
    var onRetryAnalysis: (() -> Void)?

    var body: some View {
        Group {
            if item.isAnalyzing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Analyzing...")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.snapMuted)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if let error = item.analysisError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 12))
                        .foregroundStyle(.red.opacity(0.8))
                    Text("Analysis failed")
                        .font(.system(size: 12))
                        .foregroundStyle(.red.opacity(0.8))
                    if let onRetry = onRetryAnalysis {
                        Button("Retry", action: onRetry)
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .help(error)
            } else if let patterns = item.analysisResult?.patterns, !patterns.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(patterns, id: \.name) { pattern in
                        HStack(spacing: 4) {
                            Text(pattern.name)
                                .font(.system(size: 12, weight: .medium))
                            Text("\(Int(pattern.confidence * 100))%")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.snapMuted)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }
}
