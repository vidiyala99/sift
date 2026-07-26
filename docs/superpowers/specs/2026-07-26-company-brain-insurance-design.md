# Sift — Design Spec (Company Brain, Insurance Claims)

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
- Ingest fabricated fixtures across source *types* — policy doc, claim record, call notes, and framed as representative of email/Slack/meeting-notes ingestion generally — with one deliberate coverage conflict planted between two sources.
- byLLM extraction of each source into graph nodes, with a deterministic groundedness check (see §3a).
- A walker that traverses the graph, compares same-topic facts across sources, detects the planted conflict, and decides its next action (answer / flag conflict / draft response / escalate) via a `by llm()` decision step. This one deep reasoning chain is the entire technical bet — see §3b on why breadth was rejected.
- A draft-response action (e.g., a clarification email) that requires explicit human approval before "sending" (sending is mocked — no real email integration).
- Full UI flow (§4a): landing screen → dashboard (2-3 prioritized items) → review screen (live graph traversal + agent trace + click-to-verify source panel + draft/approve).

**Explicitly out of scope:**
- No domain/problem-picker wizard.
- No real login/signup — a single "Enter" action from the landing screen is enough; no auth logic.
- No real CRM/insurance-system/email/Slack/calendar integration, and no *separate* mocked action types (no working "send to Slack," "schedule call," "generate report" buttons) — one action type (draft-and-approve) built deep, not five built shallow. Source diversity (Slack/email/meeting-notes) is represented as **labels/icons on fixture data**, not as live integrations.
- No autonomous auto-send of any drafted action, ever.
- No multi-user auth, persistence beyond the demo session, or multi-tenant support.
- No coverage of verticals beyond insurance in the actual demo (mentioned verbally/visually only, via the domain-config aside in §4a).

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

## 3a. Citation Integrity (groundedness guarantee)

An ungrounded citation is worse than no citation — it defeats the product's entire premise. Mechanism:
1. Extraction `by llm()` is scoped narrowly: locate the relevant span in the source and label its topic. It does **not** paraphrase — the `statement` field is the verbatim excerpt.
2. A deterministic (non-LLM) substring check runs after extraction: confirm `statement` actually appears in the source text. Fails → re-extract or flag `unverified`. This check cannot hallucinate; it's a string match.
3. The UI renders the stored quote **directly** — never regenerated at answer/display time. The LLM only writes the narrative wrapper around the citation, never the citation text itself.
4. **Click-to-verify:** clicking a citation opens the raw source document with the exact matched span highlighted (deterministic string search + highlight, no LLM call).
5. The conflict *verdict* (an LLM judgment) is a hint; the two raw quotes shown side-by-side are the proof — a user can independently verify the conflict without trusting the verdict.

## 3b. Depth vs. Breadth (why one action type, not several)

Considered and rejected: a broader dashboard with distinct working action types (Slack, email, calendar, call, report). Rejected because each additional action type adds UI surface without adding walker reasoning — it's the same shallow branch repeated with a different label, not new traversal/decision logic. The rubric explicitly rewards depth ("the hard part genuinely done," central Use-of-Jac via walkers/graph traversal/byLLM/agentic flows) over breadth ("mostly scaffolding" scores a 1). One action type (draft-and-approve) sitting on top of a genuinely multi-step reasoning chain (traverse → compare → detect conflict → decide action) scores higher than five action types sitting on top of the same shallow logic. Source diversity (Slack/email/meeting notes) is preserved narratively via labels on fixture data, not via separate integrations.

## 4. Demo Script (fits the rubric's 4-minute structure)

1. **Who/what breaks (≈45s):** Landing screen: "Sift" + tagline. "An adjuster gets a water-damage claim. The policy doc, the claim form, and the call notes were written by different people at different times — and they disagree."
2. **Dashboard (≈15s):** Enter the dashboard — 2-3 cards, each a claim/item needing review, with source labels and a one-line reason. Click into the water-damage claim.
3. **Live workflow (≈2min):** Ask the agent about the claim. Watch the live graph panel light up as the walker visits Fact nodes and the agent trace shows comparing sources, detecting the conflict, and choosing to flag rather than answer. See the conflict surfaced with both citations; click one to verify against the highlighted source. Ask it to draft a response; see the draft; click Approve & Send.
4. **Where Jac runs (≈30s):** Point at the walker file — the traversal/decision logic — and the `by llm()` calls doing extraction and action-selection. One-line mention: "same walker code, different config, and this runs on onboarding docs or CRM records instead — the engine doesn't know it's insurance" (glance at the `domain_config.jac` aside).
5. **Close (≈15s):** Recap the value: no guessing on stale/conflicting info, nothing sent without a human approving it.

## 4a. UI Flow

1. **Landing** — product name "Sift", one-line tagline, single "Enter" action. No signup form.
2. **Dashboard** — 2-3 cards ranked by relevance, each showing a short reason and its source labels (icons for policy/claim/call-notes, styled to also represent email/Slack/meeting-notes narratively). Click a card to open Review.
3. **Review screen** — three-pane layout:
   - *Left:* live SVG graph — claim node → source nodes → fact nodes, with visited nodes highlighted as the walker traverses, and conflicting facts rendered as pulsing/connected nodes.
   - *Middle:* the question/answer, with the conflict explanation and clickable citations.
   - *Right:* source-verify panel — raw fixture text with the exact cited span highlighted; swaps content when a different citation is clicked.
   - *Below the answer:* draft pane with Approve & Send / Edit — send is mocked, clearly a deliberate distinct step.

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
