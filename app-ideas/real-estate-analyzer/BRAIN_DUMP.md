# Real Estate Analyzer — Brain Dump

**Status**: Idea / Pre-planning
**Date**: 2026-03-04
**Stage**: Personal tool first → public SaaS later

---

## The Vision

A modern, interactive real estate investment analysis platform powered by AI agents. Combines live property monitoring (alerts the moment a listing posts) with deep deal calculators across four investment strategies. Built for personal use first, with the architecture and UX polished enough to open to the public.

---

## Core Features

### 1. AI Property Monitoring Agents
Agents continuously watch listing sources and alert the user as soon as a property is posted.

**Sources to monitor:**
- Zillow, Redfin, Realtor.com (MLS aggregators)
- Hubzu, Auction.com (distressed/foreclosure)

**Alert channels:**
- In-app dashboard (live feed)
- Email notifications
- SMS / text message

**Agent behavior:**
- User defines search criteria (market, price range, property type, bed/bath, etc.)
- Agent scores each new listing against the user's investment criteria
- Surfaces only deals that pass a threshold — not every listing

### 2. Deal Calculators (Interactive)

All calculators should be highly visual, interactive (sliders, live recalculation), and mobile-friendly.

#### A. Rental Property Analysis (Buy & Hold)
- Purchase price, down payment, closing costs
- Monthly rent, vacancy rate, property management %
- Insurance, taxes, maintenance, CapEx reserves
- Outputs: Cash flow, CoC return, cap rate, gross/net yield
- Amortization schedule

#### B. BRRRR Calculator
(Buy → Rehab → Rent → Refinance → Repeat)
- After-Repair Value (ARV)
- Purchase price + rehab cost
- Hard money loan terms (rate, points, term)
- Cash-out refinance terms (LTV, rate, new payment)
- Outputs: Equity captured, cash left in deal, infinite return scenarios
- Side-by-side: money in vs. money recovered

#### C. Short-Term Rental (STR / Airbnb/VRBO)
- Purchase price + setup/furnishing costs
- Estimated nightly rate, occupancy %, seasonality
- Platform fees (Airbnb ~3%, VRBO ~5%)
- Cleaning fees, supplies, property management
- Outputs: Gross revenue, net income, CoC return, comparison to LTR

#### D. VA Loan Calculator
- $0 down scenarios (VA-specific)
- VA funding fee (first use vs. subsequent, disabled vet exemption)
- Loan limits by county
- Residual income check (VA requirement by family size/region)
- Outputs: Monthly payment, total interest, break-even vs. conventional

### 3. Property Comparison Dashboard
- Save and compare multiple properties side by side
- Score/rank deals against each other
- Tag properties (watchlist, analyzing, passed, offer made)

### 4. Market Intelligence (Future)
- Rent growth trends by zip code
- Days on market trends
- Price/rent ratio heat maps

---

## Tech Stack Ideas

### Frontend
- **Next.js** (React) — modern, fast, SEO-friendly for public launch
- **Tailwind CSS** + component library (shadcn/ui or Radix)
- Interactive charts: **Recharts** or **Chart.js**
- Sliders/inputs: real-time recalculation without page reload

### Backend / API
- **Node.js** or **Python (FastAPI)** for the API layer
- **Claude API** (multi-agent orchestration) for property scoring and analysis
- **PostgreSQL** for user data, saved properties, search criteria

### Property Monitoring Agents
- Scraping layer: **Playwright** or **Puppeteer** (headless browser for JS-heavy sites)
- Job queue: **BullMQ** (Redis-backed) or **AWS SQS** for scheduling agent runs
- Alerts: **Twilio** (SMS) + **SendGrid** or **Resend** (email) + WebSocket for live dashboard

### Hosting / Infrastructure
- **Vercel** for frontend (free tier for personal, scales for public)
- **AWS** for backend (fits existing AWS study path):
  - Lambda for agent run triggers
  - RDS (PostgreSQL) for data
  - SQS for job queuing
  - SES for email alerts

---

## Multi-Agent Architecture (Claude API)

```
User sets search criteria
        │
        ▼
[Orchestrator Agent]
        │
        ├──► [Listing Monitor Agent] — scrapes sources, finds new listings
        │           │
        │           ▼
        │    [Scoring Agent] — evaluates listing against user criteria
        │           │
        │           ▼
        │    [Alert Agent] — sends SMS/email/dashboard push
        │
        └──► [Analysis Agent] — runs deep calculator logic on saved property
                    │
                    ▼
             [Report Agent] — generates human-readable deal summary
```

---

## Monetization (Public SaaS — Later)

- **Free tier**: 1 saved search, basic calculators
- **Pro ($19–29/month)**: Unlimited searches, all calculators, SMS alerts, comparison dashboard
- **Investor ($49–79/month)**: Priority alerts, market data, export to PDF/CSV, team seats

---

## Open Questions / Next Steps

- [ ] Which market(s) to target first for monitoring? (geographic filter)
- [ ] Build the calculators first (no scraping needed) or the agent pipeline first?
- [ ] Scraping terms of service — Zillow/Redfin have ToS restrictions; may need to use their APIs or data partnerships
- [ ] Authentication: magic link? Google OAuth?
- [ ] Mobile app eventually, or PWA from day one?

---

## Related Files
- AWS study projects: `~/workspace/ai-terminal-workflow/aws-projects/` (infra knowledge applies directly)
- FinOps notes: `~/workspace/ai-terminal-workflow/finops-projects/` (cost-aware architecture)
