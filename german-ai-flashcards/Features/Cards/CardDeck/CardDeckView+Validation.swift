import SwiftUI

extension CardDeckView {

    var correctedCount: Int {
        localValidationResults.filter { $0.status.wasAutoCorrected }.count
    }

    var attentionCount: Int {
        localValidationResults.filter { $0.status.needsAttention }.count
    }

    /// The deck's dictionary-check result, in one line where possible.
    ///
    /// Leads with what's fine rather than what's wrong: corrections have already been applied
    /// by the time this renders, so they're reported as finished work, not as a to-do list.
    @ViewBuilder
    var validationSummary: some View {
        let verified = localValidationResults.filter { $0.isVerified }.count
        let hasDetail = correctedCount > 0 || attentionCount > 0

        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text("\(verified) of \(localValidationResults.count) checked against the dictionary")
                    .foregroundStyle(.secondary)

                Button {
                    showValidationInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            if hasDetail {
                Button {
                    showCorrectionSheet = true
                } label: {
                    HStack(spacing: 10) {
                        if correctedCount > 0 {
                            Label(
                                "\(correctedCount) article\(correctedCount == 1 ? "" : "s") corrected",
                                systemImage: "wand.and.sparkles"
                            )
                            .foregroundStyle(.blue)
                        }
                        if attentionCount > 0 {
                            Label(
                                "\(attentionCount) to check",
                                systemImage: "questionmark.circle"
                            )
                            .foregroundStyle(.orange)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .font(.caption)
        .multilineTextAlignment(.center)
    }
}
