"""Neon palette and the shared Plotly template.

Every colour used anywhere in the dashboard is defined once, here. The Plotly
template below is registered under the name ``gfea`` and set as the default, so
no figure has to restate fonts, grid colours or paper backgrounds.
"""

from __future__ import annotations

import plotly.graph_objects as go
import plotly.io as pio

# --------------------------------------------------------------------------
# Palette
# --------------------------------------------------------------------------
BG_DEEP = "#05070d"  # page background
BG_PANEL = "#0a1018"  # card background
BG_RAISED = "#0f1724"  # header strips, table stripes
BORDER = "#1c2b40"

NEON = "#00e5ff"  # primary accent (cyan)
NEON_DIM = "#0b6d7d"
GOLD = "#ffc72c"  # secondary accent
GOLD_DIM = "#8a6a15"
GREEN = "#00e696"  # long / profit
RED = "#ff4a6e"  # short / loss
AMBER = "#ffa42e"  # warning
VIOLET = "#a97bff"  # projections

TEXT = "#e2eef5"
TEXT_DIM = "#7a8c9e"

# Diverging scale used by every P/L surface: loss -> flat -> profit.
PL_SCALE = [
    [0.00, "#7a1030"],
    [0.25, RED],
    [0.48, "#16202e"],
    [0.52, "#16202e"],
    [0.75, "#00a86f"],
    [1.00, GREEN,],
]

# Sequential scale for exposure / depth.
DEPTH_SCALE = [
    [0.0, "#0a1018"],
    [0.4, NEON_DIM],
    [0.7, NEON],
    [1.0, GOLD],
]

FONT = "Consolas, 'JetBrains Mono', 'SF Mono', Menlo, monospace"
FONT_UI = "'Segoe UI', Inter, system-ui, sans-serif"


def _axis3d(title: str) -> dict:
    return dict(
        title=dict(text=title, font=dict(color=TEXT_DIM, size=10)),
        backgroundcolor=BG_PANEL,
        gridcolor=BORDER,
        zerolinecolor=NEON_DIM,
        showbackground=True,
        color=TEXT_DIM,
        tickfont=dict(size=9, color=TEXT_DIM),
    )


def scene(x: str, y: str, z: str, eye=(1.7, 1.5, 1.0)) -> dict:
    """A consistently lit, consistently framed 3D scene."""
    return dict(
        xaxis=_axis3d(x),
        yaxis=_axis3d(y),
        zaxis=_axis3d(z),
        aspectmode="cube",
        camera=dict(eye=dict(x=eye[0], y=eye[1], z=eye[2])),
        bgcolor=BG_PANEL,
    )


template = go.layout.Template()
template.layout = go.Layout(
    paper_bgcolor="rgba(0,0,0,0)",
    plot_bgcolor="rgba(0,0,0,0)",
    font=dict(family=FONT, color=TEXT, size=11),
    margin=dict(l=8, r=8, t=28, b=8),
    title=dict(font=dict(family=FONT_UI, color=GOLD, size=13), x=0.01, xanchor="left"),
    xaxis=dict(gridcolor=BORDER, zerolinecolor=BORDER, linecolor=BORDER,
               tickfont=dict(color=TEXT_DIM, size=10)),
    yaxis=dict(gridcolor=BORDER, zerolinecolor=BORDER, linecolor=BORDER,
               tickfont=dict(color=TEXT_DIM, size=10)),
    legend=dict(bgcolor="rgba(0,0,0,0)", font=dict(color=TEXT_DIM, size=10),
                orientation="h", y=1.06, x=0),
    hoverlabel=dict(bgcolor=BG_RAISED, bordercolor=NEON,
                    font=dict(family=FONT, color=TEXT, size=11)),
    colorway=[NEON, GOLD, GREEN, RED, VIOLET, AMBER],
)
pio.templates["gfea"] = template
pio.templates.default = "gfea"


def pl_color(value: float) -> str:
    """Green above zero, red below, dim at zero."""
    if value > 0:
        return GREEN
    if value < 0:
        return RED
    return TEXT_DIM


def dir_color(direction: int) -> str:
    if direction > 0:
        return GREEN
    if direction < 0:
        return RED
    return TEXT_DIM


def regime_color(regime: str) -> str:
    regime = (regime or "").upper()
    if regime == "TREND UP":
        return GREEN
    if regime == "TREND DOWN":
        return RED
    if regime == "RANGE":
        return GOLD
    return TEXT_DIM
