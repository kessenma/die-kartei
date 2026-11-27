import Foundation

// A real file in the core, not a link to the app: iOS's MLX renders each model's Jinja template
// itself. llama.cpp on Android has no Jinja engine, so the app writes the two tutor families'
// formats out here. `ChatPromptFormatTests` checks them byte for byte against the real
// templates (training/scripts/render_chat_fixtures.py), so the phone sends what was evaluated.

/// How a tutor model wants its conversation written out.
enum ChatPromptFormat: String, CaseIterable {
    case gemma4
    case granite

    init(_ model: MLXModel) {
        switch model {
        case .granite2B_german, .granite41_3B_german: self = .granite
        default: self = .gemma4
        }
    }

    /// The prompt for `messages`, ending where the model starts its reply. No BOS token: the
    /// tokenizer adds it.
    func render(_ messages: [(role: ChatRole, content: String)]) -> String {
        var out = ""
        switch self {
        case .gemma4:
            // Gemma 4 trims each turn and calls the assistant "model".
            for m in messages {
                let role = m.role == .assistant ? "model" : m.role.rawValue
                out += "<|turn>\(role)\n\(m.content.trimmingCharacters(in: .whitespacesAndNewlines))<turn|>\n"
            }
            return out + "<|turn>model\n"
        case .granite:
            // Granite keeps the text as is.
            for m in messages {
                out += "<|start_of_role|>\(m.role.rawValue)<|end_of_role|>\(m.content)<|end_of_text|>\n"
            }
            return out + "<|start_of_role|>assistant<|end_of_role|>"
        }
    }

    /// Text that ends the model's turn, in case the runtime doesn't stop on it as a token.
    var endOfTurn: String {
        switch self {
        case .gemma4: "<turn|>"
        case .granite: "<|end_of_text|>"
        }
    }
}
