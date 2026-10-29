# Code standards

1. Keep it simple, do not overcomplicate.
2. Comments only when necessary.
3. Be concise: a short README and no emojis.
4. IMPORTANT: avoid overly defensive code. Handle exceptions only when necessary.
5. Use uv: ALWAYS `uv run`, NEVER `python3`.
6. TypeScript: strict mode, never `any`.
7. Swift: Swift 6 language mode with complete strict concurrency.
   - Never `!`, `try!` or `as!` outside tests. Use `guard let`, `if let` or `??`.
   - Prefer `let`, `struct` and `enum`. Mark classes `final`. Keep members `private` unless something else needs them.
   - Use `async`/`await`, actors and `@MainActor` for UI code, not GCD queues or locks. The exception is the real-time audio thread, which must not allocate, lock or await.
   - Never `@unchecked Sendable` or `nonisolated(unsafe)` to silence the compiler. If one is truly needed, add a comment saying why it is safe.
   - Use `@Observable` for new state, not `ObservableObject`.
   - Use `throws` for errors that a caller can recover from, not optional returns or `fatalError`.
