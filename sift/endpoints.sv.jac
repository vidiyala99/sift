"""Sift - Server-Side Case File Engine.

Sources (policy/claim/call-notes fixtures) are ingested once into a graph of
Source/Fact/Claim nodes. ClaimReview is the core walker: it traverses the
graph, cross-references facts on the same topic across sources, detects
contradictions, and decides what to do about it.
"""

import os;
import datetime;
import from byllm.lib { Model }

glob llm = Model(model_name="gpt-4o-mini");

# --- Data model -------------------------------------------------------

node Source {
    has name: str,
        kind: str,
        raw_text: str = "";
}

node Fact {
    has topic: str,
        statement: str,
        source_name: str,
        source_kind: str,
        sensitive: bool = False;
}

node Claim {
    has claim_id: str,
        description: str;
}

edge From {}

# --- Extraction (byLLM) ------------------------------------------------

obj FactExtraction {
    has topic: str,
        statement: str,
        sensitive: bool;
}

def extract_facts(text: str, source_kind: str) -> list[FactExtraction] by llm();
sem extract_facts = "Extract every discrete factual claim from this source document relevant to an insurance claim (coverage terms, exclusions, incident details, dates, causes, amounts). For each fact, 'statement' MUST be an exact verbatim sentence or clause copied from the text -- do not paraphrase, summarize, or reword. 'topic' is a short label describing what the fact is about (e.g. 'cause of water damage', 'coverage limit', 'filing deadline'). Be thorough: extract every distinct clause or sentence that could matter to a coverage decision, especially exclusions and conditions, not just a few highlights. Set 'sensitive' true ONLY for content explicitly marked internal-only/not-for-external-use, or that discusses a private matter genuinely unrelated to this claim (e.g. an unrelated personal dispute, health, or relationship detail). Ordinary claim administration facts -- the policyholder's name, policy number, loss location, dates, amounts, claim status -- are NEVER sensitive, even though they are personal data; mark those false. When in doubt, mark false.";
sem FactExtraction.topic = "Short topic label, consistent wording across sources when they refer to the same subject.";
sem FactExtraction.statement = "Verbatim excerpt copied exactly from the source text.";
sem FactExtraction.sensitive = "True ONLY for explicitly internal-only content or a private matter unrelated to the claim. False for all ordinary claim/coverage/identity facts, including names, policy numbers, and addresses -- these are routine, not sensitive.";

"""Deterministic (non-LLM) groundedness check: the statement must actually appear in the source."""
def is_grounded(statement: str, source_text: str) -> bool {
    return statement.strip() in source_text;
}

# --- Ingestion ----------------------------------------------------------

"""Populate the graph from the bundled fixture files. Safe to call multiple times -- skips if already ingested."""
walker:pub IngestFixtures {
    has reports: list[str] = [];

    can run with Root entry {
        existing = [-->][?:Source];
        if len(existing) > 0 {
            report "already ingested";
            return;
        }

        base = os.path.dirname(os.path.abspath(__file__));

        claims = [
            ("CLM-4471", "Water damage, upstairs bathroom"),
            ("CLM-2210", "Built-in dishwasher, sudden mechanical failure"),
        ];
        claim_nodes: dict[str, Claim] = {};
        for (cid, desc) in claims {
            cn = here ++> Claim(claim_id=cid, description=desc);
            claim_nodes[cid] = cn[0];
        }

        sources = [
            ("Policy_HO3-88214.pdf", "policy", "fixtures/policy.md", None),
            ("Claim_CLM-4471.pdf", "claim", "fixtures/claim.md", "CLM-4471"),
            ("Call_and_inspection_notes.txt", "call_notes", "fixtures/call_notes.md", "CLM-4471"),
            ("Claim_CLM-2210.pdf", "claim", "fixtures/claim2.md", "CLM-2210"),
        ];

        for (name, kind, relpath, owning_claim) in sources {
            path = os.path.join(base, relpath);
            f = open(path, "r", encoding="utf-8");
            text = f.read();
            f.close();

            src = here ++> Source(name=name, kind=kind, raw_text=text);
            extracted = extract_facts(text, kind);

            for item in extracted {
                if not is_grounded(item.statement, text) {
                    report f"rejected ungrounded fact: {item.statement[:60]}";
                    continue;
                }
                fact = src[0] ++> Fact(
                    topic=item.topic,
                    statement=item.statement,
                    source_name=name,
                    source_kind=kind,
                    sensitive=item.sensitive
                );
                if owning_claim != None {
                    claim_nodes[owning_claim] ++> fact[0];
                }
            }
        }
        report "ingested";
    }
}

# --- Claim review walker -------------------------------------------------

obj FactView {
    has topic: str,
        statement: str,
        source_name: str,
        source_kind: str;
}

obj ReviewResult {
    has claim_id: str,
        has_conflict: bool,
        conflict_topic: str,
        facts: list[FactView],
        action: str,
        answer: str,
        draft: str,
        withheld_count: int = 0;
}

obj ConflictAnalysis {
    has has_conflict: bool,
        conflict_topic: str;
}

def analyze_conflict(facts_summary: str) -> ConflictAnalysis by llm();
sem analyze_conflict = "Review these facts (each tagged with its source) about one insurance claim. A conflict exists ONLY if two facts make incompatible statements about the same specific real-world detail of THIS incident (e.g. one source says the cause was X, another source says the cause was Y, and X and Y cannot both be true) -- even if they use different wording or topic labels. A general policy rule or exclusion clause is NOT itself a conflict just because it is relevant or could apply -- it only creates a conflict if some other fact directly contradicts it or contradicts another incident-specific fact. If all the incident-specific facts (from the claim form, call notes, etc.) are consistent with each other, there is NO conflict, regardless of which policy exclusions exist. Do not flag a conflict on speculation about what might be true -- only on facts that are actually stated and actually incompatible. If found, conflict_topic should describe the underlying topic in plain words.";

def decide_action(claim_description: str, has_conflict: bool, facts_summary: str) -> str by llm();
sem decide_action = "Choose exactly one action for a claims adjuster reviewing this claim: 'answer' (facts are clear and consistent, just answer directly), 'flag_conflict' (sources disagree on something material to coverage -- surface it rather than guessing), or 'escalate' (too ambiguous or high-stakes to resolve at all, needs a senior adjuster). Return only the single action word.";

def compose_answer(claim_description: str, facts_summary: str, has_conflict: bool) -> str by llm();
sem compose_answer = "Write a short (2-4 sentence) explanation for a claims adjuster of what the facts say about this claim. If there's a conflict, clearly explain what disagrees and why it matters for coverage, without resolving it yourself. Do not invent facts beyond what's given.";

def draft_clarification(claim_description: str, facts_summary: str) -> str by llm();
sem draft_clarification = "Draft a short, polite message to the policyholder asking them to confirm the one detail that would resolve the coverage ambiguity described. 2-3 sentences, plain language, no legal jargon.";

"""Shared traversal: gather every non-sensitive fact relevant to a claim (global
policy facts + this claim's own facts). Used by both ClaimReview and Copilot
so the two don't drift on what counts as grounding context."""
def gather_claim_facts(claim: Claim) -> list[Fact] {
    claim_facts = [claim -->][?:Fact];
    all_gathered: list[Fact] = [];
    for src in [root -->][?:Source, kind == "policy"] {
        for f in [src -->][?:Fact] {
            all_gathered.append(f);
        }
    }
    for f in claim_facts {
        if f not in all_gathered {
            all_gathered.append(f);
        }
    }
    return [f for f in all_gathered if not f.sensitive];
}

def summarize_facts(facts: list[Fact]) -> str {
    return "\n".join([f"[{f.source_name}] ({f.topic}): {f.statement}" for f in facts]);
}

walker:pub ClaimReview {
    has claim_id: str = "CLM-4471",
        result: ReviewResult = ReviewResult(
            claim_id="", has_conflict=False, conflict_topic="",
            facts=[], action="", answer="", draft="", withheld_count=0
        ),
        reports: list[ReviewResult] = [];

    can start with Root entry {
        visit [-->][?:Claim, claim_id == self.claim_id];
    }

    can review with Claim entry {
        claim_facts = [-->][?:Fact];
        total_claim_and_policy = len(claim_facts) + len([f for src in [root -->][?:Source, kind == "policy"] for f in [src -->][?:Fact]]);

        # Sensitive facts are tracked but never surfaced to the LLM calls,
        # the citation list, or the policyholder-facing draft.
        all_relevant = gather_claim_facts(here);
        withheld_count = total_claim_and_policy - len(all_relevant);

        facts_summary = summarize_facts(all_relevant);

        analysis = analyze_conflict(facts_summary);
        has_conflict = analysis.has_conflict;
        conflict_topic = analysis.conflict_topic;
        action = decide_action(here.description, has_conflict, facts_summary);
        answer = compose_answer(here.description, facts_summary, has_conflict);
        draft = "";
        if "flag_conflict" in action or has_conflict {
            draft = draft_clarification(here.description, facts_summary);
        }

        self.result = ReviewResult(
            claim_id=here.claim_id,
            has_conflict=has_conflict,
            conflict_topic=conflict_topic,
            facts=[FactView(topic=f.topic, statement=f.statement, source_name=f.source_name, source_kind=f.source_kind) for f in all_relevant],
            action=action,
            answer=answer,
            draft=draft,
            withheld_count=withheld_count
        );
        report self.result;
    }
}

"""Return the small set of case-file rows shown on the dashboard."""
walker:pub GetDashboard {
    has reports: list[dict] = [];

    can run with Root entry {
        report {
            "claim_id": "CLM-4471",
            "title": "CLM-4471 -- water damage",
            "status": "contested",
            "summary": "The adjuster's own site note contradicts the customer's account of what caused the damage.",
            "sources": ["call_notes", "policy"]
        };
        report {
            "claim_id": "CLM-2210",
            "title": "CLM-2210 -- dishwasher failure",
            "status": "clear",
            "summary": "Covered under personal property, no sources disagree.",
            "sources": ["claim", "policy"]
        };
    }
}

"""Return every Source node's raw text, for the click-to-verify panel."""
walker:pub GetSources {
    has reports: list[dict] = [];

    can run with Root entry {
        for s in [-->][?:Source] {
            report {"name": s.name, "kind": s.kind, "raw_text": s.raw_text};
        }
    }
}

# --- Audit trail ---------------------------------------------------------

node ApprovalLog {
    has claim_id: str,
        draft_text: str,
        approved_at: str,
        approver: str;
}

"""Persist an approval event -- the real record backing the memo's signature line. Nothing is ever auto-logged as approved; this only runs when a human clicks Approve & Send."""
walker:pub ApproveDraft {
    has claim_id: str = "",
        draft_text: str = "",
        approver: str = "adjuster",
        reports: list[dict] = [];

    can run with Root entry {
        ts = datetime.datetime.now().isoformat(timespec="seconds");
        here ++> ApprovalLog(claim_id=self.claim_id, draft_text=self.draft_text, approved_at=ts, approver=self.approver);
        report {"approved_at": ts, "claim_id": self.claim_id, "approver": self.approver};
    }
}

"""Return the full approval history -- the actual audit trail, not just a UI label."""
walker:pub GetApprovalLog {
    has reports: list[dict] = [];

    can run with Root entry {
        for a in [-->][?:ApprovalLog] {
            report {"claim_id": a.claim_id, "draft_text": a.draft_text, "approved_at": a.approved_at, "approver": a.approver};
        }
    }
}

# --- Copilot ---------------------------------------------------------------
# Text-chat copilot: answers questions grounded in the open claim's facts (same
# groundedness rules as the rest of the app -- no free invention) and classifies
# whether the message is actually a request to navigate or to approve/send. It
# never performs the action itself -- it only reports the intent; the client
# triggers the SAME existing handlers (approveSend, navigate) a human clicking
# would use. One action type, two ways to trigger it -- not a new capability.

obj CopilotResponse {
    has reply: str,
        action: str,
        target_claim_id: str;
}

def copilot_respond(message: str, cases_summary: str, current_claim_context: str) -> CopilotResponse by llm();
sem copilot_respond = "You are Sift's copilot, embedded in an insurance case-file app. 'cases_summary' lists every open case as 'id: description'. 'current_claim_context' is empty if the user is on the case ledger (no claim open), or contains the open claim's description and known facts if they're reviewing one. Interpret the user's message: (1) If they're asking to open/view a different case by name or id, set action='navigate_claim' and target_claim_id to the matching id from cases_summary (exact id, not the description). (2) If they're asking to go back to the case list/ledger/home, set action='navigate_dashboard'. (3) If a claim is open (current_claim_context is non-empty) and they're asking to approve/send/confirm the drafted memo (e.g. 'approve it', 'send it', 'looks good, send'), set action='approve'. (4) Otherwise set action='answer' and just respond conversationally in 1-3 sentences, grounded ONLY in current_claim_context if it is given -- never invent a fact that isn't there. Always fill 'reply' with a short, natural response regardless of which action you chose (e.g. for 'approve' say something like 'Sending that now.'). target_claim_id must be empty string unless action is navigate_claim.";
sem CopilotResponse.action = "Exactly one of: answer, approve, navigate_dashboard, navigate_claim.";
sem CopilotResponse.target_claim_id = "The matching case id, only when action is navigate_claim; empty string otherwise.";

"""Text-chat copilot. Grounds answers in the same facts the rest of the app
uses (sensitive facts excluded), and classifies navigation/approval intent so
the client can trigger the existing handlers -- this walker never sends or
navigates on its own."""
walker:pub Copilot {
    has message: str = "",
        claim_id: str = "",
        reports: list[CopilotResponse] = [];

    can run with Root entry {
        cases_summary = "\n".join([f"{c.claim_id}: {c.description}" for c in [-->][?:Claim]]);

        current_claim_context = "";
        if self.claim_id {
            matches = [-->][?:Claim, claim_id == self.claim_id];
            if len(matches) > 0 {
                claim = matches[0];
                facts = gather_claim_facts(claim);
                current_claim_context = f"Claim {claim.claim_id}: {claim.description}\nFacts:\n{summarize_facts(facts)}";
            }
        }

        result = copilot_respond(self.message, cases_summary, current_claim_context);
        report result;
    }
}
