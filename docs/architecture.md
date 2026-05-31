# AIBrain Architecture

## Core Principle

**LLM is the brain, code is the pipeline.** Code does not make decisions for the LLM. No regex, no keyword matching, no heuristics.

## Two-Tier Architecture

### Tier 1: Instant Chat (no Run)

```
User message → Session.append → LLM responds → Session.append(response)
```

- Q&A, chat, explanations
- Simple tool calls: search, read file, calculation
- LLM judges it can complete within the current window
- No Run record, no Steps, no Events, no Artifacts
- Messages only in Session history (conversation.jsonl)

### Tier 2: Run Execution (has Run)

```
User message → Session.append → LLM creates Run → async execution → artifacts → Session.append(result)
```

- Multi-step task chains (code → test → debug)
- Deliverables (report, file, code)
- Long-running tasks (data collection, monitoring)

Run lifecycle: `pending → running → completed / failed / cancelled`

No `suspended`, no `waiting_approval`, no `completed_with_warnings`.
Approval pauses the engine loop internally — Run stays `running`.

## Session is Single Source of Truth

- All conversation in Session history (conversation.jsonl)
- One Session → zero or more Runs
- Run input from Session history, output back to Session history

## Decision Rights Belong to the LLM

LLM decides when to create a Run, which tools to use, and when to finish.
System prompt provides guidance. Code provides tools.

## Tool Approval Flow

```
LLM calls tool → Permissions.Policy.authorize
  ├─ allow → execute → result → continue
  └─ needs_approval → Interaction (pending)
       → Proxy claims (pending → proxy_running)
       → Proxy LLM evaluates → approve / deny / escalate
```

Run stays `running`. Engine process blocks on `receive` waiting for interaction resolution.

## Proxy Modes

**Assist**: Proxy evaluates, escalates uncertain cases to human.
**Autonomy**: Proxy decides everything. No escalation.

Control via `proxy_control` tool:
- `enable` — assist mode
- `disable` — all approvals go to human
- `autonomy` — full autonomy, sleep mode
- `assist` — back from autonomy

## Recovery

- Running runs → rebuild from messages.jsonl → continue
- Pending runs → mark failed (never started)
- Blocked processes re-subscribe to Bus events

## Removed Modules

| Module | Reason |
|--------|--------|
| RunPolicy | Regex guessing mode and step limits |
| RequestUnderstanding | Regex guessing intent |
| ContextPlan | Guesses on guesses |
| ContextAssembler | Token bloat |
| CapabilityCheck | Pre-check is unnecessary |
| VerificationRunner | Post-hoc judgment |
| CompletionRecord | Redundant metadata |
| EvidenceRecorder | Duplicates Steps |
| GoalController / ProjectController | Dead code |
