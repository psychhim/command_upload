#!/usr/bin/env bash
# upload.sh - upload a file with POST, print the returned https:// link

set -euo pipefail

# Change the UPLOAD_URL to a desired one
UPLOAD_URL="https://upload.freedoms4.top"

COPY_TO_CLIPBOARD=false

print_usage() {
  cat <<USAGE
Usage: $0 [options] -f <file>

Options:
  -f, --file PATH         File to upload (required)
  -u, --user USER:PASS    HTTP Basic auth (pass to curl --user)
  -H, --header "K: V"     Additional header (can be repeated)
  -F, --field name=value  Additional form field (can be repeated)
  -U, --url URL           Override upload URL (default: $UPLOAD_URL)
  -c, --clipboard         Copy returned URL to clipboard
  -h, --help              Show this help
USAGE
}

# parse args
USER_AUTH=""
declare -a HEADERS
declare -a FIELDS
FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--file) FILE="$2"; shift 2 ;;
    -u|--user) USER_AUTH="$2"; shift 2 ;;
    -H|--header) HEADERS+=("$2"); shift 2 ;;
    -F|--field) FIELDS+=("$2"); shift 2 ;;
    -U|--url) UPLOAD_URL="$2"; shift 2 ;;
    -c|--clipboard) COPY_TO_CLIPBOARD=true; shift ;;
    -h|--help) print_usage; exit 0 ;;
    --) shift; break ;;
    -*)
      echo "Unknown option: $1" >&2
      print_usage
      exit 2
      ;;
    *)
      if [[ -z "$FILE" ]]; then
        FILE="$1"
        shift
      else
        echo "Unexpected argument: $1" >&2
        print_usage
        exit 2
      fi
      ;;
  esac
done
if [[ -z "$FILE" ]]; then
  echo "Error: file is required." >&2
  print_usage
  exit 2
fi
if [[ ! -f "$FILE" ]]; then
  echo "Error: file not found: $FILE" >&2
  exit 3
fi

# Build curl args
declare -a CURL_OPTS
CURL_OPTS+=( -s )
if [[ -n "$USER_AUTH" ]]; then
  CURL_OPTS+=( --user "$USER_AUTH" )
fi
for h in "${HEADERS[@]}"; do
  CURL_OPTS+=( --header "$h" )
done
for f in "${FIELDS[@]}"; do
  CURL_OPTS+=( --form "$f" )
done
CURL_OPTS+=( --form "file=@${FILE}" )

# Perform request and capture response
response="$(curl "${CURL_OPTS[@]}" "$UPLOAD_URL" 2>/dev/null || true)"

# Extract the URL
link="$(printf '%s\n' "$response" \
  | perl -nle 'if (m{https?://.*}) { $url=$&; $url=~s/ /%20/g; print $url; exit }')"
if [[ -n "$link" ]]; then
  >&2 echo "Upload successful!"
  echo "$link"
  if $COPY_TO_CLIPBOARD; then
    if command -v xclip >/dev/null 2>&1; then
      echo -n "$link" | xclip -selection clipboard
      >&2 echo "Copied to clipboard."
    elif command -v pbcopy >/dev/null 2>&1; then
      echo -n "$link" | pbcopy
      >&2 echo "Copied to clipboard."
    else
      >&2 echo "Clipboard copy requested, but no clipboard utility found (install xclip or pbcopy)."
    fi
  fi
  exit 0
else
  >&2 echo "Upload failed or no URL found in server response."
  >&2 echo "---- server response ----"
  >&2 printf '%s\n' "$response"
  >&2 echo "-------------------------"
  exit 4
fi
