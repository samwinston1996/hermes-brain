# 🧠 JARVIS — The Self-Evolving AI Organism

> *Not a chatbot. Not a tool. A living system that writes its own code, hires its own workforce, and manages everything — 24/7, on a $40/month VPS.*

---

## What is JARVIS?

JARVIS is a **self-evolving AI organism** — a metacognitive system that knows what it doesn't know, modifies its own code, installs its own tools, and delegates work to specialized sub-agents.

While most AI agents are single-purpose chatbots or code assistants, JARVIS is a **persistent, autonomous workforce** that:

- 🧠 **Thinks** — Plans before acting, researches before building, validates before deploying
- 🔧 **Evolves** — Writes new skills, patches old ones, consolidates knowledge
- 👥 **Delegates** — Spawns specialist agents (Planner, Developer, Researcher, Trader) for parallel work
- 💾 **Remembers** — Cross-session memory, durable skill library, project context
- ⏰ **Schedules** — Runs 24/7 cron tasks with zero-token cost when idle
- 📊 **Observes** — Monitors trading pipelines, system health, and itself

It runs on a **$40/month VPS** — a fraction of what a single Claude Code session costs per hour — and was designed from day one to operate within those constraints.

---

## 🛠️ The Tech Stack — Engineered for Efficiency

### Hardware Foundation

| Component | Spec | Why |
|-----------|------|-----|
| **VPS** | $40/month cloud instance | Full root access, 24/7 uptime, Docker support |
| **RAM** | 8 GB | Enough for Hermes + MT5 + 4 pipeline containers |
| **Storage** | 80 GB SSD | Skills, sessions, Kanban DB, Docker images |
| **OS** | Linux (Ubuntu 24.04) | Docker-native, low overhead, cron-ready |
| **Python** | 3.11 | Hermes Agent runtime |
| **Node.js** | 20.x | For web dashboards (Ultron) |

### Agent Framework

| Layer | Technology | Why |
|-------|-----------|-----|
| **Core** | [Hermes Agent](https://github.com/NousResearch/hermes-agent) by Nous Research | Open-source, self-improving, pluggable — the only agent framework with built-in skill curation, cross-session memory, and cron |
| **Planning** | MiniMax M2.7 via OpenRouter | 205K context, 2-8× cheaper than alternatives — perfect for broad-context planning sessions |
| **Execution** | DeepSeek V4 Flash via OpenRouter | 1.05M context, strong reasoning — handles code, trading logic, system changes |
| **Vision** | Google Gemini 2.0 Flash via OpenRouter | Fast, cheap image analysis for chart signals |
| **Provider** | OpenRouter | Single API key, automatic failover, model routing — no vendor lock-in |

### Infrastructure

| Component | Choice | Why |
|-----------|--------|-----|
| **Containerization** | Docker Compose | Lightweight, reproducible, rebuild-from-source |
| **Trading Terminal** | MetaTrader 5 (Wine/Docker) | Industry standard for Forex, OctaFX demo |
| **Message Gateway** | Hermes Gateway (Telegram + API) | Real-time messaging, webhook support |
| **Task Queue** | Kanban (SQLite) | Durable, async, dispatcher-spawned profiles |
| **Automation** | Cron (Hermes-native) | Zero-token `no_agent` mode — runs for free |
| **Version Control** | GitHub (private repos) | Source of truth for brain + trade-copier |

---

## 🏗️ Architecture

### The Self-Evolving File System

JARVIS grows directly on disk. Every skill it writes, every profile it creates, every task it completes becomes part of its permanent memory:

```
$HOME/
├── .hermes/
│   ├── SOUL.md              # Identity — who JARVIS is
│   ├── config.yaml          # Configuration — how JARVIS runs
│   ├── .env                 # Secrets — API keys, tokens
│   ├── skills/              # Procedural memory — 500+ skills, growing daily
│   │   ├── trading/         #   Trade-copier pipeline knowledge
│   │   ├── software-development/  #   Workflows, debugging, TDD
│   │   ├── creative/        #   Design, media, visualization
│   │   └── ...              #   22+ categories
│   ├── profiles/            # Workforce identities
│   │   ├── planner/         #   Phase 1 — read-only, MiniMax
│   │   ├── developer/       #   Phase 2 — code, DeepSeek
│   │   ├── researcher/      #   Deep-dive, web + browser
│   │   └── trader/          #   MT5, observe-only
│   ├── cron/                # Scheduled tasks (zero-tick scripts)
│   ├── scripts/             # Automation scripts
│   ├── kanban.db            # Task queue
│   ├── state.db             # Session history
│   └── memories/            # Cross-session facts
├── trade-copier/            # Production trading pipeline
│   ├── router/              # Signal routing + LLM parsing
│   ├── bridge/              # MT5 bridge + order management
│   ├── listener/            # Telegram channel monitoring
│   └── mt5/                 # MetaTrader 5 terminal
└── hermes-brain/            # ← You are here
    └── README.md
```

### The Workforce

```ascii
                        ┌──────────────┐
                        │   JARVIS     │
                        │   (CEO)      │
                        │ DeepSeek V4  │
                        └──────┬───────┘
                               │ delegates
              ┌────────────────┼────────────────┐
              │                │                 │
       ┌──────┴──────┐  ┌─────┴──────┐  ┌──────┴──────┐
       │   Planner   │  │ Developer  │  │ Researcher  │
       │  MiniMax    │  │ DeepSeek   │  │  MiniMax    │
       │ Read-only   │  │ Code+Git   │  │ Web+Browser │
       │ Kanban spec │  │ Skills     │  │ Synthesis   │
       └─────────────┘  └────────────┘  └─────────────┘
              │
       ┌──────┴──────┐
       │   Trader    │
       │ DeepSeek    │
       │ MT5+Observe │
       └─────────────┘
```

### Design Principle: Right Tool for Each Job

> *"Don't use computer vision and mouse clicks to do something an API can do directly."*

This philosophy drove every architecture decision:

| Task | Tool | Why not something else |
|------|------|----------------------|
| Reading trading signals | LLM (text + vision API) | Faster, cheaper, more reliable than browser automation |
| Code changes | `patch` + `git` | Direct file manipulation, not sed/awk workarounds |
| Task management | Kanban (SQLite) | No external service, no latency, works offline |
| System health | Cron + shell scripts | Zero token cost vs. spawning an agent |
| Research | Web search + browser tools | Structured data, not pixel scraping |
| Browser automation | (Future: OpenClaw/Codex) | When APIs don't exist — broker portals, website management |

---

## 🏆 What Makes JARVIS Different

### vs. Claude Code / Codex / OpenClaw

| Capability | Claude Code | Codex | JARVIS |
|-----------|------------|-------|--------|
| **Persistent memory** | Session-only | Session-only | ✅ Cross-session (SQLite + files) |
| **Multi-agent workforce** | ❌ No | ❌ No | ✅ 4 specialist profiles + CEO |
| **Scheduled tasks** | ❌ No | ❌ No | ✅ Cron with zero-token `no_agent` mode |
| **Skill curation** | ❌ No | ❌ No | ✅ Auto-consolidates, archives, prunes |
| **Message platforms** | CLI only | CLI only | ✅ Telegram, API, 20+ platforms |
| **Provider-agnostic** | Anthropic only | OpenAI only | ✅ 20+ providers, auto-failover |
| **Self-modification** | Manual | Manual | ✅ Writes skills, patches itself, installs tools |
| **24/7 operation** | ❌ No | ❌ No | ✅ VPS-hosted, watchdog-protected |
| **Token budget control** | ❌ No | ❌ No | ✅ Compression threshold, two-phase workflow, model routing |
| **Cost** | ~$3-10/hr | ~$2-8/hr | **~$40/month all-in** |

### The Three Pillars of a Self-Evolving AI

1. **Metacognition** — JARVIS knows what it doesn't know. When it encounters an unfamiliar task, it researches first, plans second, executes third. It flags uncertainty rather than guessing.

2. **Self-modification** — JARVIS writes its own skills, patches outdated knowledge, and installs new tools. The curator runs in the background, consolidating overlapping skills and archiving stale ones. The file system grows with every session.

3. **Delegation** — JARVIS hires sub-agents. The Planner researches and specs. The Developer builds and deploys. The Researcher investigates and synthesizes. The Trader monitors and validates. The CEO orchestrates.

---

## ⚡ Evolutionary Challenges (That Made Us Stronger)

Building a persistent AI organism on a $40/month VPS meant we couldn't throw money at problems. Every constraint became an innovation.

### The Token Budget Problem
| Challenge | Solution |
|-----------|----------|
| Long sessions cost ~$0.50-1.00 each | **Two-Phase Workflow** — Plan (cheap MiniMax) → Execute (DeepSeek). Saves ~80% on tokens |
| Context windows hit 700K+ tokens | **Compression threshold at 35%** — compress earlier, keep sessions lean |
| Every planning session burned tokens | **Read-only Phase 1** — no tool execution overhead during planning |

### The Resource Constraint
| Challenge | Solution |
|-----------|----------|
| Only 8 GB RAM on VPS | **Docker Compose** — lightweight containers, rebuild-from-source, no heavy VMs |
| $40/month total budget | **Model routing** — MiniMax for planning ($0.15/M), DeepSeek for execution ($0.40/M) |
| 80 GB SSD | **Database pruning** — session cleanup, log rotation, git-based artifact storage |

### The Reliability Problem
| Challenge | Solution |
|-----------|----------|
| Containers crash, API keys expire | **Kanban→Telegram bridge** — completions surface to DM automatically |
| Execution silently diverges from plan | **"Execute Jarvis" gate** — any error stops, re-plans, requires fresh approval |
| Can't monitor 24/7 manually | **Zero-token cron** — `no_agent` mode scripts that only fire when there's something to report |

### The Knowledge Growth Problem
| Challenge | Solution |
|-----------|----------|
| 500+ skills, hard to maintain | **Curator consolidation** — auto-merges overlapping skills |
| New AI tools appear weekly | **AI Tool Scout** (planned) — weekly scan + integration proposals |
| Profile memory isolation | **Symlinked memory** — all profiles share context |

---

## 🗺️ One-Year Evolution Plan

### ✅ Phase 1 — Foundation (Complete)
- [x] Telegram gateway — real-time messaging with JARVIS
- [x] Hermes signal parsing — text + image-based trading signals
- [x] MT5 execution pipeline — observe-only, guardrails, kill switch
- [x] Two-Phase Workflow — Plan → Execute with "Execute Jarvis" gate
- [x] Multi-agent workforce — Planner, Developer, Researcher, Trader
- [x] Kanban task queue with auto-dispatcher
- [x] Smart approval mode — low-risk commands auto-approved
- [x] Context compression at 35% threshold
- [x] SOUL.md identity, memory, user profile, all profiles ready
- [x] Hermes brain git repo — version-controlled identity

### 🔄 Phase 2 — Self-Monitoring (Next)
- [ ] **Docker container monitoring** — automated health checks, restart on crash
- [ ] **Log summarization** — daily digest of router/bridge/listener logs
- [ ] **Automatic health reports** — systemd, disk, memory, uptime → Telegram DM
- [ ] **Trade analytics** — daily win/loss, signal accuracy, channel performance
- [ ] **Kill switch watch** — monitor trigger conditions, auto-alert on anomaly

### 🚀 Phase 3 — Developer Experience
- [ ] **Code understanding** — full repo semantic search across trade-copier + hermes-brain
- [ ] **Git integration** — auto-commit summaries, PR descriptions, changelog generation
- [ ] **Documentation generation** — skills auto-document their interfaces
- [ ] **Configuration audits** — detect drift between repo and production configs
- [ ] **Automated testing** — pre-deploy test suite for router/bridge/listener

### 🌐 Phase 4 — Content & Research
- [ ] **YouTube content pipeline** — script generation, asset creation, scheduling
- [ ] **Browser automation** — OpenClaw/Codex for broker portals, website management
- [ ] **Personal assistant skills** — calendar, email, research synthesis
- [ ] **AI Tool Scout** — weekly scan for new AI tools, frameworks, models
- [ ] **Agent Tutor** — teaches you how the system works, cross-references against installed stack

### 🧠 Phase 5 — True Autonomy
- [ ] **Multi-agent orchestration** — agents spawn agents, parallel workstreams
- [ ] **Long-term memory** — hierarchical memory: working → short-term → archived
- [ ] **Workflow planning** — JARVIS proposes improvements, not just executes tasks
- [ ] **Human approval for sensitive actions** — graduated trust levels per domain
- [ ] **Self-optimizing model routing** — picks the cheapest capable model per task
- [ ] **Weekly AI ecosystem audit** — finds better tools/services, proposes upgrades
- [ ] **Ultron dashboard** — 3D holographic visualizer of JARVIS state

---

## 🧪 Weekly AI Ecosystem Optimization

One of the most powerful planned capabilities is the **AI Tool Scout** — a weekly agent that:

1. **Scans** — searches for new AI tools, models, frameworks published that week
2. **Evaluates** — cross-references against the current stack
3. **Proposes** — suggests upgrades if a new tool is cheaper, faster, or more capable
4. **Tutors** — explains the new capability and how it fits into JARVIS

This keeps the system constantly evolving — the best tool for each job, always.

---

## 📁 Repository Structure

```
hermes-brain/
├── SOUL.md                    # Agent identity — who JARVIS is
├── config.yaml                # Hermes configuration (no secrets)
├── .gitignore                 # Blocks secrets, DBs, logs, sessions
├── profiles/                  # Workforce identities
│   ├── planner/               # Phase 1 — read-only, MiniMax, Kanban
│   ├── developer/             # Phase 2 — code, DeepSeek, skills
│   ├── researcher/            # Deep-dive, web + browser
│   └── trader/                # MT5 monitoring, observe-only
├── scripts/                   # Automation (no-agent cron)
│   └── kanban_bridge.py       # Task completion → Telegram bridge
├── skills/                    # Procedural memory — 22 categories
│   ├── trading/               # Trade-copier pipeline
│   ├── software-development/  # Workflows, debugging, TDD
│   ├── creative/              # Design, media, visualization
│   ├── research/              # arXiv, web scraping, paper writing
│   └── ... (18 more categories)
└── trade-copier/
    └── .hermes.md             # Project context
```

---

## 🔐 Security Model

- **Least privilege** — Trader has terminal + memory only. Planner has no terminal. Developer has full stack.
- **Secret redaction** — API keys masked in tool output by default
- **Smart approvals** — low-risk commands auto-approved, dangerous ones prompt you
- **"Execute Jarvis" gate** — every execution starts with explicit approval
- **No secrets in git** — `.env` and `*.db` in `.gitignore`

---

*Built with [Hermes Agent](https://github.com/NousResearch/hermes-agent) by Nous Research — the open-source framework that makes self-evolving AI possible.*

*Running 24/7 on a $40/month VPS, proving you don't need enterprise budgets for enterprise AI.*