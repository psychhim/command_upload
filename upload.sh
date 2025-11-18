#!/usr/bin/env bash
# upload.sh - upload a file with POST, print URL

set -euo pipefail

UPLOAD_URL="https://user:pass@upload.freedoms4.top/index.php"
HISTORY_FILE="$HOME/.uploaded_files.txt"
COPY_TO_CLIPBOARD=false
USE_COLOR=true
MAX_JOBS=10

# FUNCTIONS
print_usage() {
  cat <<USAGE
Usage: $0 [options] -f <file>

Options:
  -f, --file PATH           File to upload
  -u, --user USER:PASS      HTTP Basic auth (curl --user)
  -H, --header "K: V"       Additional header
  -F, --field name=value    Additional form field
  -U, --url URL             Override upload URL
  -c, --clipboard           Copy URL to clipboard
  -r, --recent              Show all history entries
  -C, --check               Check uploads status (active/expired)
  -a, --active              Show only active uploads (use with --check)
  -e, --expired             Show only expired uploads (use with --check)
  -d, --delete 				Delete uploaded file by URL or uploaded file name
  --no-color                Disable colored output
  -h, --help                Show this help
USAGE
}

# COLORS
set_colors() {
  if $USE_COLOR; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    ORANGE='\033[0;33m'
    BOLD='\033[1m'
    RESET='\033[0m'
  else
    RED=''
    GREEN=''
    ORANGE=''
    BOLD=''
    RESET=''
  fi
}

# ASYNC URL CHECK with bracket/space/parenthesis encoding
check_url() {
  local timestamp="$1"
  local filename="$2"
  local url="$3"

  # Encode spaces, brackets, parentheses
  url="${url// /%20}"
  url="${url//[/\%5B}"
  url="${url//]/%5D}"
  url="${url//\(/%28}"
  url="${url//\)/%29}"

  status=$(curl -s -o /dev/null -w "%{http_code}" -L "$url" || echo 0)
  if [[ "$status" == "200" ]]; then
    echo "ACTIVE|$timestamp|$filename|$url"
  else
    echo "EXPIRED|$timestamp|$filename|$url"
  fi
}

show_recent() {
  [[ ! -f "$HISTORY_FILE" ]] && { echo "No history found."; return; }
  echo -e "${BOLD}Recent uploads:${RESET}"
  cat "$HISTORY_FILE"
}

show_async() {
  [[ ! -f "$HISTORY_FILE" ]] && { echo "No history found."; return; }

  active_urls=()
  expired_urls=()
  pids=()
  tmp_output=$(mktemp)
  trap 'rm -f "$tmp_output"' EXIT

  while IFS= read -r line; do
    timestamp=$(echo "$line" | cut -d'|' -f1 | xargs)
    filename=$(echo "$line" | cut -d'|' -f2 | xargs)
    url=$(echo "$line" | cut -d'|' -f3 | xargs)

    {
      check_url "$timestamp" "$filename" "$url"
    } >> "$tmp_output" &

    pids+=($!)
    while (( ${#pids[@]} >= MAX_JOBS )); do
      for i in "${!pids[@]}"; do
        if ! kill -0 "${pids[i]}" 2>/dev/null; then
          wait "${pids[i]}"
          unset 'pids[i]'
        fi
      done
      sleep 0.05
    done
  done < "$HISTORY_FILE"

  wait

  # Read tmp_output and separate
  while IFS= read -r line; do
    status=$(echo "$line" | cut -d'|' -f1)
    content=$(echo "$line" | cut -d'|' -f2-)
    if [[ "$status" == "ACTIVE" ]]; then
      active_urls+=("$content")
    else
      expired_urls+=("$content")
    fi
  done < "$tmp_output"

  # Sort arrays by timestamp (first field)
  IFS=$'\n' active_urls=($(printf "%s\n" "${active_urls[@]}" | sort))
  IFS=$'\n' expired_urls=($(printf "%s\n" "${expired_urls[@]}" | sort))

  # Print in groups with colors
  if [[ "$CHECK_ACTIVE" == true ]] || [[ "$CHECK_ACTIVE" == false && "$CHECK_EXPIRED" == false ]]; then
    echo -e "${BOLD}Active uploads:${RESET}"
    for line in "${active_urls[@]}"; do
      echo -e "${GREEN}${line}${RESET}"
    done
  fi

  if [[ "$CHECK_EXPIRED" == true ]] || [[ "$CHECK_ACTIVE" == false && "$CHECK_EXPIRED" == false ]]; then
    echo -e "${BOLD}Expired uploads:${RESET}"
    for line in "${expired_urls[@]}"; do
      echo -e "${RED}${line}${RESET}"
    done
  fi
}

# ARGUMENTS
USER_AUTH=""
declare -a HEADERS
declare -a FIELDS
FILE=""
SHOW_RECENT=false
CHECK=false
CHECK_ACTIVE=false
CHECK_EXPIRED=false
DELETE_URL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--file) FILE="$2"; shift 2 ;;
    -u|--user) USER_AUTH="$2"; shift 2 ;;
    -H|--header) HEADERS+=("$2"); shift 2 ;;
    -F|--field) FIELDS+=("$2"); shift 2 ;;
    -U|--url) UPLOAD_URL="$2"; shift 2 ;;
    -c|--clipboard) COPY_TO_CLIPBOARD=true; shift ;;
    -r|--recent) SHOW_RECENT=true; shift ;;
    -C|--check) CHECK=true; shift ;;
    -a|--active) CHECK_ACTIVE=true; shift ;;
    -e|--expired) CHECK_EXPIRED=true; shift ;;
    -d|--delete) DELETE_URL="$2"; shift 2 ;;
    --no-color) USE_COLOR=false; shift ;;
    -h|--help) print_usage; exit 0 ;;
    --) shift; break ;;
    -*)
      echo "Unknown option: $1" >&2
      print_usage
      exit 2 ;;
    *)
      [[ -z "$FILE" ]] && { FILE="$1"; shift; } || { echo "Unexpected argument: $1" >&2; print_usage; exit 2; }
      ;;
  esac
done

set_colors

# RECENT / CHECK FLAGS
if $SHOW_RECENT; then
  show_recent
  exit 0
fi

if $CHECK; then
  show_async
  exit 0
fi

# DELETE MODE
if [[ -n "$DELETE_URL" ]]; then
  file_to_delete="$(basename "$DELETE_URL")"
  echo -e "${ORANGE}Deleting: $DELETE_URL${RESET}" >&2

  if [[ "$UPLOAD_URL" =~ ^https?://([^/@]+)@ ]]; then
    USER_AUTH="${BASH_REMATCH[1]}"
    UPLOAD_URL_CLEAN="${UPLOAD_URL/\/\/$USER_AUTH@/\/\/}"
  else
    UPLOAD_URL_CLEAN="$UPLOAD_URL"
  fi

  delete_response=$(curl -s -F "delete=$file_to_delete" "$UPLOAD_URL_CLEAN" ${USER_AUTH:+-u "$USER_AUTH"} || true)

  if [[ "$delete_response" == *"Deleted successfully"* ]]; then
    echo -e "${GREEN}Deleted successfully.${RESET}"
    exit 0
  else
    echo -e "${RED}Delete failed.${RESET}"
    echo "Server response: $delete_response"
    exit 5
  fi
fi

# VALIDATION OF FILE
if [[ -z "$FILE" ]]; then
  echo "Error: file is required." >&2
  print_usage
  exit 2
fi
[[ ! -f "$FILE" ]] && { echo "Error: file not found: $FILE" >&2; exit 3; }

# UPLOAD
declare -a CURL_OPTS
CURL_OPTS+=( -s )
[[ -n "$USER_AUTH" ]] && CURL_OPTS+=( --user "$USER_AUTH" )
for h in "${HEADERS[@]}"; do CURL_OPTS+=( --header "$h" ); done
for f in "${FIELDS[@]}"; do CURL_OPTS+=( --form "$f" ); done
CURL_OPTS+=( --form "file=@${FILE}" )

response="$(curl "${CURL_OPTS[@]}" "$UPLOAD_URL" 2>/dev/null || true)"
link="$(printf '%s\n' "$response" | perl -nle 'if (m{https?://.*}) { $url=$&; $url=~s/ /%20/g; print $url; exit }')"

if [[ -n "$link" ]]; then
  >&2 echo -e "${GREEN}Upload successful!${RESET}"
  echo "$link"

  # CLIPBOARD
  if $COPY_TO_CLIPBOARD; then
    if command -v xclip >/dev/null 2>&1; then
      echo -n "$link" | xclip -selection clipboard
      >&2 echo -e "${ORANGE}Link copied to clipboard.${RESET}"
    elif command -v pbcopy >/dev/null 2>&1; then
      echo -n "$link" | pbcopy
      >&2 echo -e "${ORANGE}Copied to clipboard.${RESET}"
    else
      >&2 echo "Clipboard copy requested, but no clipboard utility found."
    fi
  fi

  # SAVE TO HISTORY
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  filename="$(basename "$FILE")"
  mkdir -p "$(dirname "$HISTORY_FILE")"
  echo "$timestamp | $filename | $link" >> "$HISTORY_FILE"
  tail -n 100 "$HISTORY_FILE" > "$HISTORY_FILE.tmp" && mv "$HISTORY_FILE.tmp" "$HISTORY_FILE"

  exit 0
else
  >&2 echo "Upload failed or no URL found in server response."
  >&2 echo "---- server response ----"
  >&2 printf '%s\n' "$response"
  >&2 echo "-------------------------"
  exit 4
fi
