# Company Brain (Insurance Claims) — Design Spec

**Event:** JacHacks SF 2026 (Founders Inc., Fort Mason — Jul 26, 2026)
**Track:** Agentic AI
**Builder:** Solo, first time using Jac
**Timebox:** 10:45 AM – 7:15 PM hacking hours; partial submission checkpoint 5:50 PM; hard deadline 7:15 PM

## 1. Problem & Persona

**Persona:** An insurance claims adjuster/agent handling an incoming claim. They take calls, jot notes, and have to cross-reference the claim against policy documents that live in separate systems (policy PDFs, call notes, prior correspondence). When sources disagree, they either guess (risking a wrong claim decision) or manually chase down a colleague to confirm — both costly, and a wrong call has real financial/reputational consequences.

**Validated pain pattern** (from a Cookiy AI synthetic-interview study run on an adjacent persona — new hires reconciling fragmented internal docs — $3.50 spent, 12 interviews; findings transfer at the level of underlying trust requirements, not the literal persona):
- The costly moment isn't searching for information — it's **reconciling contradictions** between sources.
- Citations back to the source are **non-negotiable** for trust; users reject unsourced answers.
- Users want the agent to draft actions (emails, clarifications) but demand a **human-in-the-loop approval step** before anything is sent — no autonomous execution.

**This design's core bet:** the highest-value, most demoable moment is catching a conflict between the claim/call notes and the policy terms *before* the adjuster acts on it, not answering simple lookup questions.

## 2. Scope

**In scope:**
- Ingest 3 fabricated fixtures: a policy document (coverage terms + exclusions), a claim record, and call notes — with one deliberate coverage conflict planted between two sources.
- byLLM extraction of each source into graph nodes.
- A walker that traverses the graph, compares same-topic facts across sources, detects the planted conflict, and decides its next action (answer / flag conflict / draft response / escalate) via a `by llm()` decision step.
- A draft-response action (e.g., a clarification or claim-decision email) that requires explicit human approval before "sending" (sending is mocked — no real email integration).
- A minimal chat-style web UI hitting Jac's auto-generated `:pub` walker REST endpoints, plus an "agent trace" panel showing the walker's traversal/decision steps live.
- One brief, non-interactive note (a config file glance) demonstrating the same engine is domain-agnostic — not a built feature.

**Explicitly out of scope:**
- No domain/problem-picker wizard or onboarding flow.
- No real CRM/insurance-system/email integration — all data is fixture-based and local.
- No autonomous auto-send of any drafted action, ever.
- No multi-user auth, persistence beyond the demo session, or multi-tenant support.
- No coverage of verticals beyond insurance in the actual demo (mentioned verbally only).

## 3. Architecture

```
Fixtures (policy.md, claim.md, call_notes.md)
        │
        ▼
Ingestion: byLLM extracts (topic, statement, source_ref) per chunk
        │
        ▼
Graph:  Source nodes ──edge──> Fact nodes (topic, statement)
        Claim node ──edge──> relevant Fact nodes
        │
        ▼
Walker (ClaimReviewWalker), spawned on a claim query:
  1. visit Fact nodes matching the claim's topic(s)
  2. compare facts on the same topic across sources
  3. if conflict: mark conflict, else compose answer
  4. decide_action(by llm()) over [answer, flag_conflict, draft_response, escalate]
  5. report chosen action + supporting Fact nodes (with source_ref) to caller
        │
        ▼
:pub REST endpoint (jac start auto-generates this from the walker)
        │
        ▼
Web UI: chat pane (question/answer) + agent trace pane (traversal steps)
        + draft pane with Approve & Send / Edit buttons (send is mocked)
```

**Node/edge types:**
- `Source` — has `name`, `kind` (policy | claim | call_notes)
- `Fact` — has `topic`, `statement`; edge `From` back to its `Source`
- `Claim` — has `claim_id`, `description`; edges to relevant `Fact` nodes

**Key Jac mechanisms used** (confirmed against real docs via Firecrawl, not assumed):
- `node`/`edge` declarations, `++>` / `+>: Edge(...) :+>` to connect
- `walker` with `can ... with <NodeType> entry { ... }` abilities, `visit [-->]` to traverse (queued, BFS by default), `report` to collect results, `disengage` to stop early
- `by llm()` function delegation with `sem` annotations for extraction, relevance-checking, conflict comparison, and action selection
- `jac start` auto-exposing a `:pub` walker as a REST endpoint (no hand-rolled routing)

## 4. Demo Script (fits the rubric's 4-minute structure)

1. **Who/what breaks (≈45s):** "An adjuster gets a water-damage claim. The policy doc, the claim form, and the call notes were written by different people at different times — and they disagree."
2. **Live workflow (≈2min):** Ask the agent about the claim. Watch the agent trace show it visiting Fact nodes, comparing sources, detecting the conflict, and choosing to flag rather than answer. See the conflict surfaced with both citations. Ask it to draft a response; see the draft; click Approve & Send.
3. **Where Jac runs (≈45s):** Point at the walker file — the traversal/decision logic — and the `by llm()` calls doing extraction and action-selection. One-line mention: "same walker code, different config, and this runs on onboarding docs or CRM records instead — the engine doesn't know it's insurance."
4. **Close (≈30s):** Recap the value: no guessing on stale/conflicting info, nothing sent without a human approving it.

## 5. Rubric Alignment (self-check, not to be included in the demo)

- **Use of Jac (40%):** Central — byLLM extraction, graph traversal, and an explicit walker decision step, not a static RAG pipeline. Aim: score 5 by keeping the conflict-comparison logic genuinely inside the walker's traversal, not hidden in one LLM call.
- **Real-World Use Case (20%):** One named persona (the adjuster), one concrete claim scenario — not "insurance" as a market.
- **Technical Execution (20%):** Scope is deliberately narrow (3 fixtures, one conflict, one draft action) so the hard part — traversal + conflict detection + action selection — is fully working rather than half-built across more features.
- **Demo & Story (20%):** Entire flow is a live run against the walker's REST endpoint; agent trace panel makes the reasoning visible instead of a black-box chat bubble.

## 6. Risks / Open Items

- **Jac unfamiliarity:** builder has never written Jac before today. Mitigated by having real syntax reference cached locally (`scratchpad/jac_docs/`) from Firecrawl scrapes of docs.jaseci.org — no guessing at syntax during build.
- **LLM backend:** needs `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` set, or a local Ollama model configured in `jac.toml`. Decide which before implementation starts.
- **Time risk:** if the walker/graph core takes longer than expected, cut the agent-trace UI polish and the draft-response action first — the Q&A + conflict-detection core is the non-negotiable minimum for a credible demo.

## 7. Verification Before Submission

Manual check against the 3 fixtures before the 5:50 PM partial-submission checkpoint:
- Asking about the planted-conflict topic returns both sources with citations and is marked as a conflict, not silently resolved.
- Asking about a non-conflicting topic returns a direct cited answer.
- Requesting a draft produces a draft that is not auto-sent; Approve & Send is a distinct, deliberate step.
