# Sift

**Stop cross-referencing. Start deciding.**

Sift is an agentic case-file assistant built in [Jac](https://github.com/jaseci-labs/jaseci) for JacHacks SF 2026. It ingests an insurance claim's fragmented sources (policy documents, claim forms, call/inspection notes), builds a graph of the facts they contain, and cross-references them for a specific claim -- catching contradictions between sources before an adjuster acts on them, instead of silently picking one side.

## The problem

A claims adjuster reviewing an incoming claim has to manually cross-reference the policy, the claim form, and call/inspection notes -- often written by different people at different times. When those sources disagree (e.g. the customer says a pipe burst suddenly, the inspector's own notes suggest gradual seepage instead, which changes what's covered), the adjuster either guesses or has to go track someone down to confirm. Sift automates the cross-referencing and flags the disagreement instead of quietly resolving it -- and drafts the follow-up question, but never sends anything without a human approving it first.

## How it's built -- entirely in Jac

The whole application, frontend included, is written in Jac using its full-stack `cl {}` pathway (`jac create --kind fullstack`) -- there is no separate frontend framework or hand-written REST client.

- **`endpoints.sv.jac`** -- the backend: `Source`/`Fact`/`Claim` nodes and edges form the graph. `IngestFixtures` extracts facts from raw documents via `by llm()` (byLLM), with a deterministic (non-LLM) substring check rejecting any extraction that isn't a verbatim quote from the source -- so citations can never be hallucinated. `ClaimReview` is the core walker: it traverses the graph from a `Claim` node to its linked facts and the global policy facts, runs a holistic `by llm()` conflict analysis across all of them, and then a second `by llm()` call chooses an action (`answer` / `flag_conflict` / `escalate`) -- genuinely agentic decision-making inside the walker, not a single wrapper call around a chat model.
- **`frontend.cl.jac` / `frontend.impl.jac`** -- the client: a `cl {}` component (compiles to a real React/JSX bundle) that calls backend walkers directly (`root spawn ClaimReview(...)`) via the compiler-generated RPC layer. Landing page -> case-file dashboard -> review screen with a **live SVG graph** of the claim/source/fact traversal (pulsing orange on the disputed facts), an agent-trace panel, click-to-verify citations (highlighting the exact quoted span in the raw source), and a drafted follow-up message that requires an explicit "Approve & Send" -- never sent automatically.

## Design research

The core design choices (citations must be verifiable, drafts must never auto-send) were validated with a small Cookiy AI synthetic-interview study (12 interviews, ~$3.50) before writing any code. See `docs/superpowers/specs/2026-07-26-company-brain-insurance-design.md` for the full design spec and rationale.

## Running it

```
jac create --kind fullstack   # (already scaffolded in sift/)
cd sift
jac start --dev
```

Requires an LLM backend configured in `jac.toml` (`OPENAI_API_KEY` env var for the default `gpt-4o-mini`, or a local Ollama model).
