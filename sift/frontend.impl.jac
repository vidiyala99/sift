"""Implementations for the sift frontend components."""

impl Dashboard.loadDashboard -> None {
    loading = True;
    result = root spawn GetDashboard();
    dashboard = result.reports;
    stats_result = root spawn GetStats();
    stats = stats_result.reports[0];
    loading = False;
}

impl Dashboard.sendCopilotMessage -> None {
    if not copilot_input.strip() {
        return;
    }
    user_msg = copilot_input;
    copilot_messages = copilot_messages + [{"role": "user", "text": user_msg}];
    copilot_input = "";
    copilot_busy = True;

    try {
        result = root spawn Copilot(message=user_msg, claim_id="");
        r = result.reports[0];
        copilot_messages = copilot_messages + [{"role": "assistant", "text": r.reply}];
        if r.action == "navigate_claim" and r.target_claim_id {
            navigate(f"/review/{r.target_claim_id}");
        }
    } except Exception as e {
        copilot_messages = copilot_messages + [{"role": "assistant", "text": f"Sorry, something went wrong: {e}"}];
    }
    copilot_busy = False;
}

impl Review.openReview(claim_id: str) -> None {
    loading = True;
    approved = False;
    approved_at = "";
    selected_source = "";
    selected_statement = "";
    review = {};

    try {
        src_result = root spawn GetSources();
        sources = src_result.reports;

        result = root spawn ClaimReview(claim_id=claim_id);
        r = result.reports[0];
        facts_list = [
            {
                "topic": f.topic,
                "statement": f.statement,
                "source_name": f.source_name,
                "source_kind": f.source_kind
            }
            for f in r.facts
        ];
        review = {
            "claim_id": r.claim_id,
            "has_conflict": r.has_conflict,
            "conflict_topic": r.conflict_topic,
            "facts": facts_list,
            "action": r.action,
            "answer": r.answer,
            "draft": r.draft,
            "withheld_count": r.withheld_count
        };

        # Default Source Verify to the first citable fact so it never renders
        # its empty "click a citation" state on load.
        citation_words = ["gradual", "sudden", "seepage", "rupture"];
        citable = [f for f in facts_list if any(w in f["statement"].lower() for w in citation_words)];
        if len(citable) > 0 {
            selected_source = citable[0]["source_name"];
            selected_statement = citable[0]["statement"];
        }
    } except Exception as e {
        review = {"error": f"{e}"};
    }
    loading = False;
}

impl Review.selectCitation(source_name: str, statement: str) -> None {
    selected_source = source_name;
    selected_statement = statement;
}

impl Review.approveSend -> None {
    final_text = draft_override if edited else review.get("draft", "");
    result = root spawn ApproveDraft(
        claim_id=review.get("claim_id", ""),
        draft_text=final_text,
        approver="adjuster",
        edited=edited
    );
    log_entry = result.reports[0];
    approved_at = log_entry["approved_at"];
    approved = True;
}

impl Review.rejectDraft -> None {
    final_text = draft_override if edited else review.get("draft", "");
    result = root spawn RejectDraft(
        claim_id=review.get("claim_id", ""),
        draft_text=final_text,
        approver="adjuster"
    );
    log_entry = result.reports[0];
    approved_at = log_entry["approved_at"];
    rejected = True;
}

impl Review.sendCopilotMessage(claim_id: str) -> None {
    if not copilot_input.strip() {
        return;
    }
    user_msg = copilot_input;
    copilot_messages = copilot_messages + [{"role": "user", "text": user_msg}];
    copilot_input = "";
    copilot_busy = True;

    try {
        result = root spawn Copilot(message=user_msg, claim_id=claim_id);
        r = result.reports[0];
        copilot_messages = copilot_messages + [{"role": "assistant", "text": r.reply}];
        if r.action == "approve" and review.get("draft") and not approved {
            approveSend();
        } elif r.action == "navigate_dashboard" {
            navigate("/dashboard");
        } elif r.action == "navigate_claim" and r.target_claim_id and r.target_claim_id != claim_id {
            navigate(f"/review/{r.target_claim_id}");
        }
    } except Exception as e {
        copilot_messages = copilot_messages + [{"role": "assistant", "text": f"Sorry, something went wrong: {e}"}];
    }
    copilot_busy = False;
}
