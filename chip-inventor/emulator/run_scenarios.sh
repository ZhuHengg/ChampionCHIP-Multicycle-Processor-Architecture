#!/bin/bash
# Run every scenario in emu_commands.txt against the real ./emu (Stage 4, on
# the AWS FPGA).
#
#   bash run_scenarios.sh [--dry-run]
#
# EMU overrides the emulator binary (default ./emu).
#
# emu.c returns EXIT_SUCCESS on error and EXIT_FAILURE on a clean run, so the
# exit code is useless: a scenario passes when its output has at least one [ok]
# and no [error].
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMANDS="$HERE/emu_commands.txt"
EMU="${EMU:-./emu}"
DRY_RUN=0

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        *) echo "usage: $0 [--dry-run]" >&2; exit 2 ;;
    esac
done

if [ ! -f "$COMMANDS" ]; then
    echo "missing $COMMANDS (generate it with scenarios.py)" >&2
    exit 2
fi

name='?'
failures=0
total=0

while IFS= read -r line; do
    case "$line" in
        '# '[SH][0-9]*:*)
            name="${line#\# }"
            name="${name%%:*}"
            continue
            ;;
        './emu '*)
            ;;
        *)
            continue
            ;;
    esac

    command_line="${EMU}${line#./emu}"
    total=$((total + 1))

    if [ "$DRY_RUN" -eq 1 ]; then
        printf '%s\n' "$line"
        continue
    fi

    output="$(eval "$command_line" 2>&1)"
    if printf '%s' "$output" | grep -q '\[error\]' || \
       ! printf '%s' "$output" | grep -q '\[ok\]'; then
        echo "FAIL $name"
        printf '%s\n' "$output" | sed 's/^/    /'
        failures=$((failures + 1))
    else
        echo "PASS $name"
    fi
done < "$COMMANDS"

if [ "$DRY_RUN" -eq 1 ]; then
    exit 0
fi

echo
echo "$((total - failures))/$total scenarios passed"
[ "$failures" -eq 0 ]
