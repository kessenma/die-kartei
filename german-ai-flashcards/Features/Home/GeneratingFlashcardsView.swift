import SwiftUI

struct GeneratingFlashcardsView: View {
    var progress: Double
    var cardsGenerated: Int
    var cardsRequested: Int
    var isValidating: Bool
    var topic: String
    var startTime: Date
    var generatedWords: [String] = []
    var streamingTokenCount: Int = 0
    var currentBatchSize: Int = 0
    var currentBatchIndex: Int = 0
    var onStop: (() -> Void)? = nil

    private var tokenFill: Double {
        guard currentBatchSize > 0, progress < 1.0 else { return 0 }
        let estimatedTokensPerBatch = max(currentBatchSize * 180, 100)
        return min(Double(streamingTokenCount) / Double(estimatedTokensPerBatch), 0.95)
    }

    private var smoothedProgress: Double {
        guard currentBatchSize > 0 else { return progress }
        if progress >= 1.0 { return 1.0 }
        let numBatches = max((cardsRequested + currentBatchSize - 1) / currentBatchSize, 1)
        let batchStep = 0.95 / Double(numBatches)
        return min(progress + tokenFill * batchStep, 0.99)
    }

    private var estimatedCardsInProgress: Int {
        guard currentBatchSize > 0, cardsGenerated < cardsRequested else { return cardsGenerated }
        let partial = Int((tokenFill * Double(currentBatchSize)).rounded())
        return min(cardsGenerated + partial, cardsRequested)
    }

    private var totalBatches: Int {
        guard currentBatchSize > 0 else { return 1 }
        return (cardsRequested + currentBatchSize - 1) / currentBatchSize
    }

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .opacity(0.95)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                AnimatedCardStack()
                    .frame(height: 200)

                Text("Generating Flashcards")
                    .font(.title3)
                    .fontWeight(.semibold)

                VStack(spacing: 8) {
                    ProgressView(value: smoothedProgress)
                        .tint(.accentColor)
                        .frame(maxWidth: 240)
                        .animation(.linear(duration: 0.3), value: smoothedProgress)

                    HStack(spacing: 12) {
                        Text("\(estimatedCardsInProgress) of \(cardsRequested) cards")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        TimelineView(.periodic(from: startTime, by: 1)) { _ in
                            Text(elapsedString(since: startTime))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }

                // Batch dots — one per chunk, fills with token progress while active
                if totalBatches > 1 {
                    HStack(spacing: 10) {
                        ForEach(0..<totalBatches, id: \.self) { i in
                            batchDot(at: i)
                        }
                    }
                }

                if !generatedWords.isEmpty {
                    Text(generatedWords.joined(separator: "  ·  "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                        .animation(.easeInOut(duration: 0.4), value: generatedWords.count)
                }

                if isValidating {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Validating against dictionary…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if generatedWords.isEmpty {
                    Text(topic)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if let onStop, !isValidating {
                    Button(role: .destructive, action: onStop) {
                        Label("Stop & Keep Cards", systemImage: "stop.circle")
                            .font(.subheadline)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    @ViewBuilder
    private func batchDot(at index: Int) -> some View {
        if index < currentBatchIndex {
            // Completed batch — solid filled circle
            Circle()
                .fill(Color.accentColor)
                .frame(width: 10, height: 10)
        } else if index == currentBatchIndex {
            // Active batch — arc fills as tokens stream in
            ZStack {
                Circle()
                    .stroke(Color.accentColor.opacity(0.2), lineWidth: 2)
                    .frame(width: 12, height: 12)
                Circle()
                    .trim(from: 0, to: tokenFill)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 12, height: 12)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.3), value: tokenFill)
            }
        } else {
            // Pending batch — outline only
            Circle()
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1.5)
                .frame(width: 10, height: 10)
        }
    }

    private func elapsedString(since start: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(start)))
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m \(seconds % 60)s"
    }
}

// MARK: - Animated card stack

private struct AnimatedCardStack: View {
    @Environment(\.colorScheme) private var colorScheme

    @State private var isFlipped = false
    @State private var currentCardIndex = 0

    private var cardColor: Color {
        colorScheme == .dark
            ? Color(red: 0.18, green: 0.18, blue: 0.20)
            : Color(red: 0.98, green: 0.96, blue: 0.93)
    }
    private var lineColor: Color {
        colorScheme == .dark
            ? Color(red: 0.35, green: 0.38, blue: 0.45).opacity(0.3)
            : Color(red: 0.78, green: 0.82, blue: 0.90).opacity(0.4)
    }
    private var redRuleColor: Color {
        colorScheme == .dark
            ? Color(red: 0.70, green: 0.30, blue: 0.30).opacity(0.4)
            : Color(red: 0.85, green: 0.35, blue: 0.35).opacity(0.5)
    }
    private var borderColor: Color {
        Color.gray.opacity(colorScheme == .dark ? 0.5 : 0.3)
    }

    var body: some View {
        ZStack {
            // Background stacked cards for depth
            blankCard
                .frame(width: 220, height: 150)
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                .offset(x: 6, y: 6)
                .rotationEffect(.degrees(3))

            blankCard
                .frame(width: 220, height: 150)
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                .offset(x: -4, y: 4)
                .rotationEffect(.degrees(-2))

            // Main flipping card
            blankCard
                .frame(width: 220, height: 150)
                .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
                .rotation3DEffect(
                    .degrees(isFlipped ? 180 : 0),
                    axis: (x: 0, y: 1, z: 0)
                )
                .id(currentCardIndex)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.9).combined(with: .opacity),
                    removal: .scale(scale: 1.05).combined(with: .opacity)
                ))
        }
        .onAppear { startAnimation() }
    }

    private var blankCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(cardColor)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(borderColor, lineWidth: 1)

            // Ruled lines to match FlashCardView style
            VStack(spacing: 0) {
                Rectangle()
                    .fill(redRuleColor)
                    .frame(height: 1)
                    .padding(.top, 36)
                Spacer()
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(spacing: 16) {
                ForEach(0..<3, id: \.self) { _ in
                    Rectangle()
                        .fill(lineColor)
                        .frame(height: 0.5)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 42)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { _ in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                isFlipped.toggle()
            }

            // After each full flip cycle (back to front), swap to a "new" card
            if isFlipped == false {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    currentCardIndex += 1
                }
            }
        }
    }
}
