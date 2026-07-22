# 🧠 Hermes Brain — Jarvis Agent Identity

> *The configuration, identity, and procedural memory of Jarvis — a self-evolving AI workforce running 24/7 on Hermes Agent.*

---

## What is Jarvis?

Jarvis is a **personal AI orchestrator** — a CEO-level agent that manages a small workforce of specialized AI profiles. It runs on a VPS, connected to Telegram, processing trading signals, managing system health, and executing tasks autonomously.

Unlike a chatbot you talk to once, Jarvis has **persistent memory**, **reusable skills**, and **24/7 scheduled operations**. It doesn't just answer questions — it does real work.

---

## 🏗️ The Foundation

### Architecture

```
┌──────────────────────────────────────────────────┐
│                    JARVIS (CEO)                    │
│            default profile — DeepSeek V4          │
│     Orchestrator: memory, delegate, cron, todo    │
├──────────────────────────────────────────────────┤
│                                                    │
│  ┌──────────┐  ┌──────────┐  ┌──────────────────┐ │
│  │ Planner  │  │Developer │  │   Researcher     │ │
│  │ minimax  │  │deepseek  │  │    minimax       │ │
│  │ read-only│  │ code+git │  │  web+browser     │ │
│  │ Kanban   │  │ skills   │  │  research only   │ │
│  └──────────┘  └──────────┘  └──────────────────┘ │
│  ┌──────────┐  ┌─────────────────────────────────┐ │
│  │  Trader  │  │   Kanban Dispatcher              │ │
│  │ deepseek │  │   auto-decompose → assign → run  │ │
│  │ MT5 only │  └─────────────────────────────────┘ │
│  │ observe  │                                      │
│  └──────────┘                                      │
├──────────────────────────────────────────────────┤
│         Trade-Copier Pipeline (Production)         │
│  Telegram → Listener → Router → Bridge → MT5      │
│         (Observe-Only — No Live Orders)            │
└──────────────────────────────────────────────────┘
```

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| **Two-Phase Workflow** | Plan (Phase 1, read-only, minimax) → Execute (Phase 2, full tools, deepseek). Saves ~80% token cost |
| **"Execute Jarvis" Gate** | Phase 2 is gated by explicit keyword. Prevents execution drift — the solution stays true to what was approved |
| **Kanban Dispatcher** | Async task queue: dump a task, the dispatcher assigns it, a profile works on it, results come back to Telegram |
| **Profile Isolation** | Each profile has its own config, model, tools, and SOUL.md. Planner gets minimax (cheap, 205K ctx). Developer gets deepseek (strong, 1M ctx) |
| **No-Agent Cron** | Zero-token scheduled tasks. Script runs, if output is empty → silence. Only fires when there's something to report |

---

## 🛠️ Tech Stack

| Layer | Technology |
|-------|-----------|
| **Agent Framework** | [Hermes Agent](https://github.com/NousResearch/hermes-agent) by Nous Research |
| **LLM (Planning)** | MiniMax M2.7 (205K context, 2-8x cheaper) |
| **LLM (Execution)** | DeepSeek V4 Flash (1.05M context) |
| **LLM (Vision)** | Google Gemini 2.0 Flash |
| **Provider** | OpenRouter (model routing + failover) |
| **Infrastructure** | Docker Compose, VPS (Linux) |
| **Messaging** | Telegram (primary) + API Server |
| **Database** | SQLite (Kanban, sessions, state) |
| **Trading** | MetaTrader 5 (OctaFX Demo) |
| **Automation** | Cron jobs, Kanban dispatcher, GitHub Actions |

---

## ✅ What's Working Well

### Trade-Copier Pipeline (Production)
- **4 containers** (listener, router, bridge, MT5) running 24/7
- **6 channels** monitored (4 text + 2 image signals)
- **Signal parsing** — both text and image-based signals processed correctly
- **Guardrails** — SL/TP validation, 50-pip min SL on image signals, pending order rules, daily loss cap (20%), per-channel (5) / global (25) trade limits
- **Delete handling** — deleted messages auto-close trades via /close_channel

### Multi-Agent Workforce
- **Planner profile** — researching, spec'ing, and handing off on Kanban
- **Developer profile** — building skills, fixing bugs, deploying containers
- **Researcher profile** — deep-dive investigations with web + browser
- **Trader profile** — validating guardrails, observing MT5 connection

### System Improvements
- **Smart approvals** — auxiliary model auto-approves low-risk commands
- **Context compression** — triggers at 35% of model limit, keeps sessions cheaper
- **Curator consolidation** — automatically merges overlapping skills
- **Kanban→Telegram bridge** — cron job that surfaces completions to DM (zero token cost when idle)
- **Project context** — `.hermes.md` auto-loads conventions every session
- **No-agent cron** — zero-token scheduled tasks that only fire on change

---

## ⚠️ Challenges & Lessons Learned

| Challenge | Solution |
|-----------|----------|
| **Router had empty API key** — LLM calls silently failed | Restored `.env` permissions, added `OPENROUTER_API_KEY` properly, rebuilt containers |
| **Execution drift** — solutions silently diverged from approved plans | Introduced the **"Execute Jarvis"** gate — any error in execution stops, re-plans, and requires fresh approval |
| **Kanban dispatcher crashes on default profile** | Only assign tasks to specific profiles (developer, researcher, planner, trader) — default profile can't handle dispatched workloads |
| **Memory limit (2,200 chars)** — tool calls failed mid-session | Trimmed entries, consolidated duplicates, removed task narratives |
| **Profile memory isolation** — planner profile had no memory context | Symlinked memory files from default profile so all profiles share context |
| **Dashboard model mismatch** — dashboard UI overrode config.yaml model | Manual check required — config.yaml is not the only model source |
| **Token cost from long sessions** | Two-phase workflow + compression threshold = 80% savings |

---

## 🗺️ Next Evolution Plans

### Phase 1 — Immediate (Current)
- [x] Two-phase workflow with "Execute Jarvis" gate
- [x] PMO-style response format with working memory tables
- [x] Kanban→Telegram completion bridge
- [x] Config optimization (smart approvals, compression, curator)
- [x] Hermes brain git repo (this repo)

### Phase 2 — Short Term
- [ ] **Ultron Dashboard** — 3D holographic visualizer showing Jarvis state (agent status, active tasks, system health)
- [ ] **Daily health cron** — automated container + disk + memory check via health profile
- [ ] **Signal digest** — daily summary of trade-copier activity
- [ ] **Weekly AI tool scan** — AI Scout profile scanning for new tools
- [ ] **Session token monitor** — alert when sessions exceed 200K tokens

### Phase 3 — Medium Term
- [ ] **Paper trading** — flip the trade-copier from observe to paper mode
- [ ] **Content automation pipeline** — script generation, asset creation, scheduling
- [ ] **MCP server integrations** — extend Hermes with custom tool servers
- [ ] **Multi-VPS orchestration** — spread agents across machines

### Phase 4 — Long Term
- [ ] **Live trading** — real capital with position caps, kill switch, and full audit trail
- [ ] **Self-improving workflows** — curator auto-optimizes skills based on usage patterns
- [ ] **Mobile dashboard** — Jarvis state on your phone via Ultron web app

---

## 📁 Repository Structure

```
hermes-brain/
├── SOUL.md                    # Agent identity — loaded every session
├── config.yaml                # Hermes configuration (no secrets)
├── .gitignore                 # Blocks secrets, DBs, logs, sessions
├── profiles/                  # Per-role agent identities
│   ├── planner/               # Phase 1 — read-only, minimax, Kanban
│   ├── developer/             # Phase 2 — code, git, skills
│   ├── researcher/            # Deep-dive research, web + browser
│   └── trader/                # MT5 monitoring, observe-only
├── scripts/                   # Automation scripts
│   └── kanban_bridge.py       # Kanban→Telegram completion bridge
├── skills/                    # 22 categories, 500+ files
│   ├── trading/               # Trade-copier pipeline
│   ├── software-development/  # Workflows, debugging, TDD
│   ├── creative/              # Design, media, visualization
│   ├── research/              # arXiv, web scraping, paper writing
│   ├── github/                # PRs, issues, code review
│   └── ... (17 more)
└── trade-copier/
    └── .hermes.md             # Project context for trade-copier
```

---

## 🔐 Security

- **No secrets in this repo.** API keys, tokens, and passwords live in `.env` (excluded by `.gitignore`)
- **Secret redaction** is ON by default in Hermes — API keys are masked in tool output
- **Smart approval mode** — only genuinely dangerous commands prompt for confirmation
- **Least privilege** — each profile has only the tools it needs (trader has no browser, planner has no terminal)

---

## 📝 License

Private — Sam Winston © 2026

---

*Built with [Hermes Agent](https://github.com/NousResearch/hermes-agent) by Nous Research*