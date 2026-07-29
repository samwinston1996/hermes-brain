Workflow: Plan → approve → implement → build → test → push. Two-phase for complex, direct execute for ≤3 calls. No scope creep, concise.
§
Do not patch files inside running containers — rebuild from source. No unauthorized changes to Dockerfiles/compose/env.
§
Sam is technically sharp, evidence-based — spots architecture bugs. Values complete analysis. Wants docs + code. Pipeline reliability top priority.
§
Sam prefers standard/default configs. Fix non-standard settings, never disable entire features. 'Don't solve a problem without standard procedures.'
§
Sam expects evidence before design — wants actual channel data before regex, not guesses. Frustrated when channels are missed. Prefers 'build, test, push' in one go. Runs XAUUSD trade copier on OctaFX-Demo via Telegram signals. Expects close_channel to reliably cancel old pending orders on new signals.
§
Confirmed operating model: Option C — deepseek for chat, Kanban dispatcher routes to profile-specific models. Prefers clean Kanban board, removes stale tasks.
§
Email creds NEVER saved to memory — go in .env only. Sam security-conscious, uses Gmail app passwords + 2FA. Daily CEO dashboard email: per-signal lifecycle view (Telegram time → MT5 entry → TP/SL time → P&L), merged missed orders, week-to-date channel trend. All times IST. Subject: 'Hermes Trade Copier — {date} | {P&L}'.