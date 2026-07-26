"""Sift - Client UI. Landing -> Dashboard -> Review, one component, local view state."""

import "./styles.css";

sv import from endpoints { GetDashboard, ClaimReview, GetSources }

def:pub app -> JsxElement {
    has view: str = "landing",
        dashboard: list[dict] = [],
        review: dict = {},
        sources: list[dict] = [],
        selected_source: str = "",
        selected_statement: str = "",
        approved: bool = False,
        loading: bool = False;

    async def goDashboard -> None;
    async def openReview(claim_id: str) -> None;
    async def selectCitation(source_name: str, statement: str) -> None;
    async def approveSend -> None;

    if view == "landing" {
        return
            <div className="sift-app">
                <div className="hero">
                    <span className="hero-tab">CASE FILE -- SIFT</span>
                    <h1>Stop cross-referencing.<br/>Start deciding.</h1>
                    <p>Sift pulls the tools you already work in -- Slack, Gmail, Granola, your CRM -- into one case file, flags where they disagree, and drafts what to do about it.</p>
                    <div className="stamp-wrap"><div className="stamp">CROSS-CHECKED</div></div>
                    <div><button className="cta" onClick={goDashboard}>Open a case file &#8594;</button></div>
                </div>
                <div className="steps">
                    <div className="step"><div className="n">01 / CONNECT</div><h3>Bring in your sources</h3><p>Point Sift at the tools where the real story already lives.</p></div>
                    <div className="step"><div className="n">02 / CROSS-CHECK</div><h3>Let it find the contradictions</h3><p>Sift compares every source on the same fact and flags where they don't agree.</p></div>
                    <div className="step"><div className="n">03 / DECIDE</div><h3>Review the drafted next step</h3><p>You get a cited answer and a drafted action. You approve -- Sift never sends on its own.</p></div>
                </div>
                <div className="evidence">
                    <div className="label">Evidence sources on file</div>
                    <div className="tag-row">
                        <span className="evidence-tag mono">SLACK</span>
                        <span className="evidence-tag mono">GMAIL</span>
                        <span className="evidence-tag mono">GRANOLA</span>
                        <span className="evidence-tag mono">CRM</span>
                    </div>
                </div>
            </div>;
    }

    if view == "dashboard" {
        return
            <div className="sift-app">
                <div className="bar">
                    <span>SIFT -- CASE LEDGER</span>
                    <button className="link" onClick={lambda e: any { view = "landing"; }}>&#8592; back</button>
                </div>
                <div className="cols">
                    <div className="ledger" style={{"borderRight": "none"}}>
                        <div className="label">Open cases</div>
                        {
                            loading &&
                            <div className="loading">loading case file...</div>
                        }
                        {
                            [
                                <button key={row["claim_id"]} className="ledger-row" onClick={lambda e: any { openReview(row["claim_id"]); }}>
                                    <div className="ledger-top">
                                        <div className="ledger-title">{row["title"]}</div>
                                        <span className={"stamp-mark " + ("red" if row["status"] == "contested" else "green")}>
                                            {"CONTESTED" if row["status"] == "contested" else "CLEARED"}
                                        </span>
                                    </div>
                                    <div className="ledger-desc">{row["summary"]}</div>
                                </button>
                                for row in dashboard
                            ]
                        }
                    </div>
                </div>
            </div>;
    }

    # view == "review"
    facts: list[dict] = review.get("facts", []);
    citation_facts = [f for f in facts if any(w in f["statement"].lower() for w in ["gradual", "sudden", "seepage", "rupture"])];
    selected_source_data = None;
    for s in sources {
        if s["name"] == selected_source {
            selected_source_data = s;
        }
    }
    verify_before = "";
    verify_match = "";
    verify_after = "";
    if selected_source_data != None and selected_statement in selected_source_data["raw_text"] {
        parts = selected_source_data["raw_text"].split(selected_statement, 1);
        verify_before = parts[0];
        verify_match = selected_statement;
        verify_after = parts[1] if len(parts) > 1 else "";
    } elif selected_source_data != None {
        verify_before = selected_source_data["raw_text"];
    }

    return
        <div className="sift-app">
            <div className="bar">
                <span>SIFT -- CASE FILE #{review.get("claim_id", "")}</span>
                <button className="link" onClick={goDashboard}>&#8592; back to ledger</button>
            </div>
            <div className="cols">
                <div className="graph-pane">
                    <div className="label">Sources on file</div>
                    {[<div key={s["name"]} className="idx-row">{s["kind"]} <span className="idx-dot"></span></div> for s in sources]}
                    <div className="trace-box">
                        <div className="hd">agent trace -- ClaimReview</div>
                        <div>&#8594; visited {len(facts)} facts across {len(sources)} sources</div>
                        {
                            review.get("has_conflict") &&
                            <div className="warn">&#9888; conflict: {review.get("conflict_topic", "")}</div>
                        }
                        <div className="ok">&#10003; action chosen: {review.get("action", "")}</div>
                    </div>
                </div>

                <div className="answer-pane">
                    <div className="qbubble">Is {review.get("claim_id", "")} covered? Client's account is on file.</div>
                    <div className={"answer-card" + (" conflict" if review.get("has_conflict") else "")}>
                        <div style={{"fontWeight": "700", "marginBottom": "6px"}}>{"Coverage depends on an unconfirmed fact" if review.get("has_conflict") else "Answer"}</div>
                        <div style={{"fontSize": "13px", "color": "var(--ink-soft)", "marginBottom": "8px"}}>{review.get("answer", "")}</div>
                        {
                            [
                                <button key={f["source_name"] + f["topic"]} className={"cite" + (" selected" if selected_statement == f["statement"] else "")} onClick={lambda e: any { selectCitation(f["source_name"], f["statement"]); }}>
                                    <b>{f["source_name"]}</b> &#8594; click to verify<br/>
                                    "{f["statement"]}"
                                </button>
                                for f in citation_facts
                            ]
                        }
                    </div>
                </div>

                <div className="memo-pane">
                    <div className="label">Recommended memo</div>
                    {
                        review.get("draft") &&
                        <div className="memo-card">
                            <div className="memo-head">RE: confirm cause of loss</div>
                            <div className="memo-body">"{review.get("draft", "")}"</div>
                            <div className="sig-line">APPROVED BY: __________________</div>
                            <button className="memo-btn primary" onClick={approveSend} disabled={approved}>
                                {"Sent (mocked)" if approved else "Approve & Send →"}
                            </button>
                        </div>
                    }
                    {
                        not review.get("draft") &&
                        <div className="memo-card">
                            <div style={{"fontSize": "13px", "color": "var(--ink-soft)"}}>No follow-up needed -- the facts on file are consistent, nothing to confirm.</div>
                        </div>
                    }
                    <div className="memo-note">Nothing leaves this case file without your signature. Sift drafts and cites -- it doesn't act unsupervised.</div>
                </div>

                <div className="verify-pane">
                    <div className="label">Source verify</div>
                    {
                        selected_source_data == None &&
                        <div className="verify-card">Click a citation to see the exact source line highlighted here.</div>
                    }
                    {
                        selected_source_data != None &&
                        <div className="verify-card">
                            <div className="verify-title">{selected_source_data["name"] if selected_source_data else ""}</div>
                            {verify_before}
                            {<mark>{verify_match}</mark> if verify_match else ""}
                            {verify_after}
                        </div>
                    }
                </div>
            </div>
        </div>;
}
