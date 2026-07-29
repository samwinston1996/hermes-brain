Image prompt: level-first (SL/ENTRY/TP), ignore non-matching boxes, no-guess directive. Semantic keyword matching (BULLISH SETUP, BEARISH SETUP, VIEW BULLISH/BEARISH).
§
Two-phase: Phase 1 = PMO planning (TODO table, numbered plan). Phase 2 = execution gated by 'Execute Jarvis'. Stop+replan on error.
§
Sam = direct/practical. Findings-first approval. Full container logs. Level-first. Strict 'Execute Jarvis' gate — do NOT forget it.
§
Use patch tool for edits over write_file. Sam cautious about installs/restarts — no unauthorized changes.
§
Before removing code that affects existing functionality: always flag to Sam, explain what else it serves, get explicit approval. Never assume a line is unused without verifying.
§
PMO response: structured analysis, TODO table, numbered plan, end with 'Execute Jarvis'.
§
Timezone: Sam prefers IST (UTC+5:30). Report times in IST by default unless UTC is explicitly requested.
§
Default tool: execute_code (with hermes_tools). Use terminal only for bg processes, PTY, Docker. Switch back after.
§
Strict gate: ONLY 'Execute Jarvis' triggers Phase 2. User corrections/feedback/questions are NOT execution signals.
§
Sam prefers direct execution when I already know the answer. Don't run redundant verification steps — just do the work.
§
Curator: enabled=true, consolidate=false.
§
Host vmi3415001, user=trader, project at ~/workspace/projects/trade-copier from host. Inside Hermes: /opt/data/trade-copier.
§
Profile model: default/dev=deepseek-v4-flash, researcher/planner=minimax-m2.7, trader=deepseek-v4-flash. /compress built-in. Content automation at /opt/data/content-automation/ (private repo).
§
Email (Gmail SMTP): creds in /opt/data/.env. Daily trade review cron at 20:00 UTC (job=78332405e510). Script: send_trade_review.py uses MT5 position_id for exact P&L matching. 9-col signal lifecycle: Telegram time→Channel→Dir→Sym→Lot→MT5 Entry→TP/SL Time→Status→P&L. Week trend + per-channel P&L. IST timezone. Pushed to trade-copier/scripts/.