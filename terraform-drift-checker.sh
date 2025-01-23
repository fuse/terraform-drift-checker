#!/usr/bin/env bash

YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

if [ ! -f "plan.out.json" ]; then
  echo "Fichier 'plan.out.json' introuvable. Génération du plan Terraform..."
  terraform plan -out=plan.out
  terraform show -json plan.out >plan.out.json
fi

compare_data() {
  local before="$1"
  local after="$2"
  local resource_name="$3"

  local all_keys=$(echo "$before $after" | jq -r 'to_entries | .[].key' | sort -u)

  for key in $all_keys; do
    before_value=$(echo "$before" | jq -r ".$key // \"\"")
    after_value=$(echo "$after" | jq -r ".$key // \"\"")

    # Value differs
    if [ ! -z "$before_value" ] && [ ! -z "$after_value" ] && [ "$before_value" != "$after_value" ]; then
      echo -e "${YELLOW}[$resource_name] Value differs for '$key':${NC}"
      echo -e "${YELLOW}  Actual value: $before_value${NC}"
      echo -e "${YELLOW}  Code value:  $after_value${NC}"
    fi

    # Value exists only in state
    if [ ! -z "$before_value" ] && [ -z "$after_value" ]; then
      echo -e "${RED}[$resource_name] Value exists only in state for '$key': $before_value${NC}"
    fi

    # Value exists only in code
    if [ -z "$before_value" ] && [ ! -z "$after_value" ]; then
      echo -e "${BLUE}[$resource_name] Value exists only in code for '$key': $after_value${NC}"
    fi
  done
}

jq -c '.resource_changes[] | select(.change.actions[] | contains("update"))' plan.out.json | while read -r resource; do
  resource_name=$(echo "$resource" | jq -r '.address')
  before_data=$(echo "$resource" | jq -r '.change.before.data // {}')
  after_data=$(echo "$resource" | jq -r '.change.after.data // {}')

  compare_data "$before_data" "$after_data" "$resource_name"
done
