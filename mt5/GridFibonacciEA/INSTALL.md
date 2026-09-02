# Installing Grid Fibonacci Pro

Five steps. About ten minutes.

You need MetaTrader 5 already installed on a Windows PC (or a Windows VPS).
MT5 is a Windows program — on macOS or Linux it runs under Wine/CrossOver, and
these steps are the same once the terminal is running.

---

## Step 1 — Download the files

Open this link and the ZIP downloads:

<https://github.com/SEROUZCOIN/TelegramChatBot/archive/refs/heads/claude/mt5-grid-robot-fibonacci-opb5ct.zip>

Unzip it. Inside, the folder you need is:

```
TelegramChatBot-claude-mt5-grid-robot-fibonacci-opb5ct\mt5\GridFibonacciEA\
```

That folder holds one `.mq5` file and ten `.mqh` files. **Keep them together** —
the EA is one project split across files, and it will not compile if you copy
only `GridFibonacciEA.mq5`.

## Step 2 — Open the MetaTrader 5 data folder

In MetaTrader 5: **File → Open Data Folder**.

A Windows Explorer window opens. Inside it, go into **`MQL5`**, then
**`Experts`**.

Use this menu rather than typing a path. MT5 stores its data under a hashed
folder name that differs on every machine, and portable installs put it
somewhere else entirely.

## Step 3 — Copy the folder in

Copy the whole **`GridFibonacciEA`** folder into `MQL5\Experts\`.

When you are done it looks like this:

```
MQL5\
  Experts\
    GridFibonacciEA\
      GridFibonacciEA.mq5
      Config.mqh
      Execution.mqh
      Fibonacci.mqh
      Grid.mqh
      Panel.mqh
      Risk.mqh
      Signals.mqh
      State.mqh
      Telemetry.mqh
      Utils.mqh
```

`README.md`, `INSTALL.md` and `install.ps1` come along with the folder too.
They do no harm — MetaEditor ignores anything that is not `.mq5` or `.mqh`.

## Step 4 — Compile

1. In MetaTrader 5 press **F4**, or **Tools → MetaQuotes Language Editor**.
2. In MetaEditor's Navigator on the left, open
   **Experts → GridFibonacciEA → GridFibonacciEA.mq5** (double-click it).
3. Press **F7**.

The Errors tab at the bottom should read **0 errors, 0 warnings**. That creates
`GridFibonacciEA.ex5` next to the source, which is what the terminal runs.

If the Navigator does not show the folder, right-click in the Navigator and
choose **Refresh**.

## Step 5 — Attach it to a chart

1. Back in MetaTrader 5, press **Ctrl+N** to show the Navigator.
2. Open **Expert Advisors**, find **GridFibonacciEA**, and drag it onto a chart
   — the chart's symbol and timeframe are what it will trade.
3. In the dialog that opens, on the **Common** tab, tick
   **Allow Algo Trading**.
4. Click **OK**.
5. On the toolbar, the **Algo Trading** button must be green. If it is red,
   click it once.

A small smiley face appears in the top-right of the chart, and the neon panel
appears on the left. You are running.

---

## Before you let it trade real money

**Use a demo account first.** Every broker offers one, and it uses the same
live prices.

Then run it through the Strategy Tester (**Ctrl+R** in MT5) over at least two
years of history, on **"Every tick based on real ticks"**. `README.md` in this
folder explains what to look for and which inputs to optimise in what order.

This EA has never been run against a broker. It is code that was written and
statically checked, not a track record. Treat the demo run as the real test.

---

## Optional: Telegram alerts and the 3D dashboard

Both send data out over the internet, so MetaTrader has to be told the URLs are
allowed:

**Tools → Options → Expert Advisors → tick "Allow WebRequest for listed URL"**,
then add:

- `https://api.telegram.org` — for Telegram alerts
- `http://127.0.0.1:8050` — for the dashboard on the same PC (or the address of
  whatever machine runs it)

Skipping this is the single most common failure: every request comes back `-1`
with error `4014`, and the EA writes exactly that in the Experts log.

Then in the EA's inputs:

| For | Set |
|---|---|
| Telegram | `InpTelegramOn` = true, `InpTelegramToken`, `InpTelegramChatId` |
| Dashboard | `InpTelemetryOn` = true, `InpTelemetryUrl` = `http://127.0.0.1:8050/ingest` |

To run the dashboard on the same PC you need [Python 3.10+](https://www.python.org/downloads/)
(tick **"Add python.exe to PATH"** in the installer), then:

```powershell
cd tools\dashboard
pip install -r requirements.txt
python app.py --demo
```

Open <http://127.0.0.1:8050>. `--demo` shows you everything with a fake market
so you can check it works before wiring the EA to it; drop `--demo` once the EA
is sending.

---

## Optional: copy the files with one command

Instead of Steps 2 and 3, you can run `install.ps1` (it sits in this folder):
right-click it and choose **Run with PowerShell**. It finds your MetaTrader 5
data folders and copies the project into each one's `MQL5\Experts\`.

You still have to compile (Step 4) and attach (Step 5) yourself.

If Windows blocks the script, run this in PowerShell from inside this folder
instead:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

---

## If something goes wrong

| What you see | What it means |
|---|---|
| `'Config.mqh' cannot open source file` when compiling | The `.mqh` files were not copied. All eleven files must sit in the same folder. |
| The EA is not in the Navigator | Right-click in the Navigator → **Refresh**. If still missing, it did not compile — check the Errors tab in MetaEditor. |
| Smiley face has a small cross next to it | Algo Trading is off. Click the toolbar button, or re-open the EA properties and tick **Allow Algo Trading**. |
| Panel shows but no trades ever open | Normal, and usually correct. The panel's **Regime** row tells you why — `CHOP` opens nothing by design, and `no qualified leg` means no impulse big enough to trade. Check the Experts tab for the EA's own log lines. |
| `WebRequest` error `4014` in the log | The URL is not in the allowed list. See the section above. |
| Error `10030 Unsupported filling mode` | Should not happen — the EA calls `SetTypeFillingBySymbol`. If it does, tell me your broker and symbol. |
