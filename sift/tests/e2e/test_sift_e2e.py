"""
End-to-end tests for Sift, driven with Playwright against a real running app.

Prerequisites:
    1. `jac start --dev` running in sift/ (server on :8000, API on :8001)
    2. An LLM backend configured (OPENAI_API_KEY env var, or a local model
       in jac.toml) -- these tests exercise real by llm() calls, no mocks.

Run:
    pip install pytest playwright
    playwright install chromium
    pytest tests/e2e -v
"""

import urllib.request
import json

import pytest
from playwright.sync_api import sync_playwright, Page

BASE_URL = "http://localhost:8000"
API_URL = "http://localhost:8001"


def _post(path: str, payload: dict) -> dict:
    req = urllib.request.Request(
        f"{API_URL}{path}",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read())


@pytest.fixture(scope="session", autouse=True)
def ensure_fixtures_ingested():
    """Idempotent: safe to call even if already ingested."""
    _post("/walker/IngestFixtures", {})


@pytest.fixture(scope="session")
def browser():
    with sync_playwright() as p:
        b = p.chromium.launch(headless=True)
        yield b
        b.close()


@pytest.fixture()
def page(browser):
    pg = browser.new_page(viewport={"width": 1440, "height": 900})
    errors = []
    pg.on("pageerror", lambda exc: errors.append(str(exc)))
    yield pg
    assert errors == [], f"Uncaught JS errors during test: {errors}"
    pg.close()


def _wait_review_loaded(page: Page):
    page.wait_for_function(
        "document.querySelector('.trace-box') && "
        "document.querySelector('.trace-box').innerText.includes('visited') && "
        "!document.querySelector('.trace-box').innerText.includes('visited 0')",
        timeout=30000,
    )
    page.wait_for_timeout(300)


class TestLanding:
    def test_landing_renders(self, page: Page):
        page.goto(BASE_URL)
        page.wait_for_load_state("networkidle")
        assert page.locator("text=Stop cross-referencing").count() == 1
        # Landing intentionally has no persistent nav bar (marketing page, not app screen)
        assert page.locator(".topnav").count() == 0

    def test_open_case_file_navigates_to_dashboard(self, page: Page):
        page.goto(BASE_URL)
        page.click("text=Open a case file")
        page.wait_for_load_state("networkidle")
        assert page.url == f"{BASE_URL}/dashboard"


class TestDashboard:
    def test_dashboard_lists_cases(self, page: Page):
        page.goto(f"{BASE_URL}/dashboard")
        page.wait_for_load_state("networkidle")
        page.wait_for_timeout(300)
        assert page.locator(".ledger-row").count() == 3  # 2 real + 1 static illustrative row
        assert page.locator(".topnav-link.active", has_text="Case Ledger").count() == 1


class TestClaimReviewContested:
    """CLM-4471: the water-damage claim with a planted, real conflict."""

    def test_conflict_detected_with_citations(self, page: Page):
        page.goto(f"{BASE_URL}/review/CLM-4471")
        _wait_review_loaded(page)
        assert page.locator("text=Coverage depends on an unconfirmed fact").count() == 1
        assert page.locator("text=withheld 1 sensitive fact").count() == 1  # the neighbor-dispute aside
        assert page.locator("button.cite").count() >= 4

    def test_citation_verify_highlights_exact_span(self, page: Page):
        page.goto(f"{BASE_URL}/review/CLM-4471")
        _wait_review_loaded(page)
        page.locator("button.cite").first.click()
        page.wait_for_timeout(300)
        mark = page.locator(".verify-card mark")
        assert mark.count() == 1
        assert len(mark.inner_text()) > 10

    def test_approve_and_send_logs_real_audit_entry(self, page: Page):
        page.goto(f"{BASE_URL}/review/CLM-4471")
        _wait_review_loaded(page)
        page.click("text=Approve & Send")
        page.wait_for_timeout(500)
        sig = page.locator(".sig-line").inner_text()
        assert "adjuster" in sig
        assert "T" in sig  # ISO timestamp


class TestClaimReviewClean:
    """CLM-2210: the dishwasher claim, deliberately consistent, no conflict."""

    def test_no_conflict_clean_answer(self, page: Page):
        page.goto(f"{BASE_URL}/review/CLM-2210")
        _wait_review_loaded(page)
        assert page.locator("text=No follow-up needed").count() == 1
        assert page.locator("text=no disputes found").count() == 1


class TestRouting:
    def test_back_forward_preserve_state(self, page: Page):
        page.goto(f"{BASE_URL}/dashboard")
        page.wait_for_load_state("networkidle")
        page.click("text=CLM-4471")
        _wait_review_loaded(page)
        page.go_back()
        page.wait_for_timeout(300)
        assert page.url == f"{BASE_URL}/dashboard"
        page.go_forward()
        page.wait_for_timeout(300)
        assert "review/CLM-4471" in page.url

    def test_deep_link_refresh(self, page: Page):
        page.goto(f"{BASE_URL}/review/CLM-4471")
        _wait_review_loaded(page)
        assert page.locator("text=agent trace").count() == 1


class TestCopilot:
    def test_grounded_qa(self, page: Page):
        page.goto(f"{BASE_URL}/review/CLM-4471")
        _wait_review_loaded(page)
        page.click(".copilot-toggle")
        page.fill(".copilot-input", "what's the coverage limit for water damage?")
        page.click(".copilot-send")
        page.wait_for_selector(".copilot-msg.assistant:not(.typing)", timeout=20000)
        reply = page.locator(".copilot-msg.assistant:not(.typing)").last.inner_text()
        assert "25,000" in reply or "25000" in reply.replace(",", "")

    def test_chat_triggered_approve_calls_real_action(self, page: Page):
        page.goto(f"{BASE_URL}/review/CLM-4471")
        _wait_review_loaded(page)
        page.click(".copilot-toggle")
        page.fill(".copilot-input", "looks good, send it")
        page.click(".copilot-send")
        page.wait_for_timeout(3000)
        assert "adjuster" in page.locator(".sig-line").inner_text()
