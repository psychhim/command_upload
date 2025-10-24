#!/usr/bin/env bash
# upload.sh - upload a file with POST, print URL

set -euo pipefail

UPLOAD_URL="https://upload.freedoms4.top"
HISTORY_FILE="$HOME/.uploaded_files.txt"
COPY_TO_CLIPBOARD=false
USE_COLOR=true

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

# HISTORY
url_encode() {
  local url="$1"
  # Encode special characters in URL, except safe ones
  python3 -c "import urllib.parse; print(urllib.parse.quote('''$url''', safe=':/?&=#'))"
}

check_url_alive() {
  local url="$1"
  local encoded
  encoded=$(url_encode "$url")
  local status
  status=$(curl -s -o /dev/null -w "%{http_code}" -L "$encoded")
  [[ "$status" == "200" ]]
}

show_active() {
  [[ ! -f "$HISTORY_FILE" ]] && { echo "No history found."; return; }
  echo -e "${BOLD}Active uploads:${RESET}"
  while IFS='|' read -r timestamp filename url; do
    url="$(echo "$url" | xargs)"
    if check_url_alive "$url"; then
      echo -e "${GREEN}${timestamp} | ${filename} | ${url}${RESET}"
    fi
  done < "$HISTORY_FILE"
}

show_expired() {
  [[ ! -f "$HISTORY_FILE" ]] && { echo "No history found."; return; }
  echo -e "${BOLD}Expired uploads:${RESET}"
  while IFS='|' read -r timestamp filename url; do
    url="$(echo "$url" | xargs)"
    if ! check_url_alive "$url"; then
      echo -e "${RED}${timestamp} | ${filename} | ${url}${RESET}"
    fi
  done < "$HISTORY_FILE"
}

show_all() {
  show_active
  echo
  show_expired
}

show_active_only() { show_active; }
show_expired_only() { show_expired; }

show_recent() {
  [[ ! -f "$HISTORY_FILE" ]] && { echo "No history found."; return; }
  echo -e "${BOLD}Recent uploads:${RESET}"
  cat "$HISTORY_FILE"
}

# ARG
USER_AUTH=""
declare -a HEADERS
declare -a FIELDS
FILE=""
SHOW_RECENT=false
CHECK=false
CHECK_ACTIVE=false
CHECK_EXPIRED=false

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

# RECENT/CHECK FLAGS
if $SHOW_RECENT; then
  show_recent
  exit 0
fi

if $CHECK; then
  if $CHECK_ACTIVE && $CHECK_EXPIRED; then
    show_all
  elif $CHECK_ACTIVE; then
    show_active_only
  elif $CHECK_EXPIRED; then
    show_expired_only
  else
    show_all
  fi
  exit 0
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
