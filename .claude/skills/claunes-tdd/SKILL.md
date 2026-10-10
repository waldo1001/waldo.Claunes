---
name: claunes-tdd
description: Test-driven change in waldo.Claunes (Swift) - Red, Green, Mutate, then full suite, app build and commit. Use for any feature, bug fix or behaviour change in this repo, and whenever the user says TDD, "with tests", "test first", "fix this bug", "implement". This replaces iFacto.SDD here; iFacto.SDD is for AL/Business Central only.
---

# TDD in waldo.Claunes

Every behaviour change goes through these phases in order. Do not skip one, and report each
phase's evidence (the command and the pass/fail lines) before moving to the next.

## 0. Locate
- Read `CLAUDE.md` and, for anything touching bundles, launching or signing, `SPIKE.md`.
- Logic belongs in `Sources/ClaunesCore` (testable). `ClaunesApp` (SwiftUI) and the
  executables stay thin: if the change needs logic there, put the logic in the core and test it.
- Pick the test file: `Tests/ClaunesCoreTests/BundleBuilderTests.swift` (bundle, drift, migration,
  icons; has the fake Claude.app fixture in `setUpWithError`) or `ProfileStoreTests.swift`
  (model, store, paths). New area -> new `*Tests.swift`; if it needs the fake Claude.app, move
  that fixture into a shared helper first instead of copying it.

## 1. Red
- Write the smallest test that states the new behaviour. Name: `test<Behaviour>`.
- Run only it: `swift test --filter ClaunesCoreTests.<Class>/<testName>`
- It must FAIL, and for the right reason (assertion, not a compile error in unrelated code).
  A test that passes before the change proves nothing: rewrite it.

## 2. Green
- Minimum production code to pass. Re-run the filtered test until green.
- Then `swift test` (full suite) - everything green.

## 3. Mutate
- Prove the test guards the behaviour: temporarily break the new code (flip a condition,
  return early, drop the line) and run the filtered test. It must fail.
- Restore the code exactly (`git diff` must show only the intended change) and re-run green.
- If the mutant survives, the test is too weak: strengthen it and repeat.

## 4. Verify the product
- `swift build` (all targets, catches UI/CLI breakage the tests do not cover).
- `scripts/build-app.sh release` if the change touches the app, launcher, CLI or bundle layout.
- Manual smoke only with Claunes named `Test-*` via `.build/debug/claunes`, deleted afterwards;
  if one was launched, restore the handler: `.build/debug/claunes handler com.anthropic.claudefordesktop`.

## 5. Commit
- One commit per behaviour, message says what changed and why. Push to `main` (CI runs
  build + tests; check it with `gh run list -R waldo1001/waldo.Claunes -L 1`).
- Shipping to users is a separate step: the `claunes-release` skill.

## Hard rules (from CLAUDE.md)
- Tests use temp dirs and the fake Claude.app only. Never `/Applications/Claude.app`,
  never `~/Library/Application Support/Claude`, never the real `~/Applications/Claunes`.
- No hard deletes outside test temp dirs; no network calls in product code.
