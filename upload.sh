#!/usr/bin/env bash
# upload.sh - upload a file with POST, print URL

set -euo pipefail

UPLOAD_URL="https://user:pass@upload.freedoms4.top/index.php"
HISTORY_FILE="$HOME/.uploaded_files.txt"
COPY_TO_CLIPBOARD=false
USE_COLOR=true
MAX_JOBS=10
TAKE_SCREENSHOT=false
FULL_SCREENSHOT=false
PASTEBIN_MODE=false

# FUNCTIONS
print_usage() {
  cat <<USAGE
Usage: $0 [options] -f <file>
       <command> | $0 [options] -p

Options:
  -f, --file PATH           File to upload
  -p, --pastebin            Read from stdin and upload as text file
  -u, --user USER:PASS      HTTP Basic auth (curl --user)
  -H, --header "K: V"       Additional header
  -F, --field name=value    Additional form field
  -U, --url URL             Override upload URL
  -c, --clipboard           Copy URL to clipboard
  -r, --recent              Show all history entries
  -C, --check               Check uploads status (active/expired)
  -a, --active              Show only active uploads (use with --check)
  -e, --expired             Show only expired uploads (use with --check)
  -d, --delete              Delete uploaded file(s) by URL or filename

  ### SCREENSHOT
  -s, --screenshot          Take a screenshot (grim + slurp) and upload it
                   --full   With --screenshot: Takes a FULL screenshot (no slurp)

  --no-color                Disable colored output
  -h, --help                Show this help

Examples:
  # To upload: $0 -u user:pass -f file.png -c 
  # Pastebin: cat log.txt | $0 -p
              echo "Hello World" | $0 -p -c 
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

# GENERATE RANDOM FILENAME
generate_random_name() {
  # Use a subshell to avoid pipefail issues
  (
    set +o pipefail
    tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 12
  )
}

# ASYNC URL CHECK
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
DELETE_URLS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--file) FILE="$2"; shift 2 ;;
    -p|--pastebin) PASTEBIN_MODE=true; shift ;;
    -u|--user) USER_AUTH="$2"; shift 2 ;;
    -H|--header) HEADERS+=("$2"); shift 2 ;;
    -F|--field) FIELDS+=("$2"); shift 2 ;;
    -U|--url) UPLOAD_URL="$2"; shift 2 ;;
    -c|--clipboard) COPY_TO_CLIPBOARD=true; shift ;;
    -r|--recent) SHOW_RECENT=true; shift ;;
    -C|--check) CHECK=true; shift ;;
    -a|--active) CHECK_ACTIVE=true; shift ;;
    -e|--expired) CHECK_EXPIRED=true; shift ;;
    -d|--delete)
      shift
      while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do
        DELETE_URLS+=("$1")
        shift
      done
      ;;
    -s|--screenshot) TAKE_SCREENSHOT=true; shift ;;
    --full) FULL_SCREENSHOT=true; shift ;;
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

# DELETE
if (( ${#DELETE_URLS[@]} > 0 )); then
  echo -n "Deleting:"
  for d in "${DELETE_URLS[@]}"; do
    echo -n " $(basename "$d")"
  done
  echo
  echo

  pids=()
  tmp_output=$(mktemp)
  trap 'rm -f "$tmp_output"' EXIT

  for del in "${DELETE_URLS[@]}"; do
    (
      file_to_delete="$(basename "$del")"

      if [[ "$UPLOAD_URL" =~ ^https?://([^/@]+)@ ]]; then
        USER_AUTH="${BASH_REMATCH[1]}"
        UPLOAD_URL_CLEAN="${UPLOAD_URL/\/\/$USER_AUTH@/\/\/}"
      else
        UPLOAD_URL_CLEAN="$UPLOAD_URL"
      fi

      delete_response=$(curl -s -F "delete=$file_to_delete" "$UPLOAD_URL_CLEAN" ${USER_AUTH:+-u "$USER_AUTH"} || true)

      if [[ "$delete_response" == *"Deleted successfully"* ]]; then
        echo "OK|$file_to_delete" >> "$tmp_output"
      else
        echo "FAIL|$file_to_delete|$delete_response" >> "$tmp_output"
      fi
    ) &

    pids+=($!)

    # Limit of concurrency
    while (( ${#pids[@]} >= MAX_JOBS )); do
      for i in "${!pids[@]}"; do
        if ! kill -0 "${pids[i]}" 2>/dev/null; then
          unset 'pids[i]'
        fi
      done
      sleep 0.05
    done
  done

  wait

  successful=()
  failed=()

  while IFS= read -r line; do
    status=$(echo "$line" | cut -d'|' -f1)
    file=$(echo "$line" | cut -d'|' -f2)
    rest=$(echo "$line" | cut -d'|' -f3-)

    if [[ $status == "OK" ]]; then
      successful+=("$file")
    else
      failed+=("$file|$rest")
    fi
  done < "$tmp_output"

  echo -e "${GREEN}Successful deletions:${RESET}"
  if (( ${#successful[@]} > 0 )); then
    for f in "${successful[@]}"; do
      echo "  $f"
    done
  else
    echo "  (none)"
  fi

  echo
  echo -e "${RED}Unsuccessful deletions:${RESET}"
  if (( ${#failed[@]} > 0 )); then
    for f in "${failed[@]}"; do
      fname=${f%%|*}
      msg=${f#*|}
      echo "  $fname"
      echo "    Server: $msg"
    done
  else
    echo "  (none)"
  fi

  exit 0
fi

# PASTEBIN
if $PASTEBIN_MODE; then
  # Check if input is being piped
  if [[ -t 0 ]]; then
    >&2 echo "Error: --pastebin requires piped input."
    >&2 echo "Usage: <command> | $0 -p"
    >&2 echo "Example: echo 'hello' | $0 -p"
    exit 1
  fi
  
  random_name="$(generate_random_name)"
  temp_file="/tmp/${random_name}.txt"
  
  # Ensure cleanup on exit
  trap 'rm -f "$temp_file"' EXIT
  
  # Read all stdin into the temp file
  cat > "$temp_file" || {
    >&2 echo "Error: failed to read stdin."
    exit 1
  }
  
  if [[ ! -s "$temp_file" ]]; then
    >&2 echo "Error: no input received."
    exit 1
  fi
  
  FILE="$temp_file"
fi

# SCREENSHOT
if $TAKE_SCREENSHOT; then
  if ! command -v grim >/dev/null 2>&1; then
    echo "Error: grim is required for --screenshot." >&2
    exit 1
  fi
  if ! $FULL_SCREENSHOT && ! command -v slurp >/dev/null 2>&1; then
    echo "Error: slurp is required unless using --full." >&2
    exit 1
  fi

  ts="$(date '+%Y-%m-%d %H-%M-%S')"
  screenshot_name="Screenshot From ${ts}.png"
  screenshot_path="/tmp/$screenshot_name"

  if $FULL_SCREENSHOT; then
    echo "Taking FULL screenshot in 2 seconds..."
    sleep 2
    grim "$screenshot_path"
  else
    echo "Select area for screenshot..."
    grim -g "$(slurp)" "$screenshot_path"
  fi

  if [[ ! -f "$screenshot_path" ]]; then
    echo "Error: screenshot failed." >&2
    exit 1
  fi

  FILE="$screenshot_path"
  echo "Screenshot saved to: $FILE"
fi

# VALIDATION OF FILE
if [[ -z "$FILE" ]]; then
  # Check if stdin is being piped
  if [[ ! -t 0 ]]; then
    echo "Error: detected piped input but missing -p flag." >&2
    echo "Usage: <command> | $0 -p" >&2
    echo "Example: cat file.txt | $0 -p" >&2
    exit 2
  fi
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
    if command -v wl-copy >/dev/null 2>&1; then
      echo -n "$link" | wl-copy --type text/plain
      >&2 echo -e "${ORANGE}Link copied to clipboard.${RESET}"
    elif command -v xclip >/dev/null 2>&1; then
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
  url_filename="$(basename "$link")"
  mkdir -p "$(dirname "$HISTORY_FILE")"
  echo "$timestamp | $url_filename | $link" >> "$HISTORY_FILE"
  tail -n 100 "$HISTORY_FILE" > "$HISTORY_FILE.tmp" && mv "$HISTORY_FILE.tmp" "$HISTORY_FILE"

  exit 0
else
  >&2 echo "Upload failed or no URL found in server response."
  >&2 echo "---- server response ----"
  >&2 printf '%s\n' "$response"
  >&2 echo "-------------------------"
  exit 4
fi
