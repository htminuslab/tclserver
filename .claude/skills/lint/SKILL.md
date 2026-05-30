---
name: lint
description: Run Questa Lint on the current VHDL/Verilog/SystemVerilog project via the send-cli bridge to the Tcl CLI server. Use whenever the user asks to lint code, run questa lint, check HDL for lint issues, run lint with a specific methodology (fpga/ip/soc/do-254/iso26262) or goal (start/simulation/implementation/release), generate a lint report, or correct/fix sources based on a previous lint report.
---

# Questa Lint orchestration skill

This skill drives Questa Lint through the `send-cli` bridge so the user never has to hand-author a Tcl script. Every command is sent over the socket as a **single Tcl string** to `send-cli`; the server replies with **one JSON object per call**, one of:

- `{"status":"ok","result":"..."}`
- `{"status":"online"}`
- `{"status":"error","message":"..."}`

`send-cli` is invoked either as `send-cli` (on PATH) or as `.\send-cli`. Parse **every** reply with `ConvertFrom-Json` and branch on `.status` — never string-match raw output. Accept both `ok` and `online` as success.

Run the phases below **in order**. Stop on the first hard failure and surface a clear remediation. Where a step says **decide**, resolve the value locally and send nothing; where it says **send**, issue a `send-cli` call — these are different actions.

---

## Phase 0 — Configuration (resolve first, echo back)

From the user's message and `$ARGUMENTS`, **decide** the following table, then restate the resolved values as a short bullet list before doing anything else. Use the placeholders `<output_dir>`, `<methodology>`, `<goal>`, `<top>` in every command below — never bake an example value into a template.

| Setting       | Source / how to resolve                                   | Default          |
|---------------|-----------------------------------------------------------|------------------|
| `output_dir`  | token after "output"/"out"/`--out=`                       | `./output_lint`  |
| `methodology` | one of `fpga,ip,soc,standard`                             | `fpga`           |
| `goal`        | one of `do-254,iso26262,start,simulation,implementation,release,release_xilinx,release_intel,release_microsemi,release_lattice` | `release` |
| `top` (DUT)   | see Phase C — derived or asked, never guessed from a name | (must be known)  |
| sources       | see Phase D                                               | (must be known)  |

`top` and `sources` are resolved in their phases below; `output_dir`, `methodology`, and `goal` are resolved here.

### Methodology / goal quick-reference

Use this table to map user intent to the correct `methodology` and `goal` values:

| User says                          | `methodology` | `goal`              | Tcl command sent in Phase F                                    |
|------------------------------------|---------------|---------------------|----------------------------------------------------------------|
| "lint according to do-254"         | `standard`    | `do-254`            | `lint methodology standard -goal do-254`                       |
| "lint according to iso26262"       | `standard`    | `iso26262`          | `lint methodology standard -goal iso26262`                     |
| "lint according to Xilinx rules"   | `fpga`        | `release_xilinx`    | `lint methodology fpga -goal release_xilinx`                   |
| "lint according to Intel rules"    | `fpga`        | `release_intel`     | `lint methodology fpga -goal release_intel`                    |
| "lint according to Microsemi rules"| `fpga`        | `release_microsemi` | `lint methodology fpga -goal release_microsemi`                |
| "lint according to Lattice rules"  | `fpga`        | `release_lattice`   | `lint methodology fpga -goal release_lattice`                  |

---

## Phase A — Ensure the server is up

1. **Send** `status`:

   ```powershell
   $resp = .\send-cli "status"
   $j = $resp | ConvertFrom-Json
   ```

   On `$j.status -eq 'ok'` or `$j.status -eq 'online'` → go to Phase B.

2. On no JSON, non-zero exit, or connection refused, **auto-start in the background** (the launcher does **not** return — it must not run in the foreground):

   ```powershell
   Start-Process -FilePath qverify -ArgumentList '-c','-do','scripts/tclserver.tcl' -WindowStyle Hidden 
   ```

   Use the **PowerShell tool** with `run_in_background: true`. Never run `qverify` in the foreground — it does not return.

3. Poll `status` on a **bounded** loop: every ~2 s, up to ~10 attempts.

4. If still down, STOP and tell the user what was tried and to verify `qverify` is on PATH and that `scripts/tclserver.tcl` exists:

   > Tried to auto-start Questa Lint with `qverify -c -do "scripts/tclserver.tcl"` but the Tcl CLI server never came online. Check that `qverify` is on PATH and that `scripts/tclserver.tcl` exists in the current working directory, then re-run `/lint`.

---

## Phase B — Output directory

1. Tell Questa: **send** `configure output directory <output_dir>`. Require `status==ok`; on error surface `.message` and abort (usual cause: path not writeable from Questa's CWD).

---

## Phase C — Determine the DUT / top

Lint needs a top name (`-d <top>`) **in every path, including the `qrun.f` path** — do not skip this. Resolve `top` by this precedence, stopping at the first that applies:

1. **User stated it explicitly** → use it.
2. **Exactly one source file is in play** → read it and take the `entity <name> is` (VHDL) or `module <name>` (Verilog/SV) declaration. Do **not** infer from the filename stem.
3. **Otherwise** use the `ParseRTL` helper to obtain the DUT name:

   ```powershell
   $du = (.\ParseRTL . -u) | ConvertFrom-Json    # -> {"dut":"div"}
   ```

   `ParseRTL` is invoked either as `ParseRTL` (on PATH) or as `.\ParseRTL`. The `.` is the current directory; `-u` returns the DUT name in JSON. If nothing is returned, **ask the user** for the DUT name.

---

## Phase D — Source discovery

Precedence, stop at first match:

1. **Explicit filenames** the user named → use exactly those; verify each exists; if any is missing, abort naming the missing path. Do not glob, do not read a file list.
2. **`qrun.f`** in the project root → compile via qrun (Phase E, qrun path).
3. **`fileList.txt`** in the root → each non-blank, non-`#` line is a source path.
4. **Otherwise** use the `ParseRTL` helper to obtain the file list:

   ```powershell
   $fl = (.\ParseRTL . -f fileList.txt -u) | ConvertFrom-Json   # -> {"dut":"div"}
   ```

   `-f fileList.txt` writes the file list to the current directory and returns the DUT name in JSON. (This also yields a usable `dut` for Phase C if still unknown.)

If zero sources are found, abort with a clear message.

---

## Phase E — Compile

Issue the initial compile command based on the source path in use:

- **qrun.f path:** **send** `qrun -compile -quiet -outdir . -f qrun.f`
- **fileList.txt path:** **send** `qrun -compile -quiet -outdir . -f fileList.txt`

After the compile command, run the following **two-gate check** (both must pass before advancing to Phase F):

**Gate 1 — send-cli reply:** require `status==ok` and `.result` must not contain `** Error`. If either fails, print the message and **STOP**.

**Gate 2 — `qrun.log` inspection:**

```powershell
if (Test-Path "qrun.log") {
    $logLines = Get-Content "qrun.log"
    $errorLines = $logLines | Where-Object { $_ -match '\*\* Error' }
    if ($errorLines) {
        # Check specifically for a missing-library error
        $libError = $errorLines | Where-Object { $_ -match 'Library\s+"([^"]+)"\s+not found' }
        if ($libError) {
            # Extract the library name from the first such error
            $libError[0] -match 'Library\s+"([^"]+)"\s+not found' | Out-Null
            $missingLib = $Matches[1]
            Write-Host "Missing library '$missingLib' detected — issuing vmap then retrying compile"
            $vmapResp = .\send-cli "vmap $missingLib work"
            $vmapJ = $vmapResp | ConvertFrom-Json
            if ($vmapJ.status -ne 'ok') {
                Write-Host "vmap failed: $($vmapJ.message)"
                # STOP
            }
            # Retry compile (use whichever file-list form was used originally):
            # qrun.f path:       $retryResp = .\send-cli "qrun -compile -quiet -outdir . -f qrun.f"
            # fileList.txt path: $retryResp = .\send-cli "qrun -compile -quiet -outdir . -f fileList.txt"
            # Then re-run both gates on the retry result; if the retry still fails, STOP.
        } else {
            # Non-library errors — report and stop
            Write-Host "Compile errors found in qrun.log — lint cannot continue:"
            $errorLines | ForEach-Object { Write-Host "  $_" }
            # STOP — do not proceed to Phase F
        }
    }
} else {
    Write-Host "Warning: qrun.log not found in current directory — cannot verify compile output."
}
```

**Missing-library retry rules:**
- Extract the library name from the regex group `Library "([^"]+)" not found`.
- **Send** `vmap <missingLib> work` then re-run the compile step.
- Re-run **both gates** on the retry. If the retry still shows errors in `qrun.log`, **STOP** and report all remaining error lines — do not retry more than once per library.
- Only the missing-library pattern triggers a retry. Any other `** Error` line stops the run immediately.

---

## Phase F — Apply methodology & goal

**Send** `lint methodology <methodology> -goal <goal>` — require `status==ok`.

---

## Phase G — Run lint

**Send** `lint run -d <top>` — require `status==ok`. Surface a one-line summary of `.result`. Common failure: unknown top → re-prompt for `<top>` (Phase C).

---

## Phase H — Generate & locate the report

1. **Send** `lint generate report` — require `status==ok`.
2. The report is written under `<output_dir>` as `lint.rpt` (a consequence of Phase B step 2).
3. If `<output_dir>/lint.rpt` is missing, retry with an explicit path: **send** `lint generate report -file <output_dir>/lint.rpt`. If still missing, ask the user to check Questa's actual CWD (it may differ from the shell CWD).

---

## Phase I — Summarize for the user

Read `<output_dir>/lint.rpt` and emit ≤25 lines: total errors, total warnings, top rule IDs by count, and the unique offending files. Flag errors prominently; a warnings-only run is still a successful run. Offer to dump the full report or proceed to fixes (Phase J).

---

## Phase J — Fix sources (only on explicit request)

Triggered only by "correct/fix the sources", "apply the report fixes", etc.

1. Re-read `<output_dir>/lint.rpt`; group findings by file (rule + line + message).
2. Propose concrete edits with exact before/after.
3. **Wait for user approval before editing** (unless told "apply all"). Never write to source files unprompted.
4. After edits, suggest re-running the skill to confirm the design is clean.

---

## Shutdown

Do **not** auto-exit the server by default — the user may want to re-lint after fixes or run again. Only **send** `exit` when the user asks to close Questa, or after confirming they are done.

---

## PowerShell / quoting rules (Windows, PS 5.1)

**All commands in this skill run through the PowerShell tool exclusively.** Do not use Bash; Bash cannot parse Windows PowerShell syntax (`ConvertFrom-Json`, `Get-ChildItem`, `$variables`, etc.).

- Wrap each Tcl command as one **double-quoted** argument: `send-cli "qrun -compile -quiet -f qrun.f"`. Single quotes would send a literal `$file` to Tcl.
- Convert `\` → `/` in paths before embedding (`-replace '\\','/'`); Tcl escapes `\` inside `"..."`.
- Capture stdout directly (`$resp = send-cli "..."`). Do **not** redirect `2>&1` — PS 5.1 wraps stderr as an ErrorRecord and flips `$?`, falsely signalling failure.
- Do **not** chain with `&&`/`||` (parser error on PS 5.1). Sequence with `;` and explicit `if ($j.status -ne 'ok') { ... }` guards.
- Reject paths containing spaces with a clear message rather than trying to escape them.
- **Variable followed by a colon in a string:** PS 5.1 treats `$var:` as a drive/scope prefix and raises a parse error. Always wrap the variable in `${}` or `$()`: use `"Attempt ${attempt}: ..."` or `"Attempt $($attempt): ..."`, never `"Attempt $attempt: ..."`. Apply this rule to every interpolated string where a variable is immediately followed by a literal colon.

---

## Error-handling matrix

| Condition                                  | Behaviour                                              |
|--------------------------------------------|--------------------------------------------------------|
| `send-cli` non-zero exit / no JSON         | Treat as server down → Phase A remediation → abort.    |
| `configure output directory` → error       | Abort; surface `.message` (likely not writeable).      |
| compile → error / `** Error` in result     | Print file + message; abort the chain.                 |
| `qrun.log` — missing library error         | Extract lib name; retry once proceding the compile command with `vmap <lib> work`; if retry still fails, abort. |
| `qrun.log` — any other `** Error`          | Print each error line; abort — lint cannot continue.   |
| `qrun.log` missing after compile           | Warn user; continue only if send-cli reply was clean.  |
| `lint run` → error                         | Abort report; surface message; re-prompt for `<top>`.  |
| `lint.rpt` present, warnings only          | Success; summarize; offer Phase J.                     |
| `lint.rpt` present, errors                 | Same flow, flag prominently.                           |
| `lint.rpt` missing after success           | Try `-file` override; else ask user to check Questa CWD.|

---

## One-time setup note

To avoid a permission prompt on every call, suggest adding to `permissions.allow` in `.claude/settings.local.json`:

```json
"PowerShell(.\send-cli *)",
"PowerShell(.\ParseRTL *)",
"PowerShell(New-Item -ItemType Directory -Force *)"
```

**Note:** All commands in this skill run through the **PowerShell tool** only. Do not use Bash for this skill; Windows PowerShell syntax (ConvertFrom-Json, Get-ChildItem, Start-Process, etc.) will not parse in Bash.
