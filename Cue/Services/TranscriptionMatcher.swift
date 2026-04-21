import Foundation

/// Maps recognized speech back to a position in the script.
/// Designed to tolerate improvisation, skipped lines, and mispronunciations
/// by using a rolling fuzzy lookahead match.
final class TranscriptionMatcher: ObservableObject {
    /// Index into `tokens` of the word the user most recently spoke.
    @Published private(set) var currentWordIndex: Int = 0
    /// Character offset in the original script of `currentWordIndex`.
    @Published private(set) var currentCharOffset: Int = 0
    /// Total words in the script.
    @Published private(set) var totalTokens: Int = 0

    /// Normalized script tokens (lowercased, stripped).
    private var tokens: [String] = []
    /// Parallel array: NSRange of each token in the original script string.
    private var tokenRanges: [NSRange] = []
    /// Raw script (for offset calculation).
    private var script: String = ""

    /// How far ahead in the script we scan for matches.
    private let lookAhead = 40
    /// Minimum per-word similarity (0..1) to accept a match.
    private let minWordSimilarity: Float = 0.65
    /// Minimum phrase similarity (average over matched window).
    private let minPhraseSimilarity: Float = 0.55
    /// How many recognized words to match as a group.
    private let phraseSize = 3

    /// Tracks how many recognized words we've already consumed, so we don't
    /// rematch the same recognized prefix on every partial result.
    private var lastRecognizedWordCount = 0

    func setScript(_ text: String) {
        script = text
        (tokens, tokenRanges) = Self.tokenize(text)
        totalTokens = tokens.count
        currentWordIndex = 0
        currentCharOffset = 0
        lastRecognizedWordCount = 0
        Logger.shared.log("TranscriptionMatcher.setScript — \(tokens.count) tokens")
    }

    func reset() {
        currentWordIndex = 0
        currentCharOffset = 0
        lastRecognizedWordCount = 0
    }

    /// Manually override the current position (e.g. user hit arrow keys).
    func setCurrentIndex(_ index: Int) {
        let clamped = max(0, min(tokens.count, index))
        currentWordIndex = clamped
        if clamped > 0, clamped - 1 < tokenRanges.count {
            currentCharOffset = tokenRanges[clamped - 1].location
        } else {
            currentCharOffset = 0
        }
    }

    /// Ingest the latest recognized text. Called with the full transcription
    /// so far each time (recognizer returns cumulative partials).
    func ingest(_ recognizedText: String) {
        guard !tokens.isEmpty else { return }
        let recognizedWords = Self.tokenizeSimple(recognizedText)

        // We only need to consider recent words we haven't already consumed.
        // Grab the last `phraseSize` words of the new portion, plus a bit of
        // overlap to make matching more robust.
        let newStart = max(0, recognizedWords.count - phraseSize - 2)
        guard newStart < recognizedWords.count else { return }
        let recent = Array(recognizedWords[newStart..<recognizedWords.count])

        // Only consider forward progress (never backtrack).
        let windowStart = currentWordIndex
        let windowEnd = min(tokens.count, windowStart + lookAhead)
        guard windowStart < windowEnd else { return }
        let window = Array(tokens[windowStart..<windowEnd])

        if let matchEndInWindow = Self.findBestPhraseMatch(
            recent: recent,
            window: window,
            phraseSize: phraseSize,
            minWordSim: minWordSimilarity,
            minPhraseSim: minPhraseSimilarity
        ) {
            let newIndex = windowStart + matchEndInWindow
            if newIndex > currentWordIndex {
                currentWordIndex = newIndex
                if newIndex - 1 < tokenRanges.count {
                    currentCharOffset = tokenRanges[newIndex - 1].location
                }
                lastRecognizedWordCount = recognizedWords.count
            }
        }
    }

    // MARK: - Static helpers

    static func tokenize(_ text: String) -> (tokens: [String], ranges: [NSRange]) {
        var tokens: [String] = []
        var ranges: [NSRange] = []
        let nsText = text as NSString
        let length = nsText.length
        var i = 0
        while i < length {
            // Skip whitespace / non-word.
            while i < length, !isWordChar(nsText.character(at: i)) {
                i += 1
            }
            let start = i
            while i < length, isWordChar(nsText.character(at: i)) {
                i += 1
            }
            if i > start {
                let range = NSRange(location: start, length: i - start)
                let raw = nsText.substring(with: range)
                tokens.append(raw.lowercased())
                ranges.append(range)
            }
        }
        return (tokens, ranges)
    }

    static func tokenizeSimple(_ text: String) -> [String] {
        text.lowercased()
            .split { !($0.isLetter || $0.isNumber || $0 == "'") }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func isWordChar(_ c: unichar) -> Bool {
        let scalar = Unicode.Scalar(c)
        guard let s = scalar else { return false }
        return CharacterSet.letters.contains(s) ||
               CharacterSet.decimalDigits.contains(s) ||
               s == "'"
    }

    /// Find the best position in `window` where the last words of `recent` match.
    /// Returns the index ONE PAST the last matched word in `window` (i.e. the
    /// new position to advance to), or nil if no good match.
    static func findBestPhraseMatch(
        recent: [String],
        window: [String],
        phraseSize: Int,
        minWordSim: Float,
        minPhraseSim: Float
    ) -> Int? {
        guard !recent.isEmpty, !window.isEmpty else { return nil }

        // Use up to the last `phraseSize` recent words as the needle.
        let needle = Array(recent.suffix(phraseSize))
        let needleLen = needle.count

        var bestScore: Float = 0
        var bestEndIndex: Int? = nil

        // Slide the needle across the window; for short needles (e.g. 1-2 words
        // because recognition just started) we still allow single-word matching.
        for windowStart in 0..<window.count {
            let end = min(window.count, windowStart + needleLen)
            let slice = Array(window[windowStart..<end])
            guard slice.count == needle.count else { continue }

            // Compute per-word similarities; reject if any single word is poor.
            var sum: Float = 0
            var allGood = true
            for i in 0..<needleLen {
                let sim = similarity(needle[i], slice[i])
                if sim < minWordSim {
                    allGood = false
                    break
                }
                sum += sim
            }
            guard allGood else { continue }
            let avg = sum / Float(needleLen)
            if avg > bestScore {
                bestScore = avg
                bestEndIndex = windowStart + needleLen
            }
        }

        guard let idx = bestEndIndex, bestScore >= minPhraseSim else { return nil }
        return idx
    }

    /// Normalized similarity 0..1 (1 = identical). Levenshtein-based.
    static func similarity(_ a: String, _ b: String) -> Float {
        if a == b { return 1 }
        let maxLen = max(a.count, b.count)
        if maxLen == 0 { return 1 }
        let dist = Self.editDistance(a, b)
        return max(0, 1 - Float(dist) / Float(maxLen))
    }

    static func editDistance(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        if aChars.isEmpty { return bChars.count }
        if bChars.isEmpty { return aChars.count }
        var prev = Array(0...bChars.count)
        var curr = Array(repeating: 0, count: bChars.count + 1)
        for i in 1...aChars.count {
            curr[0] = i
            for j in 1...bChars.count {
                if aChars[i - 1] == bChars[j - 1] {
                    curr[j] = prev[j - 1]
                } else {
                    curr[j] = 1 + min(prev[j], curr[j - 1], prev[j - 1])
                }
            }
            swap(&prev, &curr)
        }
        return prev[bChars.count]
    }
}
