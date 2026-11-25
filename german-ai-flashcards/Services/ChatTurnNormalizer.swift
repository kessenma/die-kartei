import Foundation

/// Shapes a conversation's turns into the sequence a chat template will actually accept.
///
/// Most templates — Gemma's above all — don't merely prefer strict `user`/`assistant` alternation,
/// they enforce it:
///
/// ```jinja
/// {% if (message['role'] == 'user') != (loop.index0 % 2 == 0) %}
///   {{ raise_exception('Conversation roles must alternate user/assistant/...') }}
/// {% endif %}
/// ```
///
/// A raised exception aborts rendering and reaches the learner as the opaque
/// "The operation couldn't be completed. (Jinja.TemplateException error 1.)" — a dead end with no
/// reply and nothing to act on. And a real conversation produces violations constantly:
///
/// * the AI speaks first, so the history starts on `assistant`;
/// * a reply never lands (a crash, a memory eviction, a stalled decode) and the learner sends
///   again, so two `user` turns sit back to back;
/// * a trailing window (`suffix(12)`) cuts the history at an assistant turn;
/// * an empty transcription leaves a blank turn, which some templates also reject.
///
/// Rather than trusting every call site to avoid all of that, every chat prompt goes through here.
/// The result is guaranteed to be non-empty, free of blank content, strictly alternating, starting
/// on `user` and ending on `user` — the one shape `add_generation_prompt` is valid after.
enum ChatTurnNormalizer {
    typealias Turn = (role: ChatRole, content: String)

    /// A user turn appended when the history ends on the AI — "keep going", in the chat's own
    /// language, so the model reads it as conversation rather than as an instruction in English.
    static let continuationSeed = "Mach bitte weiter."

    /// Normalize `turns` into a strictly alternating user/assistant sequence.
    ///
    /// - Parameters:
    ///   - turns: The conversation so far, oldest first. Blank turns are dropped; consecutive
    ///     same-role turns are merged into one (a learner who sent twice reads as one longer turn,
    ///     which is also what they meant); `system` turns inside the history are folded in as user
    ///     text, since the real system prompt travels separately and most templates have no system
    ///     role at all.
    ///   - openerSeed: The user turn to stand in front of a history that starts on the AI — the
    ///     line that elicited the opener in the first place.
    static func normalized(_ turns: [Turn], openerSeed: String) -> [Turn] {
        var merged: [Turn] = []
        for turn in turns {
            let content = turn.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { continue }
            // Alternation is a two-role question, so a stray system turn has to pick a side. It's
            // an instruction, which is the user's side of a chat.
            let role: ChatRole = turn.role == .assistant ? .assistant : .user
            if let last = merged.last, last.role == role {
                merged[merged.count - 1].content = last.content + "\n\n" + content
            } else {
                merged.append((role: role, content: content))
            }
        }

        let seed = openerSeed.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackSeed = seed.isEmpty ? continuationSeed : seed

        guard !merged.isEmpty else { return [(role: .user, content: fallbackSeed)] }
        if merged[0].role == .assistant {
            merged.insert((role: .user, content: fallbackSeed), at: 0)
        }
        if merged[merged.count - 1].role == .assistant {
            merged.append((role: .user, content: continuationSeed))
        }
        return merged
    }

    /// The last-resort prompt: the whole exchange rendered as one user turn.
    ///
    /// Used only when a template rejects even the normalized sequence — an unfamiliar template with
    /// a rule we haven't met. A single user message is the one shape every chat template accepts,
    /// so this always renders. The reply is worse than a properly templated one (the model loses
    /// its own turn markers), but a worse reply beats no reply and an error the learner can't read.
    static func flattened(_ turns: [Turn], openerSeed: String) -> String {
        let normalized = normalized(turns, openerSeed: openerSeed)
        // Everything but the final user turn becomes labelled transcript; the final turn stays the
        // live thing being answered, so the model responds to it rather than summarizing.
        let transcript = normalized.dropLast().map { turn in
            (turn.role == .assistant ? "Du: " : "Ich: ") + turn.content
        }.joined(separator: "\n")
        guard let last = normalized.last else { return "" }
        guard !transcript.isEmpty else { return last.content }
        return "Bisheriges Gespräch:\n\(transcript)\n\nIch: \(last.content)\n\nDu:"
    }
}
