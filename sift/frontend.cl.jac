"""Sift - Client UI. Real routes: / (landing), /dashboard, /review/:id."""

import "./styles.css";
import from "@jac/runtime" { Router, Routes, Route, useNavigate, useParams, useLocation, Link }

sv import from endpoints { GetDashboard, GetStats, ClaimReview, GetSources, ApproveDraft, RejectDraft, Copilot }

def:pub app -> JsxElement {
    return
        <Router>
            <TopNav/>
            <Routes>
                <Route path="/" element={<Landing/>}></Route>
                <Route path="/dashboard" element={<Dashboard/>}></Route>
                <Route path="/review/:id" element={<Review/>}></Route>
            </Routes>
        </Router>;
}

def TopNav -> JsxElement {
    location = useLocation();
    navigate = useNavigate();
    path = location.pathname;
    is_review = path.startswith("/review/");
    is_dashboard = path == "/dashboard";
    crumb = path.replace("/review/", "") if is_review else "";

    if path == "/" {
        return <></>;
    }

    return
        <nav className="topnav">
            {
                is_review &&
                <button className="topnav-back" onClick={lambda e: any { navigate("/dashboard"); }} title="Back to Case Ledger" aria-label="Back to Case Ledger">&#8592;</button>
            }
            <Link to="/" className="topnav-brand">SIFT</Link>
            <div className="topnav-crumbs">
                <Link to="/dashboard" className={"topnav-link" + (" active" if is_dashboard else "")}>Case Ledger</Link>
                {
                    is_review &&
                    <>
                        <span className="crumb-sep">/</span>
                        <span className="topnav-crumb">Case #{crumb}</span>
                    </>
                }
            </div>
        </nav>;
}

def Landing -> JsxElement {
    navigate = useNavigate();

    return
        <div className="landing-frame">
            <div className="sift-app page-fade landing-split">
                <div className="landing-left">
                    <span className="hero-tab">CASE FILE -- SIFT <span className="case-no">NO. 2026-004</span></span>
                    <h1>Stop cross-referencing.<br/>Start deciding.</h1>
                    <p>Sift pulls the tools you already work in -- Slack, Gmail, Granola, your CRM -- into one case file, flags where they disagree, and drafts what to do about it.</p>
                    <div className="stamp-wrap"><div className="stamp">CROSS-CHECKED</div></div>
                    <div><button className="cta" onClick={lambda e: any { navigate("/dashboard"); }}>Open a case file &#8594;</button></div>
                </div>
                <div className="landing-right">
                    <div className="live-preview">
                        <div className="lp-head"><span className="lp-dot"></span> live -- watch Sift resolve a real conflict</div>
                        <div className="lp-body">
                            <svg className="lp-graph" width="150" height="130" viewBox="0 0 150 130">
                                <line className="lp-edge e1" x1="75" y1="18" x2="30" y2="60" stroke="#334155" strokeWidth="2"></line>
                                <line className="lp-edge e2" x1="75" y1="18" x2="120" y2="60" stroke="#334155" strokeWidth="2"></line>
                                <line className="lp-edge e3" x1="30" y1="68" x2="52" y2="112" stroke="#f59e0b" strokeWidth="2"></line>
                                <line className="lp-edge e4" x1="120" y1="68" x2="98" y2="112" stroke="#f59e0b" strokeWidth="2"></line>
                                <circle className="lp-node n1" cx="75" cy="18" r="11" fill="#2563eb"></circle>
                                <circle className="lp-node n2" cx="30" cy="65" r="9" fill="#4ade80"></circle>
                                <circle className="lp-node n3" cx="120" cy="65" r="9" fill="#4ade80"></circle>
                                <circle className="lp-node n4" cx="52" cy="112" r="10" fill="#f59e0b"></circle>
                                <circle className="lp-node n5" cx="98" cy="112" r="10" fill="#f59e0b">
                                    <animate attributeName="r" values="10;13;10" dur="1.2s" begin="3.2s" repeatCount="indefinite"></animate>
                                </circle>
                            </svg>
                            <div className="lp-lines">
                                <div className="lp-line l1">&#8594; reading Policy_HO3-88214.pdf...</div>
                                <div className="lp-line l2">&#8594; reading Call_and_inspection_notes.txt...</div>
                                <div className="lp-line l3">&#9888; conflict found: cause of water damage</div>
                                <div className="lp-line l4">&#10003; drafting adjuster follow-up memo</div>
                            </div>
                        </div>
                    </div>
                    <div className="trail">
                        <div className="exhibit">
                            <div className="exhibit-tag tag-a">EXHIBIT A</div>
                            <h3>Bring in your sources</h3>
                            <p>Point Sift at the tools where the real story already lives.</p>
                        </div>
                        <div className="exhibit">
                            <div className="exhibit-tag tag-b">EXHIBIT B</div>
                            <h3>Let it find the contradictions</h3>
                            <p>Sift compares every source on the same fact and flags where they don't agree.</p>
                        </div>
                        <div className="exhibit">
                            <div className="exhibit-tag tag-c">EXHIBIT C</div>
                            <h3>Review the drafted next step</h3>
                            <p>You get a cited answer and a drafted action. You approve -- Sift never sends on its own.</p>
                        </div>
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
                </div>
            </div>
        </div>;
}

def Dashboard -> JsxElement {
    has dashboard: list[dict] = [],
        stats: dict = {},
        filter: str = "all",
        loading: bool = False,
        copilot_open: bool = False,
        copilot_messages: list[dict] = [],
        copilot_input: str = "",
        copilot_busy: bool = False;

    navigate = useNavigate();

    can with entry {
        loadDashboard();
    }

    async def loadDashboard -> None;
    async def sendCopilotMessage -> None;

    n_contested = len([r for r in dashboard if r["status"] == "contested"]);
    n_clear = len([r for r in dashboard if r["status"] == "clear"]);
    visible_rows = [r for r in dashboard if filter == "all" or r["status"] == filter];

    return
        <>
        <div className="sift-app page-fade">
            <div className="page-head">
                <div className="label">Open cases</div>
            </div>
            {
                len(dashboard) > 0 &&
                <div className="dash-stats">
                    <div className="stat-card">
                        <div className="stat-label">Cases open</div>
                        <div className="stat-value">{len(dashboard)}</div>
                        <div className="stat-sub">{n_contested} need review</div>
                    </div>
                    <div className="stat-card">
                        <div className="stat-label"><span className="stat-pulse"></span>Facts on file</div>
                        <div className="stat-value">{stats.get("facts", 0)}</div>
                        <div className="stat-sub">across {stats.get("sources", 0)} synced sources</div>
                    </div>
                    <div className="stat-card">
                        <div className="stat-label">Conflicts flagged</div>
                        <div className="stat-value hot">{n_contested}</div>
                        <div className="stat-sub">awaiting adjuster decision</div>
                    </div>
                    <div className="stat-card">
                        <div className="stat-label">Clean cases</div>
                        <div className="stat-value clean">{n_clear}</div>
                        <div className="stat-sub">no disputes found</div>
                    </div>
                </div>
            }
            {
                len(dashboard) > 0 &&
                <div className="filter-row">
                    <button className={"filter-chip" + (" active" if filter == "all" else "")} onClick={lambda e: any { filter = "all"; }}>All cases</button>
                    <button className={"filter-chip" + (" active" if filter == "contested" else "")} onClick={lambda e: any { filter = "contested"; }}>Conflicts ({n_contested})</button>
                    <button className={"filter-chip" + (" active" if filter == "clear" else "")} onClick={lambda e: any { filter = "clear"; }}>Clean ({n_clear})</button>
                </div>
            }
            <div className="cols" style={{"minHeight": "auto"}}>
                <div className="ledger" style={{"borderRight": "none", "paddingBottom": "48px"}}>
                    {
                        loading &&
                        <div className="loading">loading case file...</div>
                    }
                    {
                        [
                            <button
                                key={row["claim_id"]}
                                className={"ledger-row row-in" + (" contested" if row["status"] == "contested" else "")}
                                style={{"animationDelay": f"{i * 45}ms"}}
                                onClick={lambda e: any { navigate(f"/review/{row['claim_id']}"); }}
                            >
                                <div className="ledger-top">
                                    <div className="ledger-title">{row["title"]}</div>
                                    <span className={"stamp-mark " + ("red" if row["status"] == "contested" else "green")}>
                                        {"CONTESTED" if row["status"] == "contested" else "CLEARED"}
                                    </span>
                                </div>
                                <div className="ledger-desc">{row["summary"]}</div>
                                <div className="ledger-reveal">Sources: {row.get("sources", []).join(", ")}</div>
                            </button>
                            for (i, row) in enumerate(visible_rows)
                        ]
                    }
                    {
                        len(dashboard) > 0 and filter == "all" &&
                        <div className="ledger-row static row-in" style={{"animationDelay": f"{len(dashboard) * 45}ms"}}>
                            <div className="ledger-top">
                                <div className="ledger-title">Reyes household -- policy renewal</div>
                                <span className="stamp-mark blue">DRAFTED</span>
                            </div>
                            <div className="ledger-desc">Follow-up drafted from a prior call. Same engine, illustrative only -- not wired in this build.</div>
                        </div>
                    }
                </div>
            </div>
        </div>
            <div className="copilot-widget">
                <button className="copilot-toggle" onClick={lambda e: any { copilot_open = not copilot_open; }}>
                    {"✕ Close" if copilot_open else "💬 Ask Sift"}
                </button>
                {
                    copilot_open &&
                    <div className="copilot-panel">
                        <div className="copilot-header">Ask Sift <span className="copilot-badge">beta</span></div>
                        <div className="copilot-messages">
                            {
                                len(copilot_messages) == 0 &&
                                <div className="copilot-hint">Try "open the water damage case" or "what's still open?"</div>
                            }
                            {[
                                <div key={str(i)} className={"copilot-msg " + m["role"]}>{m["text"]}</div>
                                for (i, m) in enumerate(copilot_messages)
                            ]}
                            {copilot_busy && <div className="copilot-msg assistant typing">thinking...</div>}
                        </div>
                        <div className="copilot-input-row">
                            <input
                                className="copilot-input"
                                value={copilot_input}
                                placeholder="Ask or say 'open CLM-4471'..."
                                onChange={lambda e: any { copilot_input = e.target.value; }}
                                onKeyDown={lambda e: any { if e.key == "Enter" { sendCopilotMessage(); } }}
                            />
                            <button className="copilot-send" onClick={lambda e: any { sendCopilotMessage(); }} disabled={copilot_busy}>&#8594;</button>
                        </div>
                    </div>
                }
            </div>
        </>;
}

def Review -> JsxElement {
    params = useParams();
    claim_id = params["id"];
    navigate = useNavigate();

    has review: dict = {},
        sources: list[dict] = [],
        selected_source: str = "",
        selected_statement: str = "",
        approved: bool = False,
        approved_at: str = "",
        rejected: bool = False,
        editing: bool = False,
        edited: bool = False,
        draft_override: str = "",
        loading: bool = False,
        copilot_open: bool = False,
        copilot_messages: list[dict] = [],
        copilot_input: str = "",
        copilot_busy: bool = False;

    can with entry {
        openReview(claim_id);
    }

    async def openReview(claim_id: str) -> None;
    async def selectCitation(source_name: str, statement: str) -> None;
    async def approveSend -> None;
    async def rejectDraft -> None;
    async def sendCopilotMessage(claim_id: str) -> None;

    if loading {
        return
            <div className="sift-app page-fade">
                <div className="loading">
                    <div className="display" style={{"fontSize": "16px", "marginBottom": "10px"}}>cross-checking sources...</div>
                    <div style={{"fontSize": "12.5px"}}>traversing the graph, comparing facts, and drafting a recommendation</div>
                </div>
            </div>;
    }

    if review.get("error") {
        return
            <div className="sift-app page-fade">
                <div className="loading">
                    <div className="display" style={{"fontSize": "16px", "marginBottom": "10px", "color": "var(--stamp-red)"}}>couldn't reach the case file</div>
                    <div style={{"fontSize": "12.5px"}}>{review.get("error")}</div>
                </div>
            </div>;
    }

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

    # --- graph layout (precomputed so the JSX below stays simple) ---
    n_src = len(sources);
    source_positions: list[dict] = [];
    for (i, s) in enumerate(sources) {
        x = 116 if n_src <= 1 else (20 + i * (192 / (n_src - 1)));
        source_positions.append({"name": s["name"], "kind": s["kind"], "x": x});
    }
    source_x_map = {p["name"]: p["x"] for p in source_positions};

    graph_facts = citation_facts[:4];
    n_facts = len(graph_facts);
    fact_positions: list[dict] = [];
    for (i, f) in enumerate(graph_facts) {
        x = 116 if n_facts <= 1 else (20 + i * (192 / (n_facts - 1)));
        fact_positions.append({"x": x, "src_x": source_x_map.get(f["source_name"], 116)});
    }
    has_conflict = review.get("has_conflict", False);
    n_src_nodes = len(source_positions);

    review_status = "contested" if has_conflict else "clear";

    return
        <>
        <div className="sift-app page-fade">
            <div className="review-head">
                <h1>Case #{review.get("claim_id", "")}</h1>
                <div className="topnav-status">
                    <span className={"status-dot " + review_status}></span>
                    <span className={"status-pill " + review_status}>{"Awaiting review" if has_conflict else "No action needed"}</span>
                </div>
            </div>
            <div className="cols">
                <div className="graph-pane">
                    <div className="label">Live traversal -- ClaimReview</div>
                    <svg width="232" height="210" style={{"background": "var(--trace-dark)", "borderRadius": "8px"}}>
                        {[
                            <line key={"cl-" + p["name"]} className="graph-in" style={{"animationDelay": f"{100 + i * 120}ms"}} x1="116" y1="26" x2={p["x"]} y2="86" stroke="#334155" strokeWidth="2"></line>
                            for (i, p) in enumerate(source_positions)
                        ]}
                        {[
                            <line key={"sf-" + str(i)} className="graph-in" style={{"animationDelay": f"{100 + n_src_nodes * 120 + i * 120}ms"}} x1={fp["src_x"]} y1="98" x2={fp["x"]} y2="170" stroke={"#f59e0b" if has_conflict else "#334155"} strokeWidth="2"></line>
                            for (i, fp) in enumerate(fact_positions)
                        ]}
                        <circle cx="116" cy="26" r="16" fill="#2563eb" className="graph-in"><title>Case {review.get("claim_id", "")} -- {len(facts)} facts, {len(sources)} sources</title></circle>
                        <text x="116" y="30" textAnchor="middle" fontSize="10" fill="white" className="graph-in">CLM</text>
                        {[
                            <circle
                                key={"sn-" + p["name"]} cx={p["x"]} cy="86" r="12" fill="#4ade80" className="graph-in gnode"
                                style={{"animationDelay": f"{100 + i * 120}ms", "cursor": "pointer"}}
                                onClick={lambda e: any { selected_source = p["name"]; selected_statement = ""; }}
                            ><title>{p["name"]} -- click to jump to source</title></circle>
                            for (i, p) in enumerate(source_positions)
                        ]}
                        {[
                            <text key={"st-" + p["name"]} x={p["x"]} y="90" textAnchor="middle" fontSize="9" fill="#0f172a" className="graph-in" style={{"animationDelay": f"{100 + i * 120}ms", "pointerEvents": "none"}}>{p["kind"][0:4]}</text>
                            for (i, p) in enumerate(source_positions)
                        ]}
                        {[
                            <circle
                                key={"fn-" + str(i)} cx={fp["x"]} cy="170" r={13 if has_conflict else 9} fill={"#f59e0b" if has_conflict else "#4ade80"} className="graph-in gnode"
                                style={{"animationDelay": f"{100 + n_src_nodes * 120 + i * 120}ms", "cursor": "pointer"}}
                                onClick={lambda e: any { selectCitation(graph_facts[i]["source_name"], graph_facts[i]["statement"]); }}
                            >
                                <title>{graph_facts[i]["topic"]} -- click to verify against {graph_facts[i]["source_name"]}</title>
                                {
                                    has_conflict &&
                                    <animate attributeName="r" values="13;17;13" dur="1.3s" begin={f"{0.1 + (n_src_nodes * 120 + i * 120) / 1000}s"} repeatCount="indefinite"></animate>
                                }
                            </circle>
                            for (i, fp) in enumerate(fact_positions)
                        ]}
                    </svg>
                    <div className="tally">
                        {len(facts)} facts on file<br/>
                        {len(sources)} sources synced<br/>
                        {has_conflict && <span className="hot">&#9888; {len(graph_facts)} facts tied to the dispute</span>}
                        {not has_conflict && "no disputes found"}
                    </div>
                    <div className="trace-box">
                        <div className="hd">agent trace -- ClaimReview</div>
                        <div className="trace-line-in" style={{"animationDelay": "80ms"}}>&#8594; visited {len(facts)} facts across {len(sources)} sources</div>
                        {
                            review.get("withheld_count", 0) > 0 &&
                            <div className="trace-line-in" style={{"animationDelay": "480ms"}}>&#128274; withheld {review.get("withheld_count", 0)} sensitive fact(s) -- not surfaced</div>
                        }
                        {
                            review.get("has_conflict") &&
                            <div className="warn trace-line-in" style={{"animationDelay": "880ms"}}>&#9888; conflict: {review.get("conflict_topic", "")}</div>
                        }
                        <div className="ok trace-line-in" style={{"animationDelay": "1280ms"}}>&#10003; action chosen: {review.get("action", "")}</div>
                    </div>
                </div>

                <div className="answer-pane">
                    <div className="qbubble">Is {review.get("claim_id", "")} covered? Client's account is on file.</div>
                    <div className={"answer-card" + (" conflict" if review.get("has_conflict") else "")}>
                        <div style={{"fontWeight": "700", "marginBottom": "6px"}}>{"Coverage depends on an unconfirmed fact" if review.get("has_conflict") else "Answer"}</div>
                        <div style={{"fontSize": "13px", "color": "var(--ink-soft)", "marginBottom": "8px"}}>{review.get("answer", "")}</div>
                        {
                            [
                                <button key={f["source_name"] + f["topic"]} className={"cite cite-in" + (" selected" if selected_statement == f["statement"] else "")} style={{"animationDelay": f"{i * 60}ms"}} onClick={lambda e: any { selectCitation(f["source_name"], f["statement"]); }}>
                                    <b>{f["source_name"]}</b> &#8594; click to verify<br/>
                                    "{f["statement"]}"
                                </button>
                                for (i, f) in enumerate(citation_facts)
                            ]
                        }
                    </div>
                </div>

                <div className="memo-pane">
                    <div className="label">Recommended memo</div>
                    {
                        review.get("draft") and rejected &&
                        <div className="memo-card">
                            <div className="memo-head">RE: confirm cause of loss</div>
                            <div className="memo-body">"{draft_override if edited else review.get("draft", "")}"</div>
                            <div className="sig-line">REJECTED BY: adjuster -- {approved_at}</div>
                            <button className="memo-btn primary" disabled={True}>&#10005; Rejected -- logged</button>
                        </div>
                    }
                    {
                        review.get("draft") and not rejected and editing &&
                        <div className="memo-card">
                            <div className="memo-head">RE: confirm cause of loss</div>
                            <textarea
                                className="memo-edit"
                                value={draft_override}
                                onChange={lambda e: any { draft_override = e.target.value; }}
                                rows={5}
                            ></textarea>
                            <div className="memo-actions">
                                <button className="memo-btn edit" onClick={lambda e: any { editing = False; draft_override = ""; }}>Cancel</button>
                                <button className="memo-btn primary" onClick={lambda e: any { edited = True; editing = False; }}>Save</button>
                            </div>
                        </div>
                    }
                    {
                        review.get("draft") and not rejected and not editing &&
                        <div className="memo-card">
                            <div className="memo-head">RE: confirm cause of loss</div>
                            <div className="memo-body">"{draft_override if edited else review.get("draft", "")}"</div>
                            <div className="sig-line">
                                {"APPROVED BY: adjuster -- " + approved_at if approved else "APPROVED BY: __________________"}
                            </div>
                            <div className="memo-actions">
                                {
                                    not approved &&
                                    <button className="memo-btn reject" onClick={rejectDraft} title="Reject this recommendation" aria-label="Reject">&#10005;</button>
                                }
                                {
                                    not approved &&
                                    <button className="memo-btn edit" onClick={lambda e: any { draft_override = review.get("draft", "") if not edited else draft_override; editing = True; }}>Edit</button>
                                }
                                <button className={"memo-btn primary" + (" just-approved" if approved else "")} onClick={approveSend} disabled={approved}>
                                    {"✓ Sent (mocked) -- logged" if approved else "Approve & Send →"}
                                </button>
                            </div>
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
        </div>
            <div className="copilot-widget">
                <button className="copilot-toggle" onClick={lambda e: any { copilot_open = not copilot_open; }}>
                    {"✕ Close" if copilot_open else "💬 Ask Sift"}
                </button>
                {
                    copilot_open &&
                    <div className="copilot-panel">
                        <div className="copilot-header">Ask Sift <span className="copilot-badge">beta</span></div>
                        <div className="copilot-messages">
                            {
                                len(copilot_messages) == 0 &&
                                <div className="copilot-hint">Try "what's the conflict about?" or "approve it"</div>
                            }
                            {[
                                <div key={str(i)} className={"copilot-msg " + m["role"]}>{m["text"]}</div>
                                for (i, m) in enumerate(copilot_messages)
                            ]}
                            {copilot_busy && <div className="copilot-msg assistant typing">thinking...</div>}
                        </div>
                        <div className="copilot-input-row">
                            <input
                                className="copilot-input"
                                value={copilot_input}
                                placeholder="Ask about this case, or say 'approve it'..."
                                onChange={lambda e: any { copilot_input = e.target.value; }}
                                onKeyDown={lambda e: any { if e.key == "Enter" { sendCopilotMessage(claim_id); } }}
                            />
                            <button className="copilot-send" onClick={lambda e: any { sendCopilotMessage(claim_id); }} disabled={copilot_busy}>&#8594;</button>
                        </div>
                    </div>
                }
            </div>
        </>;
}
