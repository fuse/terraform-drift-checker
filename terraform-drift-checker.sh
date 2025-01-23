#!/usr/bin/env bash

set -o pipefail
set -o nounset
set -o errexit

YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

TOTAL_DIFFS=0
TOTAL_STATE_ONLY=0
TOTAL_CODE_ONLY=0

usage() {
  echo "Usage: $0 <path_to_plan.json>"
  echo
  echo "To generate a plan file:"
  echo "  1. terraform plan -out=plan.out"
  echo "  2. terraform show -json plan.out > plan.out.json"
  exit 1
}

if [ $# -ne 1 ]; then
  usage
fi

PLAN_FILE="$1"

if [ ! -f "$PLAN_FILE" ]; then
  echo -e "${RED}Error: File '$PLAN_FILE' not found${NC}"
  usage
fi

if ! jq empty "$PLAN_FILE" 2>/dev/null; then
  echo -e "${RED}Error: File '$PLAN_FILE' is not a valid JSON file${NC}"
  usage
fi

compare_data() {
  local before="$1"
  local after="$2"
  local resource="$3"

  local namespace=$(echo "$resource" | jq -r '.change.before.namespace // .change.after.namespace')
  local vault_name=$(echo "$resource" | jq -r '.change.before.name // .change.after.name')

  local all_keys=$(echo "$before $after" | jq -r 'to_entries | .[].key' | sort -u)

  for key in $all_keys; do
    before_value=$(echo "$before" | jq -r ".$key // \"\"")
    after_value=$(echo "$after" | jq -r ".$key // \"\"")

    # Value differs
    if [ ! -z "$before_value" ] && [ ! -z "$after_value" ] && [ "$before_value" != "$after_value" ]; then
      echo -e "${YELLOW}In namespace ${namespace}, vault ${vault_name}, key ${key} differs:${NC}"
      printf "${YELLOW}  %-13s %s${NC}\n" "Actual value:" "$before_value"
      printf "${YELLOW}  %-13s %s${NC}\n" "Code value:" "$after_value"
      ((TOTAL_DIFFS++))
    fi

    # Value exists only in state
    if [ ! -z "$before_value" ] && [ -z "$after_value" ]; then
      echo -e "${RED}In namespace ${namespace}, vault ${vault_name}, key ${key} doesn’t exist in code: $before_value${NC}"
      ((TOTAL_STATE_ONLY++))
    fi

    # Value exists only in code
    if [ -z "$before_value" ] && [ ! -z "$after_value" ]; then
      echo -e "${BLUE}In namespace ${namespace}, vault ${vault_name}, key ${key} only exists in code: $after_value${NC}"
      ((TOTAL_CODE_ONLY++))
    fi
  done
}

if ! jq -e '.resource_changes | length > 0' "$PLAN_FILE" >/dev/null; then
  echo -e "${BLUE}No changes found in plan${NC}"
  exit 0
fi

while read -r resource; do
  before_data=$(echo "$resource" | jq -r '.change.before.data // {}')
  after_data=$(echo "$resource" | jq -r '.change.after.data // {}')

  compare_data "$before_data" "$after_data" "$resource"
done < <(jq -c '.resource_changes[] | select(.change.actions[] | contains("update"))' "$PLAN_FILE")

echo -e "\n${NC}=== Drift Summary ===${NC}"
echo -e "${YELLOW}Modified values: $TOTAL_DIFFS${NC}"
echo -e "${RED}Values only in state: $TOTAL_STATE_ONLY${NC}"
echo -e "${BLUE}Values only in code: $TOTAL_CODE_ONLY${NC}"
echo -e "Total drifts: $((TOTAL_DIFFS + TOTAL_STATE_ONLY + TOTAL_CODE_ONLY))"
