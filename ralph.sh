#!/bin/bash
# Ralph Wiggum - Long-running AI agent loop
# Usage: ./ralph.sh [options]
#
# Options:
#   -n, --iterations NUM   Maximum iterations (default: 10)
#   -t, --task NUM         Stop at task number (exit 0 if passes, exit 1 if fails)
#   -h, --help             Show this help
#
# Examples:
#   ./ralph.sh                    # Run with defaults (10 iterations)
#   ./ralph.sh -n 20              # Run up to 20 iterations
#   ./ralph.sh -t 3               # Stop after attempting task 3
#   ./ralph.sh -n 20 -t 5         # Stop after task 5, max 20 iterations

set -e

# Defaults
MAX_ITERATIONS=10
STOP_AT_TASK_NUM=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -n|--iterations)
      MAX_ITERATIONS="$2"
      shift 2
      ;;
    -t|--task)
      STOP_AT_TASK_NUM="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [options]"
      echo ""
      echo "Options:"
      echo "  -n, --iterations NUM   Maximum iterations (default: 10)"
      echo "  -t, --task NUM         Stop at task number (exit 0 if passes, exit 1 if fails)"
      echo "  -h, --help             Show this help"
      echo ""
      echo "Examples:"
      echo "  $0                      # Run with defaults"
      echo "  $0 -n 20                # Run up to 20 iterations"
      echo "  $0 -t 3                 # Stop after attempting task 3"
      echo "  $0 -n 20 -t 5           # Stop after task 5, max 20 iterations"
      exit 0
      ;;
    *)
      # Legacy support: bare number means max_iterations
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        MAX_ITERATIONS="$1"
      else
        echo "Unknown option: $1" >&2
        echo "Use -h for help" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRD_FILE="$SCRIPT_DIR/prd.json"
PROGRESS_FILE="$SCRIPT_DIR/progress.txt"
ARCHIVE_DIR="$SCRIPT_DIR/archive"
LAST_BRANCH_FILE="$SCRIPT_DIR/.last-branch"

# Archive previous run if branch changed
if [ -f "$PRD_FILE" ] && [ -f "$LAST_BRANCH_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  LAST_BRANCH=$(cat "$LAST_BRANCH_FILE" 2>/dev/null || echo "")

  if [ -n "$CURRENT_BRANCH" ] && [ -n "$LAST_BRANCH" ] && [ "$CURRENT_BRANCH" != "$LAST_BRANCH" ]; then
    # Archive the previous run
    DATE=$(date +%Y-%m-%d)
    # Strip "ralph/" prefix from branch name for folder
    FOLDER_NAME=$(echo "$LAST_BRANCH" | sed 's|^ralph/||')
    ARCHIVE_FOLDER="$ARCHIVE_DIR/$DATE-$FOLDER_NAME"

    echo "Archiving previous run: $LAST_BRANCH"
    mkdir -p "$ARCHIVE_FOLDER"
    [ -f "$PRD_FILE" ] && cp "$PRD_FILE" "$ARCHIVE_FOLDER/"
    [ -f "$PROGRESS_FILE" ] && cp "$PROGRESS_FILE" "$ARCHIVE_FOLDER/"
    echo "   Archived to: $ARCHIVE_FOLDER"

    # Reset progress file for new run
    echo "# Ralph Progress Log" > "$PROGRESS_FILE"
    echo "Started: $(date)" >> "$PROGRESS_FILE"
    echo "---" >> "$PROGRESS_FILE"
  fi
fi

# Track current branch
if [ -f "$PRD_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  if [ -n "$CURRENT_BRANCH" ]; then
    echo "$CURRENT_BRANCH" > "$LAST_BRANCH_FILE"
  fi
fi

# Initialize progress file if it doesn't exist
if [ ! -f "$PROGRESS_FILE" ]; then
  echo "# Ralph Progress Log" > "$PROGRESS_FILE"
  echo "Started: $(date)" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
fi

echo "Starting Ralph - Max iterations: $MAX_ITERATIONS"
if [ -n "$STOP_AT_TASK_NUM" ]; then
  echo "Will stop at task number: $STOP_AT_TASK_NUM (exit 0 if passes, exit 1 if fails)"
  export RALPH_STOP_AT_TASK_NUM="$STOP_AT_TASK_NUM"
fi

for i in $(seq 1 $MAX_ITERATIONS); do
  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  Ralph Iteration $i of $MAX_ITERATIONS"
  echo "═══════════════════════════════════════════════════════"

  # Run Claude Code with the ralph prompt
  OUTPUT=$(cat "$SCRIPT_DIR/prompt.md" | claude --dangerously-skip-permissions 2>&1 | tee /dev/stderr) || true

  # Check for completion signal
  if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
    echo ""
    echo "Ralph completed all tasks!"
    echo "Completed at iteration $i of $MAX_ITERATIONS"
    exit 0
  fi

  # If stop_at_task_num is set, check the task status
  if [ -n "$STOP_AT_TASK_NUM" ] && [ -f "$PRD_FILE" ]; then
    TASK_INDEX=$((STOP_AT_TASK_NUM - 1))
    TASK_PASSES=$(jq -r ".user_stories[$TASK_INDEX].passes // false" "$PRD_FILE")
    TASK_ID=$(jq -r ".user_stories[$TASK_INDEX].id // \"US-$STOP_AT_TASK_NUM\"" "$PRD_FILE")

    if [ "$TASK_PASSES" = "true" ]; then
      echo ""
      echo "Task $TASK_ID (position $STOP_AT_TASK_NUM) passed!"
      echo "Stopping as requested. Completed at iteration $i"
      exit 0
    elif [ "$TASK_PASSES" = "false" ]; then
      # Check if this task was just attempted (status changed from pending)
      TASK_STATUS=$(jq -r ".user_stories[$TASK_INDEX].status // \"pending\"" "$PRD_FILE")
      if [ "$TASK_STATUS" != "pending" ]; then
        echo ""
        echo "ERROR: Task $TASK_ID (position $STOP_AT_TASK_NUM) failed!"
        echo "Task status: $TASK_STATUS, passes: false"
        echo "Check $PROGRESS_FILE for details."
        exit 1
      fi
    fi
  fi

  echo "Iteration $i complete. Continuing..."
  sleep 2
done

echo ""
echo "Ralph reached max iterations ($MAX_ITERATIONS) without completing target task."
if [ -n "$STOP_AT_TASK_NUM" ]; then
  echo "Task at position $STOP_AT_TASK_NUM did not complete."
fi
echo "Check $PROGRESS_FILE for status."
exit 1
