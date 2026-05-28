---
name: lint
description: Run Questa Lint on the current VHDL/Verilog/SystemVerilog project via the send-cli bridge to the Tcl CLI server. Use whenever the user asks to lint code, run questa lint, check HDL for lint issues, run lint with a specific methodology (fpga/ip/soc/do-254/iso26262) or goal (start/simulation/implementation/release), generate a lint report, or correct/fix sources based on a previous lint report at output_lint/lint.rpt.
---

# Questa Lint orchestration skill

This skill drives Questa Lint through the `send-cli` bridge so the user does not have to hand-author a Tcl script. Every command goes over the socket as a single Tcl string; the server replies with one JSON object per call: `{"status":"ok","result":"..."}`, `{"status":"online"}`, or `{"status":"error","message":"..."}`.

Run the phases below in order. Stop on the first hard failure and surface a clear remediation.

## Phase 0 — Parse the request

From the user message (and `$ARGUMENTS` if invoked via `/lint <args>`), extract:

- **output_dir** — token after "output", "out", or `--out=`. Default `./output_lint`.
- **methodology** — one of `fpga|ip|soc|do-254|iso26262`. Default `fpga`.
- **goal** — one of `start|simulation|implementation|release`. Default `release`.
- **explicit_sources** — any source filenames the user names directly (e.g. "please lint div.vhd" → `div.vhd`). These short-circuit Phase 3 discovery.
- **top** — top-level entity (VHDL) or module (Verilog). If the user named exactly one explicit source, derive `top` by reading the file (the `entity <name> is` for VHDL, or `module <name>` for Verilog/SV) — do **not** guess from the filename stem. Otherwise, if not given, **ASK the user**.

Echo the resolved configuration as a short bullet list before doing anything else.

## Phase 1 — Status check (auto-start if needed)

Run:

```powershell
$resp = send-cli status
$j = $resp | ConvertFrom-Json
```

Accept `$j.status -eq 'ok'` or `$j.status -eq 'online'` → proceed to Phase 2.

On anything else (no JSON, non-zero exit, connection refused), **auto-start Questa Lint**:

1. Launch `qverify` in the background — it will source the Tcl CLI server script and start listening:

   ```powershell
   Start-Process -FilePath qverify -ArgumentList '-c','-do','tclserverw.tcl' -WindowStyle Hidden
   ```

   (Use the `Bash` tool's `run_in_background: true` if PowerShell's `Start-Process` is not preferred — never run `qverify` in the foreground, it does not return.)

2. Poll `send-cli status` until it returns `ok`/`online`, up to ~30 seconds (e.g. retry every 2s for 15 attempts).

3. If the server still does not come up, STOP and tell the user:

   > Tried to auto-start Questa Lint with `qverify -c -do "tclserverw.tcl"` but the Tcl CLI server never came online. Check that `qverify` is on PATH and that `tclserverw.tc` exists in the current working directory, then re-run `/lint`.

## Phase 2 — Output directory

1. Create the host-side folder so we can read the report later:

   ```powershell
   New-Item -ItemType Directory -Force -Path $output_dir | Out-Null
   ```

2. Tell Questa about it:

   ```powershell
   $resp = send-cli "configure output directory $output_dir"
   ```

   Verify `$j.status -eq 'ok'`. On error, surface `$j.message` and abort — usually the path is not writable from Questa's CWD.

## Phase 3 — Source discovery

Precedence (stop at the first match — do not fall through):

1. **Explicit filenames from the user** (from Phase 0 `explicit_sources`). If the user named one or more files (e.g. "please lint div.vhd"), use exactly that list. Do **not** look for `filelist.txt` and do **not** glob the CWD. Verify each file exists; if any is missing, abort with the missing path.
2. If `filelist.txt` exists in CWD, read it. Skip blank lines and lines beginning with `#`. Each remaining line is a source path.
3. Otherwise glob the CWD (non-recursive) for `*.vhd`, `*.vhdl`, `*.v`, `*.sv`.

Print the resulting list back to the user with inferred language (vcom vs vlog) per file. If zero files are found, abort with: "No source files found in CWD and no filelist.txt present. Add files or create filelist.txt."

When the source list came from case 1 and exactly one file was named, also echo the `top` derived from that file (see Phase 0) so the user can correct it before Phase 6.

## Phase 4 — Per-file compile

For each discovered source, dispatch by extension:

| Extension       | Command                                  |
|-----------------|-------------------------------------------|
| `.vhd`, `.vhdl` | `send-cli "vcom -quiet -2008 <path>"`           |
| `.v`, `.sv`     | `send-cli "vlog -quiet <path>"`           |

Parse the JSON after each call. If `$j.status -eq 'error'` (or `$j.result` contains `** Error`), print the offending file and the message, then **STOP**. A failed compile invalidates the lint run.

## Phase 5 — Methodology & goal

```powershell
$resp = send-cli "lint methodology $methodology -goal $goal"
```

Verify `$j.status -eq 'ok'`.

## Phase 6 — Run lint

```powershell
$resp = send-cli "lint run -d $top"
```

Verify `$j.status -eq 'ok'`. Surface a one-line summary of `$j.result` to the user (e.g. the elapsed-time or rule-count line if Questa emits one).

## Phase 7 — Generate report

```powershell
$resp = send-cli "lint generate report"
```

Verify `$j.status -eq 'ok'`.

## Phase 8 — Summarize the report

Read `$output_dir/lint.rpt`.

- If missing, try the explicit form:

  ```powershell
  send-cli "lint generate report -file $output_dir/lint.rpt"
  ```

  If still missing, ask the user to check Questa's actual working directory — the report may have landed elsewhere if Questa's CWD differs from the shell CWD.

- If present, emit ≤25 lines: total errors, total warnings, top-5 rule IDs by count, and the list of unique offending files. Offer to dump the full report or jump to Phase 9.

## Phase 9 — Fix sources (only on explicit user request)

Triggered when the user says things like "correct the source files", "fix the lint issues", "apply the report fixes".

1. Re-read `$output_dir/lint.rpt`.
2. Group findings by file. For each file, summarize rule + line + message.
3. For each file, propose concrete edits using the Edit tool with exact before/after.
4. **Wait for explicit user approval before each edit** (unless the user has said "apply all").
5. After edits, suggest re-running `/lint` to confirm the design is clean.

Never write to source files without confirmation.

---

## send-cli quoting rules (Windows PowerShell)

- Always wrap the Tcl command as one **double-quoted** argument: `send-cli "vcom -quiet $file"`. Single quotes would send a literal `$file` to Tcl.
- Convert backslashes to forward slashes in paths before embedding (`$file = $file -replace '\\','/'`) — Tcl treats `\` as an escape inside `"..."`.
- Reject paths containing spaces with a clear message rather than trying to escape them.
- Capture stdout directly: `$resp = send-cli "..."`. Do NOT redirect `2>&1` — PowerShell 5.1 wraps stderr as an ErrorRecord and flips `$?`, falsely signalling failure.
- Do NOT chain with `&&` / `||` (parser error on PS 5.1). Sequence with `;` and explicit `if ($j.status -ne 'ok') { ... }` guards.
- Parse responses with `$j = $resp | ConvertFrom-Json`. Never grep the raw string.

## Error-handling matrix

| Condition                                       | Behaviour                                                                |
|-------------------------------------------------|---------------------------------------------------------------------------|
| `send-cli` non-zero exit / no JSON              | Treat as server down; print remediation from Phase 1; abort.              |
| `configure output directory` returns error      | Abort; surface `$j.message`. Likely cause: path not writable from Questa. |
| `vcom`/`vlog` returns error                     | Print file + message; abort the chain.                                    |
| `lint run` returns error                        | Abort report; surface message. Common cause: unknown top-level — re-prompt. |
| `lint.rpt` exists, warnings only                | Treat as success; summarize; offer Phase 9.                               |
| `lint.rpt` exists, errors present               | Same flow but flag prominently.                                           |
| `lint.rpt` missing after success                | Try the `-file` override; else ask user to check Questa's CWD.            |

## Setup (one-time)

To avoid a permission prompt on every `send-cli` call, add these entries to `permissions.allow` in `.claude/settings.local.json`:

```json
"PowerShell(send-cli *)",
"Bash(send-cli *)",
"PowerShell(New-Item -ItemType Directory -Force *)"
```
