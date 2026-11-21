//
//  WritingDiff.swift
//  german-ai-flashcards
//
//  A word-level diff between what the learner wrote and the tutor's correction, for showing a fix
//  (struck words out, new words in) and for the rewrite gate: a correction that replaces most of
//  a sentence is the tutor rewriting, not correcting, and the check treats it as unsure.
//

import Foundation

nonisolated enum WritingDiff {

    enum Kind: Hashable { case same, removed, inserted }

    struct Token: Hashable, Identifiable {
        let id: Int
        let text: String
        let kind: Kind
    }

    /// Whitespace-separated tokens, punctuation left attached to its word.
    static func tokens(_ s: String) -> [String] {
        s.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// The two sentences as one sequence: shared words once, removed words from `a`, inserted
    /// words from `b`, in reading order.
    static func diff(_ a: String, _ b: String) -> [Token] {
        let x = tokens(a), y = tokens(b)
        var id = 0
        return alignment(x, y).map { step in
            defer { id += 1 }
            switch step {
            case .same(let i, _):  return Token(id: id, text: x[i], kind: .same)
            case .removed(let i):  return Token(id: id, text: x[i], kind: .removed)
            case .inserted(let j): return Token(id: id, text: y[j], kind: .inserted)
            }
        }
    }

    /// One step of a word alignment, by index into the two token lists.
    enum Step: Hashable {
        case same(Int, Int)
        case removed(Int)
        case inserted(Int)
    }

    /// The longest-common-subsequence alignment of two token lists, compared through `key`
    /// (identity by default). Diktat aligns on a folded key so a missed capital or umlaut still
    /// lines up with its word; `diff` uses the plain one.
    static func alignment(_ x: [String], _ y: [String], key: (String) -> String = { $0 }) -> [Step] {
        let n = x.count, m = y.count
        guard n > 0 || m > 0 else { return [] }
        let kx = x.map(key), ky = y.map(key)
        var table = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                table[i][j] = kx[i] == ky[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var out: [Step] = []
        var i = 0, j = 0
        while i < n, j < m {
            if kx[i] == ky[j] {
                out.append(.same(i, j)); i += 1; j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                out.append(.removed(i)); i += 1
            } else {
                out.append(.inserted(j)); j += 1
            }
        }
        while i < n { out.append(.removed(i)); i += 1 }
        while j < m { out.append(.inserted(j)); j += 1 }
        return out
    }

    /// How much of either sentence the other does not share: the larger of the removed share
    /// of `a` and the inserted share of `b`. 0 for identical sentences, 1 for nothing in common.
    static func changedRatio(_ a: String, _ b: String) -> Double {
        let x = tokens(a).count, y = tokens(b).count
        guard x > 0, y > 0 else { return x == y ? 0 : 1 }
        let d = diff(a, b)
        let removed = d.filter { $0.kind == .removed }.count
        let inserted = d.filter { $0.kind == .inserted }.count
        return max(Double(removed) / Double(x), Double(inserted) / Double(y))
    }

    /// The pair of words a one-word fix swaps, when the correction changes exactly one word in
    /// place (a Dativ ending, an article, a spelling). Nil for anything else.
    static func singleSwap(_ a: String, _ b: String) -> (wrong: String, right: String)? {
        let x = tokens(a), y = tokens(b)
        guard x.count == y.count else { return nil }
        let differing = zip(x, y).enumerated().filter { $0.element.0 != $0.element.1 }
        guard differing.count == 1, let only = differing.first else { return nil }
        return (wrong: only.element.0, right: only.element.1)
    }
}
