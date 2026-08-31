#!/usr/bin/env bash
# Amalgamates the FibBot modules into one .mq5 that compiles on its own.
#
# The modular folder stays the source of truth — this only rewrites the
# generated file, so never edit the output by hand. Run it after changing
# any module:
#
#   ./mt5/FibBot/build-single-file.sh
#
# Output: mt5/FibBot/FibBot_AllInOne.mq5
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="$here/FibBot_AllInOne.mq5"

# Dependency order. Config first (structs and inputs), main file last.
modules=(Config.mqh Util.mqh Swing.mqh Fib.mqh Execution.mqh Api.mqh Visuals.mqh FibBot.mq5)

{
  cat <<'HEADER'
//+------------------------------------------------------------------+
//|                                              FibBot_AllInOne.mq5 |
//|                                                                  |
//|  GENERATED FILE — do not edit. Built from the modules in         |
//|  mt5/FibBot/ by build-single-file.sh. Edit those and re-run it.  |
//|                                                                  |
//|  Single-file build for pasting straight into MetaEditor: copy    |
//|  this one file to MQL5\Experts\ and press F7. Behaviour is       |
//|  identical to the modular folder.                                |
//+------------------------------------------------------------------+
#property copyright "Trading Signals Platform"
#property version   "1.00"
#property description "Fibonacci retracement setups: detect, publish, optionally trade."

#include <Trade\Trade.mqh>

HEADER

  for m in "${modules[@]}"; do
    printf '\n//====================================================================\n'
    printf '// %s\n' "$m"
    printf '//====================================================================\n\n'
    # Drop: project-relative includes, the standard-library include (hoisted
    # above), include guards, and the per-file #property block.
    sed -E \
      -e '/^#include "/d' \
      -e '/^#include <Trade\\Trade\.mqh>/d' \
      -e '/^#(ifndef|define) FIBBOT_[A-Z_]+_MQH$/d' \
      -e '/^#endif \/\/ FIBBOT_[A-Z_]+_MQH$/d' \
      -e '/^#property /d' \
      "$here/$m"
  done
} > "$out"

echo "wrote $out ($(wc -l < "$out") lines)"
