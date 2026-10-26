//
//  StarterSourceSetup.swift
//  Aidoku
//

enum StarterSourceSetup {
    /// Records only successful installations, including sources already present.
    /// Keeping completion separate from installation preserves later user removals.
    static func run(
        keys: [String],
        completed: Set<String>,
        missingSourceKeys: (Set<String>) async -> Set<String>,
        installSources: (Set<String>) async -> AsyncStream<String>?,
        onCompletion: (String) async -> Void
    ) async {
        let pending = Set(keys).subtracting(completed)
        guard !pending.isEmpty else { return }

        let missing = await missingSourceKeys(pending)
        for key in keys where pending.contains(key) && !missing.contains(key) {
            await onCompletion(key)
        }

        guard !missing.isEmpty, let stream = await installSources(missing) else { return }
        for await key in stream where missing.contains(key) {
            await onCompletion(key)
        }
    }
}
