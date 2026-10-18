#!/bin/sh
set -eu
umask 077

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

# An optional application name requests rotation
[ "$#" -le 1 ] || fail 'Expected at most one application name.'
rotate=${1:-}
case "$rotate" in
  ''|app-a|app-b) ;;
  *) fail 'Unknown application.' ;;
esac

directory=/var/lib/lab-secrets
config=$(mktemp /tmp/kong.yml.XXXXXX)
temporary_key=''
trap 'rm -f "$config"; if [ -n "$temporary_key" ]; then rm -f "$temporary_key"; fi' 0
trap 'exit 1' HUP INT TERM
cat /tmp/routes.yml > "$config"
printf '\nconsumers:\n' >> "$config"

for name in app-a app-b; do
  file="$directory/$name.key"
  # Fail on unexpected links or unreadable files rather than replacing credentials.
  [ ! -L "$file" ] || fail 'Credential must not be a symbolic link.'
  if [ -e "$file" ]; then
    [ -f "$file" ] && [ -r "$file" ] || fail 'Credential must be a readable regular file.'
    key=$(cat "$file")
  else
    key=$(openssl rand -hex 32)
  fi
  case "$key" in
    ''|*[!0-9a-f]*) fail 'Invalid credential format.' ;;
  esac
  [ "${#key}" -eq 64 ] || fail 'Invalid credential length.'

  if [ "$rotate" = "$name" ]; then
    key=$(openssl rand -hex 32)
  fi

  if [ ! -e "$file" ] || [ "$rotate" = "$name" ]; then
    temporary_key=$(mktemp "$directory/.key.XXXXXX")
    printf '%s' "$key" > "$temporary_key"
    mv -f "$temporary_key" "$file"
    temporary_key=''
  fi

  # Validated hexadecimal values are safe inside YAML single-quoted strings.
  printf "  - username: %s\n    keyauth_credentials:\n      - key: '%s'\n" "$name" "$key" >> "$config"
done

# Readers see a complete config; updating it does not reload the running gateway.
mv -f "$config" /tmp/kong.yml
