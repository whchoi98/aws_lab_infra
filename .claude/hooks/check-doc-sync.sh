#!/bin/bash
# Check if documentation needs updating after file changes
# Triggered by Write/Edit tool uses

CHANGED_FILE="$1"

check_doc_needed() {
  local dir="$1"
  local doc="$2"
  if [ ! -f "$doc" ]; then
    echo "⚠️  Missing documentation: $doc"
    echo "   Run /sync-docs to generate"
    return 1
  fi
}

# Check module CLAUDE.md files
for dir in cloudformation cdk terraform shared; do
  if [[ "$CHANGED_FILE" == *"$dir"* ]]; then
    check_doc_needed "$dir" "$dir/CLAUDE.md"
  fi
done

# Check if architecture doc needs update
if [[ "$CHANGED_FILE" == *"templates/"* ]] || [[ "$CHANGED_FILE" == *"modules/"* ]] || [[ "$CHANGED_FILE" == *"lib/"* ]]; then
  if [ -f "docs/architecture.md" ]; then
    MOD_TIME=$(stat -c %Y "docs/architecture.md" 2>/dev/null || echo 0)
    NOW=$(date +%s)
    AGE=$(( (NOW - MOD_TIME) / 86400 ))
    if [ "$AGE" -gt 7 ]; then
      echo "⚠️  docs/architecture.md is $AGE days old. Consider running /sync-docs"
    fi
  fi
fi
