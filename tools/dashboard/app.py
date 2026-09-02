"""Grid Fibonacci Pro — 3D control room.

Run it:

    python app.py --demo                     # synthetic feed, no terminal needed
    python app.py                            # wait for EA telemetry on /ingest
    python app.py --mt5 --symbol EURUSD      # read a local MT5 terminal directly
    python app.py --ingest-key SECRET        # require the EA's X-Ingest-Key

Then open http://127.0.0.1:8050.

To feed it from the EA, set InpTelemetryOn = true, point InpTelemetryUrl at
http://<this machine>:8050/ingest, and allow that URL in
MetaTrader 5 > Tools > Options > Expert Advisors > Allow WebRequest.
"""

from __future__ import annotations

import argparse
import os
from typing import Any, Dict, List

from dash import Dash, Input, Output, dcc, html
from flask import Flask, jsonify, request

import figures as F
import theme as T
from sources import DemoFeed, MT5Feed
from store import STORE

REFRESH_MS = 1000
INGEST_KEY = os.environ.get("GFEA_INGEST_KEY", "")

server = Flask(__name__)
app = Dash(__name__, server=server, title="Grid Fibonacci Pro · Control Room",
           update_title=None, suppress_callback_exceptions=True)


# ---------------------------------------------------------------------------
# Ingest endpoint — where the EA's telemetry lands
# ---------------------------------------------------------------------------
@server.route("/ingest", methods=["POST"])
def ingest():
    if INGEST_KEY and request.headers.get("X-Ingest-Key", "") != INGEST_KEY:
        return jsonify({"error": "unauthorised"}), 401

    payload = request.get_json(force=True, silent=True)
    if not isinstance(payload, dict):
        return jsonify({"error": "expected a JSON object"}), 400

    STORE.update(payload, source="ea")
    return jsonify({"ok": True}), 200


@server.route("/health", methods=["GET"])
def health():
    age = STORE.age_seconds()
    return jsonify({
        "ok": True,
        "feed": STORE.snapshot().get("source", "none"),
        "seconds_since_snapshot": round(age, 2) if age is not None else None,
    }), 200


# ---------------------------------------------------------------------------
# Layout helpers
# ---------------------------------------------------------------------------
def tile(tile_id: str, label: str) -> html.Div:
    return html.Div(className="tile", children=[
        html.Div(label, className="tile-label"),
        html.Div("--", id=f"tile-{tile_id}", className="tile-value"),
        html.Div("", id=f"tile-{tile_id}-sub", className="tile-sub"),
    ])


def card(title: str, *children, className: str = "") -> html.Div:
    body = [html.Div(title, className="card-title")] if title else []
    body.extend(children)
    return html.Div(body, className=f"card {className}")


def graph(graph_id: str, height: int) -> dcc.Graph:
    return dcc.Graph(
        id=graph_id,
        config={"displayModeBar": False, "scrollZoom": True, "responsive": True},
        style={"height": f"{height}px"},
    )


app.layout = html.Div(className="shell", children=[
    dcc.Interval(id="tick", interval=REFRESH_MS, n_intervals=0),

    html.Div(className="topbar", children=[
        html.Div(className="brand", children=[
            html.Div(className="pulse", id="status-led"),
            html.Div([
                html.Div("GRID FIBONACCI PRO", className="brand-name"),
                html.Div("3D CONTROL ROOM", className="brand-sub"),
            ]),
        ]),
        html.Div(id="topbar-instrument", className="instrument"),
        html.Div(id="topbar-status", className="status"),
    ]),

    html.Div(id="banner", className="banner hidden"),

    html.Div(className="tiles", children=[
        tile("equity", "EQUITY"),
        tile("day", "DAY P/L"),
        tile("floating", "BASKET FLOATING"),
        tile("dd", "DRAWDOWN"),
        tile("levels", "LADDER"),
        tile("regime", "REGIME"),
        tile("winrate", "CYCLES / WIN RATE"),
        tile("spread", "SPREAD"),
    ]),

    html.Div(className="grid-2", children=[
        card("", graph("fig-ladder", 430)),
        card("", graph("fig-surface", 430)),
    ]),

    html.Div(className="grid-2", children=[
        card("", graph("fig-terrain", 430)),
        card("", graph("fig-fib", 430)),
    ]),

    html.Div(className="grid-2", children=[
        card("", graph("fig-equity", 260)),
        html.Div(className="stack", children=[
            card("", graph("fig-gauges", 190)),
            card("", graph("fig-pressure", 150)),
        ]),
    ]),

    html.Div(className="grid-2", children=[
        card("GRID LEVELS", html.Div(id="level-table", className="table-wrap")),
        card("EVENT LOG", html.Div(id="event-log", className="log-wrap")),
    ]),

    html.Div("Grid Fibonacci Pro · telemetry dashboard · figures update every "
             f"{REFRESH_MS} ms", className="footer"),
])


# ---------------------------------------------------------------------------
# Rendering helpers
# ---------------------------------------------------------------------------
def level_rows(snap: Dict[str, Any]) -> Any:
    levels = F.open_levels(snap)
    digits = int(snap["market"].get("digits", 5))
    if not levels:
        return html.Div("no open levels", className="empty")

    header = html.Tr([html.Th(h) for h in
                      ("LVL", "TICKET", "PLANNED", "FILL", "LOTS", "P/L")])
    rows = [header]
    for lv in levels:
        pl = float(lv.get("pl", 0.0))
        rows.append(html.Tr([
            html.Td(f"L{lv['level']}"),
            html.Td(str(lv.get("ticket", "-"))),
            html.Td(f"{float(lv.get('requested', 0.0)):.{digits}f}"),
            html.Td(f"{float(lv.get('filled', 0.0)):.{digits}f}"),
            html.Td(f"{float(lv.get('lots', 0.0)):.2f}"),
            html.Td(f"{pl:+.2f}", style={"color": T.pl_color(pl)}),
        ]))
    return html.Table(rows, className="levels")


def event_rows(events: List[Dict[str, Any]]) -> Any:
    if not events:
        return html.Div("no events yet", className="empty")
    return html.Div([
        html.Div(className="log-row", children=[
            html.Span(e["time"], className="log-time"),
            html.Span(e["text"], className="log-text"),
        ]) for e in events[:40]
    ])


# ---------------------------------------------------------------------------
# The single refresh callback
# ---------------------------------------------------------------------------
@app.callback(
    Output("topbar-instrument", "children"),
    Output("topbar-status", "children"),
    Output("status-led", "style"),
    Output("banner", "children"),
    Output("banner", "className"),
    Output("tile-equity", "children"), Output("tile-equity-sub", "children"),
    Output("tile-day", "children"), Output("tile-day", "style"),
    Output("tile-day-sub", "children"),
    Output("tile-floating", "children"), Output("tile-floating", "style"),
    Output("tile-floating-sub", "children"),
    Output("tile-dd", "children"), Output("tile-dd", "style"),
    Output("tile-dd-sub", "children"),
    Output("tile-levels", "children"), Output("tile-levels-sub", "children"),
    Output("tile-regime", "children"), Output("tile-regime", "style"),
    Output("tile-regime-sub", "children"),
    Output("tile-winrate", "children"), Output("tile-winrate-sub", "children"),
    Output("tile-spread", "children"), Output("tile-spread-sub", "children"),
    Output("fig-ladder", "figure"),
    Output("fig-surface", "figure"),
    Output("fig-terrain", "figure"),
    Output("fig-fib", "figure"),
    Output("fig-equity", "figure"),
    Output("fig-gauges", "figure"),
    Output("fig-pressure", "figure"),
    Output("level-table", "children"),
    Output("event-log", "children"),
    Input("tick", "n_intervals"),
)
def refresh(_n):
    snap = STORE.snapshot()
    series = STORE.series()
    account = snap["account"]
    market = snap["market"]
    cycle = snap["cycle"]
    guard = snap["guard"]
    stats = snap["stats"]
    regime = snap["regime"]

    age = STORE.age_seconds()
    live = age is not None and age < 15
    currency = account.get("currency", "")

    instrument = html.Div([
        html.Span(market.get("symbol", "-"), className="sym"),
        html.Span(market.get("timeframe", "-"), className="tf"),
        html.Span(f"{float(market.get('bid') or 0):.{int(market.get('digits', 5))}f}",
                  className="px"),
    ])

    source = snap.get("source", "none")
    status = html.Div([
        html.Span(f"feed: {source}", className="chip"),
        html.Span("LIVE" if live else "STALE",
                  className="chip live" if live else "chip stale"),
        html.Span(f"{age:.0f}s ago" if age is not None else "no data",
                  className="chip"),
        html.Span(f"{account.get('company', '-')} · {account.get('login', 0)}",
                  className="chip dim"),
    ])

    led_colour = T.GREEN if live else T.TEXT_DIM
    if guard.get("halted"):
        led_colour = T.RED
    elif not guard.get("trading_enabled", False):
        led_colour = T.AMBER
    led_style = {"background": led_colour,
                 "boxShadow": f"0 0 12px {led_colour}, 0 0 26px {led_colour}"}

    if guard.get("halted"):
        banner = f"⛔ EA HALTED — {guard.get('halt_reason') or 'protection breach'}"
        banner_class = "banner halt"
    elif guard.get("daily_target_hit"):
        banner = "✔ DAILY TARGET REACHED — resting until the next trading day"
        banner_class = "banner ok"
    elif not live:
        banner = "⏳ No telemetry received — start the EA, or run this dashboard with --demo"
        banner_class = "banner warn"
    else:
        banner, banner_class = "", "banner hidden"

    equity = float(account.get("equity") or 0.0)
    balance = float(account.get("balance") or 0.0)
    day_pl = float(guard.get("day_pl") or 0.0)
    floating = float(cycle.get("floating") or 0.0)
    dd = float(guard.get("dd_pct") or 0.0)
    dd_limit = float(snap["spec"].get("max_dd_pct") or 0.0)
    day_start = float(guard.get("day_start_balance") or 0.0)
    max_levels = int(snap["spec"].get("max_levels", 6))
    cycles = int(stats.get("cycles_total", 0))
    won = int(stats.get("cycles_won", 0))
    win_rate = (won / cycles * 100.0) if cycles else 0.0

    def money_style(value: float) -> Dict[str, str]:
        return {"color": T.pl_color(value)}

    figs = (
        F.fig_grid_ladder(snap),
        F.fig_risk_surface(snap),
        F.fig_equity_terrain(series),
        F.fig_fib_ladder(snap),
        F.fig_equity_2d(series),
        F.fig_regime_gauges(snap),
        F.fig_pressure(snap),
    )

    return (
        instrument, status, led_style, banner, banner_class,

        f"{equity:,.2f}", f"balance {balance:,.2f} {currency}",

        f"{day_pl:+,.2f}", money_style(day_pl),
        f"{(day_pl / day_start * 100.0) if day_start else 0.0:+.2f}% of day start",

        f"{floating:+,.2f}", money_style(floating),
        f"realised {float(cycle.get('realised') or 0.0):+,.2f}",

        f"{dd:.2f}%", {"color": T.RED if dd_limit and dd >= dd_limit * 0.5 else T.TEXT},
        f"limit {dd_limit:.1f}% · peak {float(guard.get('peak_equity') or 0.0):,.0f}",

        f"{int(cycle.get('levels', 0))} / {max_levels}",
        (f"{'LONG' if int(cycle.get('dir', 0)) > 0 else 'SHORT'} "
         f"{float(cycle.get('volume') or 0.0):.2f} lots"
         if cycle.get("active") else "flat"),

        regime.get("regime", "CHOP"),
        {"color": T.regime_color(regime.get("regime", ""))},
        f"ADX {float(regime.get('adx') or 0.0):.1f} · slope "
        f"{float(regime.get('slope_atr') or 0.0):+.3f}",

        f"{cycles} / {win_rate:.0f}%",
        f"realised {float(stats.get('realised_total') or 0.0):+,.2f}",

        f"{int(market.get('spread_points', 0))} pts",
        f"ATR {float(regime.get('atr') or 0.0):.{int(market.get('digits', 5))}f}",

        *figs,
        level_rows(snap),
        event_rows(STORE.event_list()),
    )


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
def main() -> None:
    global INGEST_KEY

    parser = argparse.ArgumentParser(description="Grid Fibonacci Pro dashboard")
    parser.add_argument("--host", default="127.0.0.1",
                        help="bind address (use 0.0.0.0 to accept a remote EA)")
    parser.add_argument("--port", type=int, default=8050)
    parser.add_argument("--demo", action="store_true",
                        help="run the synthetic feed instead of waiting for the EA")
    parser.add_argument("--mt5", action="store_true",
                        help="read a local MetaTrader 5 terminal directly")
    parser.add_argument("--symbol", default="EURUSD", help="symbol for --mt5")
    parser.add_argument("--timeframe", default="M15", help="timeframe for --mt5")
    parser.add_argument("--magic", type=int, default=0,
                        help="filter --mt5 positions by magic number (0 = all)")
    parser.add_argument("--ingest-key", default=INGEST_KEY,
                        help="require this X-Ingest-Key on /ingest")
    parser.add_argument("--debug", action="store_true")
    args = parser.parse_args()

    INGEST_KEY = args.ingest_key

    if args.demo:
        DemoFeed().start()
        STORE.note_event("demo feed running - no terminal required")
    if args.mt5:
        MT5Feed(symbol=args.symbol, magic=args.magic,
                timeframe=args.timeframe).start()

    print(f"  Grid Fibonacci Pro dashboard  ->  http://{args.host}:{args.port}")
    print(f"  EA ingest endpoint            ->  POST /ingest"
          f"{'  (key required)' if INGEST_KEY else ''}")
    app.run(host=args.host, port=args.port, debug=args.debug)


if __name__ == "__main__":
    main()
