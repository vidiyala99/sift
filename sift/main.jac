"""sift - Entry Point.

Combines server-side endpoints with the client-side UI.
"""

import from endpoints { Source, Fact, Claim, IngestFixtures, ClaimReview, GetDashboard, GetStats, GetSources, ApprovalLog, ApproveDraft, RejectDraft, GetApprovalLog, Copilot }

# Client-side UI
cl {
    import from .frontend { app as ClientApp }

    def:pub app -> JsxElement {
        return <ClientApp/>;
    }
}
