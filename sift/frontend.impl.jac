"""Implementations for the sift frontend components."""

impl Dashboard.loadDashboard -> None {
    loading = True;
    result = root spawn GetDashboard();
    dashboard = result.reports;
    loading = False;
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
        review = {
            "claim_id": r.claim_id,
            "has_conflict": r.has_conflict,
            "conflict_topic": r.conflict_topic,
            "facts": [
                {
                    "topic": f.topic,
                    "statement": f.statement,
                    "source_name": f.source_name,
                    "source_kind": f.source_kind
                }
                for f in r.facts
            ],
            "action": r.action,
            "answer": r.answer,
            "draft": r.draft,
            "withheld_count": r.withheld_count
        };
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
    result = root spawn ApproveDraft(
        claim_id=review.get("claim_id", ""),
        draft_text=review.get("draft", ""),
        approver="adjuster"
    );
    log_entry = result.reports[0];
    approved_at = log_entry["approved_at"];
    approved = True;
}
