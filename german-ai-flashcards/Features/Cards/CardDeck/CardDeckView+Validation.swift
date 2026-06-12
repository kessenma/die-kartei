import SwiftUI

extension CardDeckView {

    @ViewBuilder
    var validationSummary: some View {
        let verified = localValidationResults.filter { $0.isVerified }.count
        let genderIssues = localValidationResults.filter {
            if case .genderMismatch = $0.status { return true }
            return false
        }.count
        let notFound = localValidationResults.filter { $0.status == .notFound }.count

        VStack(spacing: 4) {
            HStack(spacing: 8) {
                VStack(spacing: 4) {
                    if verified > 0 {
                        Label("\(verified) verified", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }
                    if genderIssues > 0 {
                        Label("\(genderIssues) gender issue\(genderIssues == 1 ? "" : "s")", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    if notFound > 0 {
                        Label("\(notFound) not in dictionary", systemImage: "questionmark.circle")
                            .foregroundStyle(.secondary)
                    }
                }

                if genderIssues > 0 || notFound > 0 {
                    Button {
                        showValidationInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .font(.caption)
    }
}
