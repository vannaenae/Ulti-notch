# Technical debt

Running list. Each item: what, why it's debt, when to pay it.

| # | Item | Why it matters | Pay by |
|---|---|---|---|
| TD1 | No local compile in the agent environment; code verified by CI only | Slower feedback; a CI failure is the first signal | Ongoing — you running `swift test` locally closes the gap |
| TD2 | `ModuleHost.setEnabled` coalesces rapid toggles; a toggle request that arrives mid-transition returns before the final state is applied and can't report a later activation error | Settings UI needs the error to show it | Phase 1 Settings work: expose per-module status (`.starting`, `.active`, `.failed(Error)`) |
| TD3 | `ModuleLifecycle.deactivate()` also runs when `activate` throws part way; modules must be idempotent | Easy to get wrong | Phase 1: add a shared test helper every module test uses |
| TD4 | No "break through suppression" rule: a `.critical` activity (incoming call) can't currently unhide the island in a full-screen app | Calls and agent approvals in Phase 2–3 need it | Before Phase 2 calls module |
| TD5 | Layout defaults (`IslandLayout`) are guesses, not measured | Visual fit on real notches | Phase 1 shell: measure on hardware, record in `docs/testing` |
| TD6 | `ActivityBoard.resolve` sorts on every call (O(n log n)) | Irrelevant at < 20 activities; noted so nobody adds per-frame resolution | Only if profiling shows it |
