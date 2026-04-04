import SwiftUI

// MARK: - Detail Metadata Section

struct DetailMetadataSection: View {
    let item: MediaItem
    let stage: Int
    var onSearchPattern: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if item.isAnalyzing {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.white)
                    Text("Analyzing...")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .stageReveal(stage: stage, threshold: 1)
            } else if item.analysisError != nil {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 13))
                        .foregroundStyle(.red.opacity(0.8))
                    Text("Analysis failed")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .stageReveal(stage: stage, threshold: 1)
            } else if let result = item.analysisResult {
                if !result.imageSummary.isEmpty {
                    Text(result.imageSummary)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(2)
                        .stageReveal(stage: stage, threshold: 1)
                        .padding(.bottom, 12)
                }

                if !result.patterns.isEmpty {
                    patternPillsGrid(result.patterns)
                        .padding(.bottom, 18)
                }

                if hasDescription(result) {
                    Text(result.imageContext)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(stage >= 3 ? 1 : 0)
                        .animation(SnapSpring.resolvedMetadata, value: stage)
                }
            }

            HStack(spacing: 0) {
                Text("\(item.width) \u{00D7} \(item.height)")
                Text("  \u{00B7}  ")
                    .foregroundStyle(.white.opacity(0.15))
                Text(item.createdAt, style: .date)
                if let duration = item.duration {
                    Text("  \u{00B7}  ")
                        .foregroundStyle(.white.opacity(0.15))
                    Text(formatDuration(duration))
                }
            }
            .font(.caption.monospaced())
            .foregroundStyle(.white.opacity(0.25))
            .stageReveal(stage: stage, threshold: 4)
            .padding(.top, 16)

            if let urlString = item.sourceURL, let url = URL(string: urlString) {
                SourceLinkButton(url: url)
                    .stageReveal(stage: stage, threshold: 4)
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 32)
    }

    private func hasDescription(_ result: AnalysisResult) -> Bool {
        !result.imageContext.isEmpty && result.imageContext != result.imageSummary
    }

    private func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = Int(seconds)
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    // MARK: - Pattern pills (glass on iOS 26+, material fallback)

    @ViewBuilder
    private func patternPillsGrid(_ patterns: [PatternTag]) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(Array(patterns.enumerated()), id: \.element.name) { index, pattern in
                patternPill(pattern: pattern, index: index)
            }
        }
    }

    @ViewBuilder
    private func patternPill(pattern: PatternTag, index: Int) -> some View {
        let base = Text(pattern.name)
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)

        if #available(iOS 26.0, *) {
            base
                .environment(\.colorScheme, .dark)
                .glassEffect(.regular.interactive(), in: .capsule)
                .contentShape(Rectangle())
                .accessibilityHint("Double tap to search for this pattern")
                .onTapGesture {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onSearchPattern?(pattern.name)
                }
                .opacity(stage >= 2 ? 1 : 0)
                .offset(y: stage >= 2 ? 0 : MetadataReveal.slideDistance)
                .animation(
                    UIAccessibility.isReduceMotionEnabled
                        ? SnapSpring.resolvedMetadata
                        : SnapSpring.resolvedMetadata.delay(Double(index) * MetadataReveal.tagStagger),
                    value: stage
                )
        } else {
            base
                .background(.ultraThinMaterial, in: Capsule())
                .environment(\.colorScheme, .dark)
                .contentShape(Rectangle())
                .accessibilityHint("Double tap to search for this pattern")
                .onTapGesture {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onSearchPattern?(pattern.name)
                }
                .opacity(stage >= 2 ? 1 : 0)
                .offset(y: stage >= 2 ? 0 : MetadataReveal.slideDistance)
                .animation(
                    UIAccessibility.isReduceMotionEnabled
                        ? SnapSpring.resolvedMetadata
                        : SnapSpring.resolvedMetadata.delay(Double(index) * MetadataReveal.tagStagger),
                    value: stage
                )
        }
    }
}

// MARK: - Source Link Button

struct SourceLinkButton: View {
    let url: URL
    @Environment(\.openURL) private var openURL

    private var label: String {
        if let host = url.host?.lowercased(),
           host.contains("x.com") || host.contains("twitter.com") {
            return "View on X"
        }
        return "View source"
    }

    private var iconName: String {
        if let host = url.host?.lowercased(),
           host.contains("x.com") || host.contains("twitter.com") {
            return "arrow.up.right.square"
        }
        return "link"
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: iconName)
                .font(.system(size: 11))
            Text(label)
                .font(.system(size: 13))
        }
        .foregroundStyle(.white.opacity(0.35))
        .contentShape(Rectangle())
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            openURL(url)
        }
        .accessibilityLabel("View original post on X")
        .accessibilityAddTraits(.isLink)
    }
}
