# CLAUDE.md

@AGENTS.md

`AGENTS.md` is the shared source of agent instructions. Follow its task-specific reading table; load only the domain references needed for the current task.

Review and release bundling is the default workflow (see the section of that name in `AGENTS.md`): no separate review and re-review per change. Branches deliver their own evidence; a set of ready branches gets one combined final review, one fix round, and one TestFlight build for the whole bundle.
