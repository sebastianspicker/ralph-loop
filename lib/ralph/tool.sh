# shellcheck shell=bash
# shellcheck disable=SC2034

normalize_tool_name() {
  local raw="$1"
  case "$raw" in
    codex|codex-cli)
      printf 'codex'
      ;;
    *)
      printf '%s' "$raw"
      ;;
  esac
}

is_supported_tool() {
  case "$1" in
    codex) return 0 ;;
    *) return 1 ;;
  esac
}

validate_tool_config() {
  TOOL="$(normalize_tool_name "$TOOL")"
  is_supported_tool "$TOOL" || fail "Tool must be one of: $SUPPORTED_TOOLS_HINT (got: $TOOL)"
}

selected_tool_cmd() {
  case "$TOOL" in
    codex)
      printf 'codex'
      ;;
    *)
      fail "Unsupported tool selected: $TOOL"
      ;;
  esac
}

require_selected_tool_cmd() {
  local cmd
  cmd="$(selected_tool_cmd)"
  require_cmd "$cmd"
}
