"""Every figure the dashboard draws.

The three 3D views each answer a different question:

  * LADDER   — where the money actually is right now: one stem per filled grid
               level, height = fill price, depth = lot size, colour = P/L.
  * RISK     — what happens next: basket P/L as a surface over (price move,
               ladder depth), including the levels not filled yet. This is the
               view that makes a grid's convexity visible instead of implied.
  * TERRAIN  — where the account has been: the equity path plotted against its
               own drawdown, so a recovering curve and a deteriorating one are
               different shapes rather than the same line.
"""

from __future__ import annotations

from typing import Any, Dict, List, Tuple

import numpy as np
import plotly.graph_objects as go

import theme as T

EMPTY_NOTE = dict(
    xref="paper", yref="paper", x=0.5, y=0.5, showarrow=False,
    font=dict(color=T.TEXT_DIM, size=12), align="center",
)


def _blank(title: str, message: str) -> go.Figure:
    fig = go.Figure()
    fig.update_layout(
        title=title,
        annotations=[dict(text=message, **EMPTY_NOTE)],
        xaxis=dict(visible=False), yaxis=dict(visible=False),
        height=340,
    )
    return fig


def money_per_price_per_lot(spec: Dict[str, Any]) -> float:
    """Account currency earned per 1.0 of price movement, per 1.0 lot."""
    tick_size = float(spec.get("tick_size") or 0.0)
    tick_value = float(spec.get("tick_value") or 0.0)
    if tick_size <= 0 or tick_value <= 0:
        return 0.0
    return tick_value / tick_size


def open_levels(snap: Dict[str, Any]) -> List[Dict[str, Any]]:
    levels = [lv for lv in snap.get("levels", []) if not lv.get("closed")]
    return sorted(levels, key=lambda lv: lv.get("level", 0))


# ---------------------------------------------------------------------------
# 3D — grid ladder
# ---------------------------------------------------------------------------
def fig_grid_ladder(snap: Dict[str, Any]) -> go.Figure:
    cycle = snap["cycle"]
    market = snap["market"]
    levels = open_levels(snap)
    digits = int(market.get("digits", 5))

    if not levels:
        return _blank("GRID LADDER · 3D", "no open grid levels")

    direction = int(cycle.get("dir", 0)) or 1
    stop = float(cycle.get("stop_price", 0.0))
    price_now = float(market.get("bid") or 0.0)
    base = stop if stop > 0 else min(lv["filled"] for lv in levels)

    xs = [int(lv["level"]) for lv in levels]
    ys = [float(lv["lots"]) for lv in levels]
    zs = [float(lv["filled"]) for lv in levels]
    pls = [float(lv.get("pl", 0.0)) for lv in levels]

    fig = go.Figure()

    # Stems: each level dropped to the shared basket stop, so the distance to
    # invalidation is a length you can see rather than a number to subtract.
    for x, y, z in zip(xs, ys, zs):
        fig.add_trace(go.Scatter3d(
            x=[x, x], y=[y, y], z=[base, z],
            mode="lines",
            line=dict(color=T.NEON_DIM, width=4),
            hoverinfo="skip", showlegend=False,
        ))

    fig.add_trace(go.Scatter3d(
        x=xs, y=ys, z=zs,
        mode="markers+text",
        marker=dict(
            size=[max(10.0, 10 + 26 * (v / max(ys))) for v in ys],
            color=pls, colorscale=T.PL_SCALE, cmid=0.0,
            line=dict(color=T.NEON, width=1),
            colorbar=dict(title=dict(text="P/L", font=dict(color=T.TEXT_DIM, size=10)),
                          tickfont=dict(color=T.TEXT_DIM, size=9),
                          outlinewidth=0, thickness=10, len=0.6),
            opacity=0.95,
        ),
        text=[f"L{x}" for x in xs],
        textposition="top center",
        textfont=dict(color=T.TEXT, size=10),
        customdata=np.column_stack([ys, pls]),
        hovertemplate=("level %{text}<br>fill %{z:." + str(digits) + "f}"
                       "<br>lots %{customdata[0]:.2f}"
                       "<br>P/L %{customdata[1]:+.2f}<extra></extra>"),
        name="filled levels",
    ))

    # The pending step, drawn as a projection rather than a fact.
    next_price = float(cycle.get("next_price", 0.0))
    if next_price > 0:
        fig.add_trace(go.Scatter3d(
            x=[max(xs) + 1], y=[ys[-1]], z=[next_price],
            mode="markers+text",
            marker=dict(size=12, color=T.VIOLET, symbol="diamond",
                        line=dict(color=T.GOLD, width=1)),
            text=["NEXT"], textposition="top center",
            textfont=dict(color=T.VIOLET, size=10),
            hovertemplate="next level<br>%{z:." + str(digits) + "f}<extra></extra>",
            name="planned",
        ))

    # Reference planes: basket average, current price, the far target.
    span_x = [min(xs) - 0.5, max(xs) + 1.5]
    span_y = [0.0, max(ys) * 1.4]
    planes = [
        (float(cycle.get("avg_price", 0.0)), T.GOLD, "basket average"),
        (price_now, T.NEON, "market"),
        (float(cycle.get("tp3", 0.0)), T.GREEN, "final target"),
        (stop, T.RED, "basket stop"),
    ]
    for value, colour, label in planes:
        if value <= 0:
            continue
        fig.add_trace(go.Surface(
            x=span_x, y=span_y,
            z=[[value, value], [value, value]],
            showscale=False, opacity=0.16,
            colorscale=[[0, colour], [1, colour]],
            hovertemplate=f"{label} %{{z:.{digits}f}}<extra></extra>",
            name=label, showlegend=False,
        ))

    fig.update_layout(
        title=f"GRID LADDER · 3D   {'LONG' if direction > 0 else 'SHORT'} basket",
        scene=T.scene("level", "lots", "price", eye=(1.9, 1.3, 0.75)),
        height=430, showlegend=False,
    )
    return fig


# ---------------------------------------------------------------------------
# 3D — basket P/L risk surface
# ---------------------------------------------------------------------------
def _projected_ladder(snap: Dict[str, Any]) -> Tuple[List[Tuple[float, float]], int, float]:
    """Return (ladder, filled_count, spacing).

    ladder is [(price, lots)] ordered outward from the first entry, covering
    both the levels already filled and the ones the EA would still add.
    """
    cycle = snap["cycle"]
    market = snap["market"]
    spec = snap["spec"]
    regime = snap["regime"]

    levels = open_levels(snap)
    direction = int(cycle.get("dir", 0))
    price_now = float(market.get("bid") or 0.0)
    atr = float(regime.get("atr") or 0.0) or (price_now * 0.002 if price_now else 1.0)
    max_levels = max(1, int(spec.get("max_levels", 6)))

    if levels:
        ladder = [(float(lv["filled"]), float(lv["lots"])) for lv in levels]
    else:
        # Flat: project the ladder the EA WOULD build from here, so the surface
        # still answers "what would this configuration cost me".
        direction = int(snap["swing"].get("dir", 0)) or 1
        ladder = [(price_now, float(spec.get("volume_min", 0.01)))]

    filled_count = len(ladder)

    # Spacing: measured from the real fills when we have two, otherwise from
    # the EA's own next planned level, otherwise one ATR.
    if len(ladder) >= 2:
        gaps = [abs(ladder[i][0] - ladder[i - 1][0]) for i in range(1, len(ladder))]
        spacing = sum(gaps) / len(gaps)
    else:
        next_price = float(cycle.get("next_price", 0.0))
        spacing = abs(ladder[0][0] - next_price) if next_price > 0 else atr
    spacing = max(spacing, atr * 0.25)

    # Lot progression: the ratio the EA has actually been using.
    if len(ladder) >= 2 and ladder[-2][1] > 0:
        ratio = min(max(ladder[-1][1] / ladder[-2][1], 1.0), 3.0)
    else:
        ratio = 1.0

    price, lots = ladder[-1]
    direction = direction or 1
    for _ in range(len(ladder), max_levels):
        price = price - direction * spacing
        lots = lots * ratio
        ladder.append((price, lots))

    return ladder, filled_count, spacing


def fig_risk_surface(snap: Dict[str, Any]) -> go.Figure:
    spec = snap["spec"]
    market = snap["market"]
    cycle = snap["cycle"]
    regime = snap["regime"]

    mpp = money_per_price_per_lot(spec)
    price_now = float(market.get("bid") or 0.0)
    if mpp <= 0 or price_now <= 0:
        return _blank("BASKET RISK SURFACE · 3D", "waiting for contract specification")

    atr = float(regime.get("atr") or 0.0) or price_now * 0.002
    ladder, filled_count, _ = _projected_ladder(snap)
    direction = int(cycle.get("dir", 0)) or int(snap["swing"].get("dir", 0)) or 1
    max_levels = max(1, int(spec.get("max_levels", 6)))

    # X: where price goes next, in ATR units. Y: how deep the ladder is allowed
    # to get. Z: the money that produces.
    offsets = np.linspace(-4.0, 4.0, 81)
    caps = np.arange(1, max_levels + 1)
    z = np.zeros((len(caps), len(offsets)))

    for ci, cap in enumerate(caps):
        for oi, off in enumerate(offsets):
            price = price_now + off * atr
            total = 0.0
            for idx, (lvl_price, lvl_lots) in enumerate(ladder[: int(cap)]):
                if idx >= filled_count:
                    # An unfilled level only exists once price trades through it.
                    reached = price <= lvl_price if direction > 0 else price >= lvl_price
                    if not reached:
                        continue
                total += direction * (price - lvl_price) * lvl_lots * mpp
            z[ci, oi] = total

    equity = float(snap["account"].get("equity") or 0.0)
    cycle_stop = -equity * float(spec.get("cycle_max_loss_pct", 0.0)) / 100.0

    fig = go.Figure()
    fig.add_trace(go.Surface(
        x=offsets, y=caps, z=z,
        colorscale=T.PL_SCALE, cmid=0.0,
        opacity=0.97,
        contours=dict(
            z=dict(show=True, usecolormap=True, project_z=True,
                   width=1, highlightcolor=T.NEON),
            x=dict(show=True, color=T.BORDER, width=1),
        ),
        colorbar=dict(title=dict(text="P/L", font=dict(color=T.TEXT_DIM, size=10)),
                      tickfont=dict(color=T.TEXT_DIM, size=9),
                      outlinewidth=0, thickness=10, len=0.6),
        hovertemplate=("move %{x:+.2f} ATR<br>ladder cap %{y}"
                       "<br>basket P/L %{z:+.2f}<extra></extra>"),
        name="basket P/L",
    ))

    # The cycle's own loss ceiling, as a floor the surface can be read against.
    if cycle_stop < 0:
        fig.add_trace(go.Surface(
            x=offsets, y=caps,
            z=np.full_like(z, cycle_stop),
            showscale=False, opacity=0.18,
            colorscale=[[0, T.RED], [1, T.RED]],
            hovertemplate=f"cycle loss ceiling {cycle_stop:+.2f}<extra></extra>",
            name="loss ceiling", showlegend=False,
        ))

    # Where the market is right now.
    current = np.interp(0.0, offsets, z[min(filled_count, len(caps)) - 1])
    fig.add_trace(go.Scatter3d(
        x=[0.0], y=[max(1, filled_count)], z=[current],
        mode="markers+text", text=["NOW"], textposition="top center",
        textfont=dict(color=T.GOLD, size=11),
        marker=dict(size=7, color=T.GOLD, symbol="diamond",
                    line=dict(color=T.TEXT, width=1)),
        hovertemplate="current basket %{z:+.2f}<extra></extra>",
        showlegend=False,
    ))

    fig.update_layout(
        title="BASKET RISK SURFACE · 3D   P/L over price move × ladder depth",
        scene=T.scene("price move (ATR)", "ladder depth", "basket P/L",
                      eye=(1.6, -1.7, 0.9)),
        height=430, showlegend=False,
    )
    return fig


# ---------------------------------------------------------------------------
# 3D — equity terrain
# ---------------------------------------------------------------------------
def fig_equity_terrain(series: Dict[str, List[float]]) -> go.Figure:
    equity = series["equity"]
    if len(equity) < 3:
        return _blank("EQUITY TERRAIN · 3D", "collecting history…")

    n = len(equity)
    step = max(1, n // 600)  # keep the trace light on long sessions
    idx = list(range(0, n, step))

    x = [i for i in idx]
    y = [series["dd_pct"][i] for i in idx]
    z = [equity[i] for i in idx]
    floating = [series["floating"][i] for i in idx]
    levels = [series["levels"][i] for i in idx]

    fig = go.Figure()
    fig.add_trace(go.Scatter3d(
        x=x, y=y, z=z,
        mode="lines",
        line=dict(color=floating, colorscale=T.PL_SCALE, cmid=0.0, width=6),
        hovertemplate=("t %{x}<br>drawdown %{y:.2f}%"
                       "<br>equity %{z:.2f}<extra></extra>"),
        name="equity path",
    ))
    fig.add_trace(go.Scatter3d(
        x=x, y=y, z=z,
        mode="markers",
        marker=dict(size=[2 + 1.6 * lv for lv in levels],
                    color=floating, colorscale=T.PL_SCALE, cmid=0.0,
                    opacity=0.55, showscale=False),
        hoverinfo="skip", showlegend=False,
    ))
    # The balance floor makes the gap between banked and floating visible.
    if series["balance"]:
        floor = min(series["balance"])
        fig.add_trace(go.Scatter3d(
            x=x, y=[0.0] * len(x), z=[floor] * len(x),
            mode="lines", line=dict(color=T.BORDER, width=2),
            hoverinfo="skip", showlegend=False,
        ))

    fig.update_layout(
        title="EQUITY TERRAIN · 3D   path plotted against its own drawdown",
        scene=T.scene("snapshot", "drawdown %", "equity", eye=(-1.7, -1.5, 0.85)),
        height=430, showlegend=False,
    )
    return fig


# ---------------------------------------------------------------------------
# 2D — equity / drawdown
# ---------------------------------------------------------------------------
def fig_equity_2d(series: Dict[str, List[float]]) -> go.Figure:
    if len(series["equity"]) < 2:
        return _blank("EQUITY & DRAWDOWN", "collecting history…")

    x = list(range(len(series["equity"])))
    fig = go.Figure()
    fig.add_trace(go.Scatter(
        x=x, y=series["balance"], name="balance",
        line=dict(color=T.TEXT_DIM, width=1, dash="dot"),
        hovertemplate="balance %{y:.2f}<extra></extra>",
    ))
    fig.add_trace(go.Scatter(
        x=x, y=series["equity"], name="equity",
        line=dict(color=T.NEON, width=2), fill="tonexty",
        fillcolor="rgba(0,229,255,0.10)",
        hovertemplate="equity %{y:.2f}<extra></extra>",
    ))
    fig.add_trace(go.Scatter(
        x=x, y=series["dd_pct"], name="drawdown %",
        line=dict(color=T.RED, width=1), yaxis="y2",
        hovertemplate="drawdown %{y:.2f}%<extra></extra>",
    ))
    fig.update_layout(
        title="EQUITY & DRAWDOWN",
        # equity sits near the account size, so SI-prefixed ticks ("10k") lose
        # exactly the digits that matter: format them in full and reserve the
        # margin both axes need.
        # Equity moves in cents against a four-figure balance and drawdown in
        # hundredths of a percent, so both axes need real decimals: rounded
        # ticks collapse into a column of identical labels.
        yaxis=dict(title=None, tickformat=",.2f", automargin=True),
        yaxis2=dict(overlaying="y", side="right", showgrid=False, ticksuffix="%",
                    tickformat=".2f", tickfont=dict(color=T.RED, size=9),
                    rangemode="tozero", automargin=True, nticks=5),
        xaxis=dict(showticklabels=False),
        margin=dict(l=58, r=52, t=28, b=8),
        height=260,
    )
    return fig


# ---------------------------------------------------------------------------
# 2D — the Fibonacci structure as a price ladder
# ---------------------------------------------------------------------------
def fig_fib_ladder(snap: Dict[str, Any]) -> go.Figure:
    swing = snap["swing"]
    market = snap["market"]
    cycle = snap["cycle"]
    digits = int(market.get("digits", 5))

    if not swing.get("valid") or float(swing.get("range", 0.0)) <= 0:
        return _blank("FIBONACCI STRUCTURE", "no qualified impulse leg")

    hi = float(swing["high"])
    lo = float(swing["low"])
    rng = hi - lo
    direction = int(swing.get("dir", 1)) or 1
    price = float(market.get("bid") or 0.0)

    def retrace(ratio: float) -> float:
        return hi - ratio * rng if direction > 0 else lo + ratio * rng

    def extend(ratio: float) -> float:
        return lo + ratio * rng if direction > 0 else hi - ratio * rng

    fig = go.Figure()
    ratios = [0.236, 0.382, 0.5, 0.618, 0.705, 0.786, 1.0]
    for ratio in ratios:
        level = retrace(ratio)
        key = ratio in (0.5, 0.618)
        fig.add_trace(go.Scatter(
            x=[0, 1], y=[level, level], mode="lines",
            line=dict(color=T.GOLD if key else T.BORDER,
                      width=2 if key else 1,
                      dash="solid" if key else "dot"),
            name=f"{ratio:.3f}", showlegend=False,
            hovertemplate=f"retr {ratio:.3f} %{{y:.{digits}f}}<extra></extra>",
        ))
        fig.add_annotation(x=1, y=level, text=f" {ratio:.3f}", showarrow=False,
                           xanchor="left", font=dict(color=T.TEXT_DIM, size=9))

    for label, ratio, colour in (("TP1", 1.272, T.GREEN),
                                 ("TP2", 1.618, T.GREEN),
                                 ("TP3", 2.618, T.NEON)):
        level = extend(ratio)
        fig.add_trace(go.Scatter(
            x=[0, 1], y=[level, level], mode="lines",
            line=dict(color=colour, width=1, dash="dash"),
            showlegend=False,
            hovertemplate=f"{label} {ratio} %{{y:.{digits}f}}<extra></extra>",
        ))
        fig.add_annotation(x=1, y=level, text=f" {label}", showarrow=False,
                           xanchor="left", font=dict(color=colour, size=9))

    # The entry window, as a band rather than two more lines.
    zone_a, zone_b = retrace(0.382), retrace(0.786)
    fig.add_hrect(y0=min(zone_a, zone_b), y1=max(zone_a, zone_b),
                  fillcolor=T.GREEN if direction > 0 else T.RED,
                  opacity=0.10, line_width=0)

    for level in open_levels(snap):
        fig.add_trace(go.Scatter(
            x=[0.5], y=[float(level["filled"])], mode="markers+text",
            marker=dict(size=9, color=T.dir_color(int(cycle.get("dir", 0))),
                        symbol="triangle-right", line=dict(color=T.TEXT, width=1)),
            text=[f"L{level['level']} {level['lots']:.2f}"],
            textposition="middle right",
            textfont=dict(color=T.TEXT, size=9),
            showlegend=False,
            hovertemplate=f"fill %{{y:.{digits}f}}<extra></extra>",
        ))

    if price > 0:
        fig.add_trace(go.Scatter(
            x=[0, 1], y=[price, price], mode="lines",
            line=dict(color=T.NEON, width=2),
            showlegend=False,
            hovertemplate=f"market %{{y:.{digits}f}}<extra></extra>",
        ))

    fig.update_layout(
        title=f"FIBONACCI STRUCTURE   {'IMPULSE UP' if direction > 0 else 'IMPULSE DOWN'}",
        # prices on the left, ratio labels on the right: putting both on the
        # right made the axis ticks and the annotations overwrite each other
        xaxis=dict(visible=False, range=[0, 1.16]),
        yaxis=dict(side="left", tickformat=f".{digits}f", automargin=True),
        margin=dict(l=8, r=58, t=28, b=8),
        height=430, showlegend=False,
    )
    return fig


# ---------------------------------------------------------------------------
# 2D — regime instrumentation
# ---------------------------------------------------------------------------
def fig_regime_gauges(snap: Dict[str, Any]) -> go.Figure:
    regime = snap["regime"]
    guard = snap["guard"]
    spec = snap["spec"]

    adx = float(regime.get("adx") or 0.0)
    slope = float(regime.get("slope_atr") or 0.0)
    dd = float(guard.get("dd_pct") or 0.0)
    dd_limit = max(float(spec.get("max_dd_pct", 12.0)), 0.1)

    fig = go.Figure()
    fig.add_trace(go.Indicator(
        mode="gauge+number", value=adx,
        title=dict(text="ADX", font=dict(color=T.TEXT_DIM, size=11)),
        number=dict(font=dict(color=T.NEON, size=22), valueformat=".1f"),
        gauge=dict(
            axis=dict(range=[0, 60], tickcolor=T.BORDER,
                      tickfont=dict(color=T.TEXT_DIM, size=8)),
            bar=dict(color=T.NEON, thickness=0.28),
            bgcolor=T.BG_RAISED, borderwidth=0,
            steps=[dict(range=[0, 18], color="#12202e"),
                   dict(range=[18, 22], color="#1b2c3d"),
                   dict(range=[22, 60], color="#123c44")],
            threshold=dict(line=dict(color=T.GOLD, width=2), value=22),
        ),
        domain=dict(row=0, column=0),
    ))
    fig.add_trace(go.Indicator(
        mode="gauge+number", value=slope,
        title=dict(text="MA SLOPE / ATR", font=dict(color=T.TEXT_DIM, size=11)),
        number=dict(font=dict(color=T.pl_color(slope), size=22), valueformat="+.3f"),
        gauge=dict(
            axis=dict(range=[-0.6, 0.6], tickcolor=T.BORDER,
                      tickfont=dict(color=T.TEXT_DIM, size=8)),
            bar=dict(color=T.pl_color(slope), thickness=0.28),
            bgcolor=T.BG_RAISED, borderwidth=0,
            threshold=dict(line=dict(color=T.GOLD, width=2), value=0),
        ),
        domain=dict(row=0, column=1),
    ))
    fig.add_trace(go.Indicator(
        mode="gauge+number", value=dd,
        title=dict(text="DRAWDOWN %", font=dict(color=T.TEXT_DIM, size=11)),
        number=dict(font=dict(color=T.RED if dd > dd_limit * 0.5 else T.TEXT, size=22),
                    valueformat=".2f"),
        gauge=dict(
            axis=dict(range=[0, dd_limit], tickcolor=T.BORDER,
                      tickfont=dict(color=T.TEXT_DIM, size=8)),
            bar=dict(color=T.RED, thickness=0.28),
            bgcolor=T.BG_RAISED, borderwidth=0,
            threshold=dict(line=dict(color=T.GOLD, width=2), value=dd_limit),
        ),
        domain=dict(row=0, column=2),
    ))
    fig.update_layout(
        grid=dict(rows=1, columns=3, pattern="independent"),
        height=190, margin=dict(l=8, r=8, t=8, b=8),
    )
    return fig


# ---------------------------------------------------------------------------
# 2D — directional pressure (+DI / -DI over the MA stack)
# ---------------------------------------------------------------------------
def fig_pressure(snap: Dict[str, Any]) -> go.Figure:
    regime = snap["regime"]
    di_plus = float(regime.get("di_plus") or 0.0)
    di_minus = float(regime.get("di_minus") or 0.0)

    fig = go.Figure()
    fig.add_trace(go.Bar(
        x=[di_plus], y=["pressure"], orientation="h", width=0.34,
        marker=dict(color=T.GREEN, line=dict(color=T.BG_PANEL, width=1)),
        name="+DI", hovertemplate="+DI %{x:.1f}<extra></extra>",
    ))
    fig.add_trace(go.Bar(
        x=[-di_minus], y=["pressure"], orientation="h", width=0.34,
        marker=dict(color=T.RED, line=dict(color=T.BG_PANEL, width=1)),
        name="-DI", hovertemplate="-DI %{x:.1f}<extra></extra>",
    ))
    limit = max(di_plus, di_minus, 25.0) * 1.15
    dominant = di_plus - di_minus
    # Parked on the title row: inside the plot area a long bar runs straight
    # through the very text that summarises it.
    fig.add_annotation(
        xref="paper", yref="paper", x=1.0, y=1.16,
        xanchor="right", yanchor="middle", showarrow=False,
        text=("BALANCED" if abs(dominant) < 0.5 else
              f"{'BULL' if dominant > 0 else 'BEAR'} {abs(dominant):.1f}"),
        font=dict(color=T.pl_color(dominant), size=12),
    )
    fig.update_layout(
        title="DIRECTIONAL PRESSURE",
        barmode="relative", bargap=0.55,
        xaxis=dict(range=[-limit, limit], zerolinecolor=T.NEON_DIM,
                   zerolinewidth=2, tickformat=".0f"),
        yaxis=dict(visible=False),
        margin=dict(l=8, r=8, t=34, b=22),
        height=150, showlegend=True,
    )
    return fig
