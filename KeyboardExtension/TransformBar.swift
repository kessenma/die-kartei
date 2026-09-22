import SwiftUI

/// The strip above the keys: the two verbs, who you're writing to, and what just happened.
///
/// It stays one row tall in its resting state so the keys keep their full height. Status replaces
/// the row only while something is happening, then fades back.
struct TransformBar: View {

    @ObservedObject var writer: GermanWriter
    @Binding var address: GermanWriter.Address

    /// Nil while idle. Set to what the transform acted on, so the user can see whether it took
    /// their selection or the text they typed before committing to the result.
    let status: String?
    let isError: Bool

    let onRun: (GermanWriter.Job) -> Void
    let onUndo: (() -> Void)?
    let onDiagnostics: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            if let status {
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(isError ? Color.red : Color.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }

            HStack(spacing: 6) {
                ForEach(GermanWriter.Job.allCases) { job in
                    JobButton(job: job, onRun: onRun)
                        .disabled(writer.isWorking)
                }

                Picker("Anrede", selection: $address) {
                    ForEach(GermanWriter.Address.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 88)
                .disabled(writer.isWorking)

                if let onUndo {
                    Button(action: onUndo) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 15))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .disabled(writer.isWorking)
                }

                if KeyboardDiagnostics.isAvailable {
                    Button(action: onDiagnostics) {
                        Image(systemName: "stethoscope")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 34)
                    }
                    .buttonStyle(.plain)
                }
            }
            .opacity(writer.isWorking ? 0.5 : 1)
            .overlay {
                if writer.isWorking {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
        .animation(.easeInOut(duration: 0.15), value: status)
    }
}

/// Split out of `TransformBar` purely so the type checker can cope — inline, the label plus its
/// modifiers plus the two conditional colours blew past the expression time limit.
private struct JobButton: View {
    let job: GermanWriter.Job
    let onRun: (GermanWriter.Job) -> Void

    private var isPrimary: Bool { job == .translate }

    var body: some View {
        Button { onRun(job) } label: {
            Label(job.title, systemImage: job.symbol)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(background)
                .foregroundStyle(isPrimary ? Color.white : Color.accentColor)
        }
        .buttonStyle(.plain)
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.accentColor.opacity(isPrimary ? 1 : 0.15))
    }
}
