#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

VERSION="${1:?version is required}"
DATASET_KEY="${2:?dataset is required}"

require_command curl

load_stack_env "$VERSION" "$DATASET_KEY"
require_command jq
mkdir -p "$STACK_STATE_DIR"

SEED_CONTENT_VERSION="4"

api_request() {
  local method="$1"
  local endpoint="$2"
  local payload="${3:-}"

  if [[ -n "$payload" ]]; then
    curl -fsS -X "$method" \
      "http://127.0.0.1:${METABASE_PORT}${endpoint}" \
      -H "Content-Type: application/json" \
      -H "x-api-key: ${MB_AUTOMATION_API_KEY}" \
      -d "$payload"
  else
    curl -fsS -X "$method" \
      "http://127.0.0.1:${METABASE_PORT}${endpoint}" \
      -H "x-api-key: ${MB_AUTOMATION_API_KEY}"
  fi
}

echo "Waiting for config-driven API key to become active"
attempt=0
# The config file creates the API key during Metabase startup; wait until it can authenticate requests.
until api_request GET "/api/user/current" >/dev/null 2>&1; do
  attempt=$((attempt + 1))
  if [[ $attempt -ge 30 ]]; then
    echo "Metabase API key did not become active in time." >&2
    exit 1
  fi
  sleep 2
done

users_json="$(api_request GET "/api/user")"

items_array_filter='if type == "array" then . elif type == "object" and (.data | type? == "array") then .data else [] end'

user_id_by_email() {
  local email="$1"
  echo "$users_json" | jq -r --arg email "$email" "$items_array_filter | .[] | select(.email == \$email) | .id" | head -n 1
}

groups_json="$(api_request GET "/api/permissions/group")"

ensure_group() {
  local group_name="$1"
  local group_id
  group_id="$(echo "$groups_json" | jq -r --arg name "$group_name" "$items_array_filter | .[] | select(.name == \$name) | .id" | head -n 1)"

  if [[ -n "$group_id" ]]; then
    echo "$group_id"
    return
  fi

  group_id="$(api_request POST "/api/permissions/group" "{\"name\":\"${group_name}\"}" | jq -r '.id')"
  groups_json="$(api_request GET "/api/permissions/group")"
  echo "$group_id"
}

ensure_membership() {
  local user_id="$1"
  local group_id="$2"
  local already_member
  already_member="$(api_request GET "/api/permissions/group/${group_id}" | jq -r --argjson uid "$user_id" '.members[]? | select(.user_id == $uid) | .user_id')"
  if [[ -n "$already_member" ]]; then
    return
  fi
  local payload
  payload="{\"user_id\":${user_id},\"group_id\":${group_id}}"
  api_request POST "/api/permissions/membership" "$payload" >/dev/null
}

collection_id_by_name() {
  local collection_name="$1"
  api_request GET "/api/search?q=${collection_name// /%20}" | jq -r --arg name "$collection_name" '.data[]? | select(.model == "collection" and .name == $name) | .id' | head -n 1
}

update_collection() {
  local collection_id="$1"
  local collection_name="$2"
  local description="$3"
  local payload

  payload="$(jq -nc --arg name "$collection_name" --arg description "$description" '{name: $name, description: $description}')"
  api_request PUT "/api/collection/${collection_id}" "$payload" >/dev/null
}

collection_item_id_by_name() {
  local collection_id="$1"
  local model="$2"
  local item_name="$3"

  api_request GET "/api/collection/${collection_id}/items" | jq -r --arg model "$model" --arg name "$item_name" '.data[]? | select(.model == $model and .name == $name) | .id' | head -n 1
}

wait_for_database_id_by_name() {
  local database_name="$1"
  local attempt=0
  local found_id

  while :; do
    found_id="$(api_request GET "/api/database" | jq -r --arg name "$database_name" '.data[]? | select(.name == $name) | .id' | head -n 1)"
    if [[ -n "$found_id" ]]; then
      echo "$found_id"
      return 0
    fi

    attempt=$((attempt + 1))
    if [[ $attempt -ge 30 ]]; then
      echo "Expected sample database connection named ${database_name} was not found." >&2
      return 1
    fi

    sleep 2
  done
}

ensure_cache_policy() {
  local model="$1"
  local model_id="$2"
  local duration="$3"
  local unit="$4"
  local refresh_automatically="$5"
  local payload

  payload="$(jq -nc \
    --arg model "$model" \
    --argjson model_id "$model_id" \
    --argjson duration "$duration" \
    --arg unit "$unit" \
    --argjson refresh_automatically "$refresh_automatically" \
    '{model: $model, model_id: $model_id, strategy: {type: "duration", duration: $duration, unit: $unit, refresh_automatically: $refresh_automatically}}')"

  api_request PUT "/api/cache" "$payload" >/dev/null
}

ensure_cache_policy "root" 0 "$DEFAULT_CACHE_POLICY_DURATION" "$DEFAULT_CACHE_POLICY_UNIT" "$DEFAULT_CACHE_POLICY_REFRESH_AUTOMATICALLY"
database_id="$(wait_for_database_id_by_name "$SAMPLE_DB_DISPLAY_NAME")"
ensure_cache_policy "database" "$database_id" "$DATABASE_CACHE_POLICY_DURATION" "$DATABASE_CACHE_POLICY_UNIT" "$DATABASE_CACHE_POLICY_REFRESH_AUTOMATICALLY"

current_seed_content_version=""
if [[ -f "$METABASE_SEED_MARKER" ]]; then
  current_seed_content_version="$(<"$METABASE_SEED_MARKER")"
fi

# Skip content reconciliation only when the seed version already matches.
if [[ "$current_seed_content_version" == "$SEED_CONTENT_VERSION" && "${FORCE:-0}" != "1" ]]; then
  echo "Seed marker version ${SEED_CONTENT_VERSION} found for ${COMPOSE_PROJECT_NAME}. Cache policy reconciled; skipping content reseed."
  exit 0
fi

create_card_if_missing() {
  local card_name="$1"
  local display="$2"
  local description="$3"
  local dataset_query="$4"
  local existing_card_id
  local payload

  existing_card_id="$(collection_item_id_by_name "$starter_collection_id" "card" "$card_name")"
  if [[ -n "$existing_card_id" ]]; then
    echo "$existing_card_id"
    return
  fi

  payload="$(jq -nc \
    --arg name "$card_name" \
    --arg description "$description" \
    --arg display "$display" \
    --argjson collection_id "$starter_collection_id" \
    --argjson dataset_query "$dataset_query" \
    '{name: $name, description: $description, display: $display, collection_id: $collection_id, dataset_query: $dataset_query, visualization_settings: {}}')"

  api_request POST "/api/card" "$payload" | jq -r '.id'
}

refresh_database_metadata() {
  database_metadata_json="$(api_request GET "/api/database/${database_id}/metadata")"
}

table_id_by_name() {
  local table_name="$1"
  echo "$database_metadata_json" | jq -r --arg table_name "$table_name" '.tables[]? | select((.name | ascii_downcase) == ($table_name | ascii_downcase)) | .id' | head -n 1
}

field_id_by_name() {
  local table_name="$1"
  local field_name="$2"
  echo "$database_metadata_json" | jq -r --arg table_name "$table_name" --arg field_name "$field_name" '.tables[]? | select((.name | ascii_downcase) == ($table_name | ascii_downcase)) | .fields[]? | select((.name | ascii_downcase) == ($field_name | ascii_downcase)) | .id' | head -n 1
}

field_id_by_nfc_path() {
  local table_name="$1"
  local nfc_path_json="$2"
  echo "$database_metadata_json" | jq -r --arg table_name "$table_name" --argjson nfc_path "$nfc_path_json" '.tables[]? | select((.name | ascii_downcase) == ($table_name | ascii_downcase)) | .fields[]? | select(.nfc_path == $nfc_path) | .id' | head -n 1
}

add_card_to_dashboard() {
  local dashboard_id="$1"
  local card_id="$2"
  local row="$3"
  local col="$4"
  local size_x="$5"
  local size_y="$6"
  local dashboard_json
  local payload

  dashboard_json="$(api_request GET "/api/dashboard/${dashboard_id}")"
  if echo "$dashboard_json" | jq -e --argjson card_id "$card_id" '.dashcards[]? | select(.card_id == $card_id)' >/dev/null; then
    return
  fi

  payload="$(echo "$dashboard_json" | jq -c \
    --argjson card_id "$card_id" \
    --argjson row "$row" \
    --argjson col "$col" \
    --argjson size_x "$size_x" \
    --argjson size_y "$size_y" \
    '.dashcards = ((.dashcards // []) + [{id: -1, card_id: $card_id, row: $row, col: $col, size_x: $size_x, size_y: $size_y, parameter_mappings: [], visualization_settings: {}}])')"

  api_request PUT "/api/dashboard/${dashboard_id}" "$payload" >/dev/null
}

analytics_group_id="$(ensure_group "Analytics Team")"
sales_group_id="$(ensure_group "Sales Team")"

analyst_user_id="$(user_id_by_email "$MB_ANALYST_EMAIL")"
sales_user_id="$(user_id_by_email "$MB_SALES_EMAIL")"

if [[ -n "$analyst_user_id" ]]; then
  ensure_membership "$analyst_user_id" "$analytics_group_id"
fi

if [[ -n "$sales_user_id" ]]; then
  ensure_membership "$sales_user_id" "$sales_group_id"
fi

starter_collection_name="$SEED_COLLECTION_NAME"
starter_collection_description="Seeded starter content for ${SAMPLE_DB_DISPLAY_NAME}."
starter_collection_id="$(collection_id_by_name "$starter_collection_name")"

if [[ -z "$starter_collection_id" ]]; then
  legacy_collection_id="$(collection_id_by_name "Starter Pack")"
  if [[ -n "$legacy_collection_id" ]]; then
    update_collection "$legacy_collection_id" "$starter_collection_name" "$starter_collection_description"
    starter_collection_id="$legacy_collection_id"
  fi
fi

# Keep the seed idempotent: create the collection and starter card only if they are missing.
if [[ -z "$starter_collection_id" ]]; then
  starter_collection_id="$(api_request POST "/api/collection" "{\"name\":\"${starter_collection_name}\",\"description\":\"${starter_collection_description}\"}" | jq -r '.id')"
fi

question_name="Sample DB Connectivity Check"

if [[ -n "$database_id" ]]; then
  if [[ "$DATASET_KEY" == sample-mysql* ]]; then

    # ── MySQL content ──────────────────────────────────────────────────────────

    connectivity_query="$(jq -nc --argjson database "$database_id" \
      '{type: "native", native: {query: "select DATABASE() as db_name, NOW() as checked_at", "template-tags": {}}, database: $database}')"
    connectivity_card_id="$(create_card_if_missing "$question_name" "table" "Simple query proving the sample database is connected." "$connectivity_query")"

    metadata_attempt=0
    while :; do
      refresh_database_metadata
      orders_table_id="$(table_id_by_name "orders")"
      people_table_id="$(table_id_by_name "people")"
      products_table_id="$(table_id_by_name "products")"
      orders_created_at_field_id="$(field_id_by_name "orders" "created_at")"
      people_state_field_id="$(field_id_by_name "people" "state")"
      products_category_field_id="$(field_id_by_name "products" "category")"
      orders_total_field_id="$(field_id_by_name "orders" "total")"

      if [[ -n "$orders_table_id" && -n "$people_table_id" && -n "$products_table_id" && -n "$orders_created_at_field_id" && -n "$people_state_field_id" && -n "$products_category_field_id" && -n "$orders_total_field_id" ]]; then
        break
      fi

      metadata_attempt=$((metadata_attempt + 1))
      if [[ $metadata_attempt -ge 30 ]]; then
        echo "Sample database metadata did not finish syncing in time. Created SQL-only starter content." >&2
        break
      fi

      sleep 2
    done

    if [[ -n "$orders_table_id" && -n "$people_table_id" && -n "$products_table_id" && -n "$orders_created_at_field_id" && -n "$people_state_field_id" && -n "$products_category_field_id" && -n "$orders_total_field_id" ]]; then
      orders_by_month_query="$(jq -nc \
        --argjson database "$database_id" \
        --argjson source_table "$orders_table_id" \
        --argjson created_at_field "$orders_created_at_field_id" \
        '{type: "query", database: $database, query: {"source-table": $source_table, aggregation: [["count"]], breakout: [["field", $created_at_field, {"temporal-unit": "month"}]], "order-by": [["asc", ["field", $created_at_field, {"temporal-unit": "month"}]]]}}')"
      people_by_state_query="$(jq -nc \
        --argjson database "$database_id" \
        --argjson source_table "$people_table_id" \
        --argjson state_field "$people_state_field_id" \
        '{type: "query", database: $database, query: {"source-table": $source_table, aggregation: [["count"]], breakout: [["field", $state_field, null]], "order-by": [["desc", ["aggregation", 0]]], limit: 10}}')"
      products_by_category_query="$(jq -nc \
        --argjson database "$database_id" \
        --argjson source_table "$products_table_id" \
        --argjson category_field "$products_category_field_id" \
        '{type: "query", database: $database, query: {"source-table": $source_table, aggregation: [["count"]], breakout: [["field", $category_field, null]], "order-by": [["desc", ["aggregation", 0]]], limit: 10}}')"
      monthly_revenue_query="$(jq -nc --argjson database "$database_id" \
        '{type: "native", native: {query: "select DATE_FORMAT(created_at, '"'"'%Y-%m-01'"'"') as month,\n       count(*) as order_count,\n       round(sum(total), 2) as revenue\nfrom orders\ngroup by 1\norder by 1", "template-tags": {}}, database: $database}')"
      category_revenue_query="$(jq -nc --argjson database "$database_id" \
        '{type: "native", native: {query: "select p.category, count(*) as orders, round(sum(o.total), 2) as revenue\nfrom orders o\njoin products p on p.id = o.product_id\ngroup by 1\norder by revenue desc\nlimit 10", "template-tags": {}}, database: $database}')"
      state_field_filter_query="$(jq -nc \
        --argjson database "$database_id" \
        --argjson state_field "$people_state_field_id" \
        '{type: "native", database: $database, native: {query: "select count(distinct o.id), p.state\nfrom orders o\njoin people p on o.user_id = p.id\nwhere {{fltr_state}}\ngroup by p.state\norder by 1", "template-tags": {"fltr_state": {id: "2441fdaf-2ff8-4fc1-9103-8b4d40f72c85", name: "fltr_state", "display-name": "Fltr State", type: "dimension", "widget-type": "string/=", default: null, dimension: ["field", $state_field, null], alias: "p.state"}}}}')"
      orders_by_month_card_id="$(create_card_if_missing "Orders by Month" "line" "GUI question showing monthly order volume in ${SAMPLE_DB_DISPLAY_NAME}." "$orders_by_month_query")"
      people_by_state_card_id="$(create_card_if_missing "Customers by State" "bar" "GUI question showing where customers are concentrated." "$people_by_state_query")"
      products_by_category_card_id="$(create_card_if_missing "Products by Category" "row" "GUI question showing product catalog mix by category." "$products_by_category_query")"
      monthly_revenue_card_id="$(create_card_if_missing "Monthly Revenue" "line" "SQL question showing order count and revenue by month." "$monthly_revenue_query")"
      category_revenue_card_id="$(create_card_if_missing "Top Categories by Revenue" "bar" "SQL question showing which product categories drive revenue." "$category_revenue_query")"
      state_field_filter_card_id="$(create_card_if_missing "SQL Report with State Field Filter" "table" "SQL question showing a native field filter bound to People.State." "$state_field_filter_query")"

      dashboard_name="${SAMPLE_DB_DISPLAY_NAME} Overview"
      dashboard_id="$(collection_item_id_by_name "$starter_collection_id" "dashboard" "$dashboard_name")"
      if [[ -z "$dashboard_id" ]]; then
        dashboard_payload="$(jq -nc --arg name "$dashboard_name" --arg description "Seeded dashboard for ${SAMPLE_DB_DISPLAY_NAME}." --argjson collection_id "$starter_collection_id" '{name: $name, description: $description, collection_id: $collection_id, parameters: []}')"
        dashboard_id="$(api_request POST "/api/dashboard" "$dashboard_payload" | jq -r '.id')"
      fi

      add_card_to_dashboard "$dashboard_id" "$orders_by_month_card_id"      0  0 12 6
      add_card_to_dashboard "$dashboard_id" "$monthly_revenue_card_id"      0 12 12 6
      add_card_to_dashboard "$dashboard_id" "$people_by_state_card_id"      6  0  8 6
      add_card_to_dashboard "$dashboard_id" "$products_by_category_card_id" 6  8  8 6
      add_card_to_dashboard "$dashboard_id" "$category_revenue_card_id"     6 16  8 6
      add_card_to_dashboard "$dashboard_id" "$connectivity_card_id"        12  0  8 4
    fi

  else

    # ── Postgres content (existing) ────────────────────────────────────────────

    connectivity_query="$(jq -nc --argjson database "$database_id" '{type: "native", native: {query: "select current_database() as db_name, current_timestamp as checked_at;", "template-tags": {}}, database: $database}')"
    connectivity_card_id="$(create_card_if_missing "$question_name" "table" "Simple query proving the sample database is connected." "$connectivity_query")"

    metadata_attempt=0
    while :; do
      refresh_database_metadata
      orders_table_id="$(table_id_by_name "orders")"
      people_table_id="$(table_id_by_name "people")"
      person_profiles_json_table_id="$(table_id_by_name "person_profiles_json")"
      products_table_id="$(table_id_by_name "products")"
      orders_created_at_field_id="$(field_id_by_name "orders" "created_at")"
      people_state_field_id="$(field_id_by_name "people" "state")"
      people_id_field_id="$(field_id_by_name "people" "id")"
      person_profiles_person_id_field_id="$(field_id_by_name "person_profiles_json" "person_id")"
      person_profiles_dark_mode_field_id="$(field_id_by_nfc_path "person_profiles_json" '["profile_json","preferences","dark_mode"]')"
      products_category_field_id="$(field_id_by_name "products" "category")"
      orders_total_field_id="$(field_id_by_name "orders" "total")"

      if [[ -n "$orders_table_id" && -n "$people_table_id" && -n "$person_profiles_json_table_id" && -n "$products_table_id" && -n "$orders_created_at_field_id" && -n "$people_state_field_id" && -n "$people_id_field_id" && -n "$person_profiles_person_id_field_id" && -n "$person_profiles_dark_mode_field_id" && -n "$products_category_field_id" && -n "$orders_total_field_id" ]]; then
        break
      fi

      metadata_attempt=$((metadata_attempt + 1))
      if [[ $metadata_attempt -ge 30 ]]; then
        echo "Sample database metadata did not finish syncing in time. Created SQL-only starter content." >&2
        break
      fi

      sleep 2
    done

    if [[ -n "$orders_table_id" && -n "$people_table_id" && -n "$products_table_id" && -n "$orders_created_at_field_id" && -n "$people_state_field_id" && -n "$products_category_field_id" && -n "$orders_total_field_id" ]]; then
      orders_by_month_query="$(jq -nc \
        --argjson database "$database_id" \
        --argjson source_table "$orders_table_id" \
        --argjson created_at_field "$orders_created_at_field_id" \
        '{type: "query", database: $database, query: {"source-table": $source_table, aggregation: [["count"]], breakout: [["field", $created_at_field, {"temporal-unit": "month"}]], "order-by": [["asc", ["field", $created_at_field, {"temporal-unit": "month"}]]]}}')"
      people_by_state_query="$(jq -nc \
        --argjson database "$database_id" \
        --argjson source_table "$people_table_id" \
        --argjson state_field "$people_state_field_id" \
        '{type: "query", database: $database, query: {"source-table": $source_table, aggregation: [["count"]], breakout: [["field", $state_field, null]], "order-by": [["desc", ["aggregation", 0]]], limit: 10}}')"
      products_by_category_query="$(jq -nc \
        --argjson database "$database_id" \
        --argjson source_table "$products_table_id" \
        --argjson category_field "$products_category_field_id" \
        '{type: "query", database: $database, query: {"source-table": $source_table, aggregation: [["count"]], breakout: [["field", $category_field, null]], "order-by": [["desc", ["aggregation", 0]]], limit: 10}}')"
      monthly_revenue_query="$(jq -nc --argjson database "$database_id" '{type: "native", native: {query: "select date_trunc('"'"'month'"'"', created_at)::date as month, count(*) as order_count, round(sum(total)::numeric, 2) as revenue\nfrom orders\ngroup by 1\norder by 1;", "template-tags": {}}, database: $database}')"
      category_revenue_query="$(jq -nc --argjson database "$database_id" '{type: "native", native: {query: "select p.category, count(*) as orders, round(sum(o.total)::numeric, 2) as revenue\nfrom orders o\njoin products p on p.id = o.product_id\ngroup by 1\norder by revenue desc\nlimit 10;", "template-tags": {}}, database: $database}')"
      state_field_filter_query="$(jq -nc \
        --argjson database "$database_id" \
        --argjson state_field "$people_state_field_id" \
        '{type: "native", database: $database, native: {query: "select\n  count(distinct o.id), p.state\nfrom orders o\njoin people p on o.user_id = p.id\nwhere {{fltr_state}}\ngroup by p.state\norder by 1;", "template-tags": {"fltr_state": {id: "2441fdaf-2ff8-4fc1-9103-8b4d40f72c85", name: "fltr_state", "display-name": "Fltr State", type: "dimension", "widget-type": "string/=", default: null, dimension: ["field", $state_field, null], alias: "p.state"}}}}')"
      json_unfolding_example_query="$(jq -nc \
        --argjson database "$database_id" \
        --argjson people_table "$people_table_id" \
        --argjson person_profiles_json_table "$person_profiles_json_table_id" \
        --argjson people_id_field "$people_id_field_id" \
        --argjson person_profiles_person_id_field "$person_profiles_person_id_field_id" \
        --argjson person_profiles_dark_mode_field "$person_profiles_dark_mode_field_id" \
        '{type: "query", database: $database, query: {"source-table": $people_table, joins: [{strategy: "left-join", alias: "Person Profiles Json", "source-table": $person_profiles_json_table, fields: "none", condition: ["=", ["field", $people_id_field, null], ["field", $person_profiles_person_id_field, {"join-alias": "Person Profiles Json"}]]}], aggregation: [["count"]], breakout: [["field", $person_profiles_dark_mode_field, {"join-alias": "Person Profiles Json"}]]}}')"

      orders_by_month_card_id="$(create_card_if_missing "Orders by Month" "line" "GUI question showing monthly order volume in ${SAMPLE_DB_DISPLAY_NAME}." "$orders_by_month_query")"
      people_by_state_card_id="$(create_card_if_missing "Customers by State" "bar" "GUI question showing where customers are concentrated." "$people_by_state_query")"
      products_by_category_card_id="$(create_card_if_missing "Products by Category" "row" "GUI question showing product catalog mix by category." "$products_by_category_query")"
      monthly_revenue_card_id="$(create_card_if_missing "Monthly Revenue" "line" "SQL question showing order count and revenue by month." "$monthly_revenue_query")"
      category_revenue_card_id="$(create_card_if_missing "Top Categories by Revenue" "bar" "SQL question showing which product categories drive revenue." "$category_revenue_query")"
      state_field_filter_card_id="$(create_card_if_missing "SQL Report with State Field Filter" "table" "SQL question showing a native field filter bound to People.State." "$state_field_filter_query")"
      json_unfolding_example_card_id="$(create_card_if_missing "JSON Unfolding Example" "bar" "GUI question grouping people by the seeded profile dark mode preference." "$json_unfolding_example_query")"

      dashboard_name="${SAMPLE_DB_DISPLAY_NAME} Overview"
      dashboard_id="$(collection_item_id_by_name "$starter_collection_id" "dashboard" "$dashboard_name")"
      if [[ -z "$dashboard_id" ]]; then
        dashboard_payload="$(jq -nc --arg name "$dashboard_name" --arg description "Seeded dashboard for ${SAMPLE_DB_DISPLAY_NAME}." --argjson collection_id "$starter_collection_id" '{name: $name, description: $description, collection_id: $collection_id, parameters: []}')"
        dashboard_id="$(api_request POST "/api/dashboard" "$dashboard_payload" | jq -r '.id')"
      fi

      add_card_to_dashboard "$dashboard_id" "$orders_by_month_card_id" 0 0 12 6
      add_card_to_dashboard "$dashboard_id" "$monthly_revenue_card_id" 0 12 12 6
      add_card_to_dashboard "$dashboard_id" "$people_by_state_card_id" 6 0 8 6
      add_card_to_dashboard "$dashboard_id" "$products_by_category_card_id" 6 8 8 6
      add_card_to_dashboard "$dashboard_id" "$category_revenue_card_id" 6 16 8 6
      add_card_to_dashboard "$dashboard_id" "$connectivity_card_id" 12 0 8 4
    fi

  fi
fi

printf '%s\n' "$SEED_CONTENT_VERSION" > "$METABASE_SEED_MARKER"
echo "Metabase seed complete for ${COMPOSE_PROJECT_NAME}."
