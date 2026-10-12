#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  echo "Uso: $0 [ip-o-host] [utente-ssh-iniziale]" >&2
  echo "L'utente SSH iniziale predefinito è root." >&2
  echo "Se omesso, l'host viene letto da SSH_HOST in .env." >&2
  exit 2
}

[[ $# -le 2 ]] || usage
local_user=${USER:?La variabile USER locale non è impostata}
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
env_file="$project_dir/.env"

read_env_value() {
  local name=$1 line value
  [[ -f "$env_file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line=${line%$'\r'}
    [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?${name}[[:space:]]*= ]] || continue
    value=${line#*=}
    value=${value#"${value%%[![:space:]]*}"}
    value=${value%"${value##*[![:space:]]}"}
    if [[ ( "$value" == \'*\' && "$value" == *\' ) || ( "$value" == \"*\" && "$value" == *\" ) ]]; then
      value=${value:1:${#value}-2}
    fi
    printf '%s' "$value"
    return 0
  done < "$env_file"
}

host=${1:-${SSH_HOST:-}}
if [[ -z "$host" ]]; then host=$(read_env_value SSH_HOST); fi
[[ -n "$host" ]] || { echo "SSH_HOST non impostato in .env e host non specificato." >&2; usage; }
bootstrap_user=${2:-root}

for command in ssh sshpass ssh-keygen ssh-copy-id base64; do
  command -v "$command" >/dev/null || { echo "Comando richiesto non trovato: $command" >&2; exit 1; }
done

key_file=${MINIAGENT_SSH_KEY:-}
if [[ -z "$key_file" ]]; then
  for candidate in "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_rsa"; do
    if [[ -f "$candidate.pub" ]]; then key_file=$candidate; break; fi
  done
fi
if [[ -z "$key_file" || ! -f "$key_file.pub" ]]; then
  echo "Non trovo una chiave pubblica SSH. Creo ~/.ssh/id_ed25519." >&2
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N ''
  key_file="$HOME/.ssh/id_ed25519"
fi
public_key=$(<"$key_file.pub")
encoded_key=$(printf '%s' "$public_key" | base64 -w0)

if ! ssh -i "$key_file" -o BatchMode=yes -o ConnectTimeout=8 \
  "${bootstrap_user}@${host}" true 2>/dev/null; then
  ssh_password=${SSH_PASS:-}
  if [[ -z "$ssh_password" ]]; then ssh_password=$(read_env_value SSH_PASS); fi
  if [[ -z "$ssh_password" ]]; then
    read -r -s -p "Password SSH iniziale per ${bootstrap_user}@${host}: " ssh_password
    echo
  fi
  [[ -n "$ssh_password" ]] || { echo "La password SSH non può essere vuota." >&2; exit 1; }
  export SSHPASS=$ssh_password
  sshpass -e ssh-copy-id -i "$key_file.pub" \
    -o StrictHostKeyChecking=accept-new \
    -o PreferredAuthentications=password \
    -o PubkeyAuthentication=no \
    "${bootstrap_user}@${host}"
  unset SSHPASS ssh_password
fi

remote_bootstrap=$(cat <<'REMOTE'
set -Eeuo pipefail
target_user=$1
target_key=$(printf '%s' "$2" | base64 -d)

if ! id "$target_user" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "$target_user"
fi
target_home=$(getent passwd "$target_user" | cut -d: -f6)
target_group=$(id -gn "$target_user")
install -d -m 700 -o "$target_user" -g "$target_group" "$target_home/.ssh"
touch "$target_home/.ssh/authorized_keys"
grep -qxF "$target_key" "$target_home/.ssh/authorized_keys" || echo "$target_key" >> "$target_home/.ssh/authorized_keys"
chown "$target_user:$target_group" "$target_home/.ssh/authorized_keys"
chmod 600 "$target_home/.ssh/authorized_keys"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl git screen
node_major=0
if command -v node >/dev/null 2>&1; then
  node_major=$(node -p 'Number(process.versions.node.split(".")[0])')
fi
if (( node_major < 22 )); then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
fi
apt-get install -y nodejs
command -v npm >/dev/null || { echo 'npm non è incluso nel pacchetto Node.js installato.' >&2; exit 1; }
target_home=$(getent passwd "$target_user" | cut -d: -f6)
npm_prefix="$target_home/.local/npm"
install -d -m 755 -o "$target_user" -g "$target_group" "$npm_prefix"
runuser -u "$target_user" -- env HOME="$target_home" npm config set prefix "$npm_prefix"
claude_package="$npm_prefix/lib/node_modules/@anthropic-ai/claude-code"
install -d -m 755 -o "$target_user" -g "$target_group" "$npm_prefix/bin"
if [[ ! -x "$npm_prefix/bin/claude" ]] && command -v claude >/dev/null 2>&1; then
  ln -sfn "$(command -v claude)" "$npm_prefix/bin/claude"
elif [[ ! -x "$npm_prefix/bin/claude" && ! -x "$claude_package/bin/claude.exe" ]]; then
  staged_claude=$(find "$npm_prefix/lib/node_modules/@anthropic-ai" -path '*/bin/claude.exe' -type f -size +10M -print -quit 2>/dev/null || true)
  if [[ -n "$staged_claude" ]]; then
    install -d -m 755 -o "$target_user" -g "$target_group" "$claude_package/bin"
    mv "$staged_claude" "$claude_package/bin/claude.exe"
    chmod 755 "$claude_package/bin/claude.exe"
  else
    runuser -u "$target_user" -- env HOME="$target_home" npm install --global @anthropic-ai/claude-code --no-audit --no-fund
  fi
fi
if [[ ! -x "$npm_prefix/bin/claude" ]]; then
  ln -sfn ../lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe "$npm_prefix/bin/claude"
fi

codex_package="$npm_prefix/lib/node_modules/@openai/codex"
codex_native_package="$codex_package/node_modules/@openai/codex-linux-x64"
if [[ -d "$codex_native_package/codex-linux-x64" && ! -f "$codex_native_package/package.json" ]]; then
  mv "$codex_native_package/codex-linux-x64/"* "$codex_native_package/"
  rmdir "$codex_native_package/codex-linux-x64"
fi
if [[ -d "$codex_native_package" && ! -e "$codex_native_package/package.json" && ! -d "$codex_native_package/vendor" ]]; then
  rmdir "$codex_native_package" 2>/dev/null || true
fi
codex_native="$codex_native_package/vendor/x86_64-unknown-linux-musl/bin/codex"
if [[ ! -x "$codex_native" ]]; then
  staged_native=$(find "$npm_prefix/lib/node_modules/@openai" -path '*/node_modules/@openai/codex-linux-x64/vendor/x86_64-unknown-linux-musl/bin/codex' -print -quit 2>/dev/null || true)
  if [[ -n "$staged_native" ]]; then
    staged_package=${staged_native%/vendor/x86_64-unknown-linux-musl/bin/codex}
    install -d -m 755 -o "$target_user" -g "$target_group" "$(dirname "$codex_native_package")"
    mv "$staged_package" "$codex_native_package"
  else
    runuser -u "$target_user" -- env HOME="$target_home" npm install --global @openai/codex --no-audit --no-fund
  fi
fi
ln -sfn ../lib/node_modules/@openai/codex/bin/codex.js "$npm_prefix/bin/codex"
chown -h "$target_user:$target_group" "$npm_prefix/bin/claude" "$npm_prefix/bin/codex"
runuser -u "$target_user" -- env HOME="$target_home" PATH="$npm_prefix/bin:/usr/bin:/bin" claude --version
runuser -u "$target_user" -- env HOME="$target_home" PATH="$npm_prefix/bin:/usr/bin:/bin" codex --version
runuser -u "$target_user" -- env HOME="$target_home" npm cache clean --force --silent
npm cache clean --force --cache /root/.npm --silent

cat > /usr/local/bin/miniagent-menu <<'MENU'
#!/usr/bin/env bash
set -Eeuo pipefail
while true; do
  clear
  echo 'miniagent — scegli il coding agent'
  echo '1) Claude Code (Haiku)'
  echo '2) OpenAI Codex'
  echo 'q) Esci'
  read -r -p '> ' choice
  case "$choice" in
    1) exec claude --model haiku ;;
    2) exec codex ;;
    q|Q) exit 0 ;;
    *) echo 'Scelta non valida'; sleep 1 ;;
  esac
done
MENU
chmod 755 /usr/local/bin/miniagent-menu

profile="$target_home/.bash_profile"
touch "$profile"
if ! grep -qF '.local/npm/bin' "$profile"; then
  sed -i '1iexport PATH="$HOME/.local/npm/bin:$PATH"' "$profile"
fi
# Replace the old direct-menu block and any previous managed block.
sed -i \
  -e '/^# BEGIN miniagent SSH session$/,/^# END miniagent SSH session$/d' \
  -e '/^if \[\[ -n "\${SSH_CONNECTION:-}" && -t 0 && -t 1 \]\]; then$/,/^fi$/d' \
  "$profile"
cat >> "$profile" <<'PROFILE'

# BEGIN miniagent SSH session
if [[ -n "${SSH_CONNECTION:-}" && -t 0 && -t 1 && -z "${STY:-}" ]]; then
  screen -RR miniagent /usr/local/bin/miniagent-menu || exec bash -l
  exit
fi
# END miniagent SSH session
PROFILE
chown "$target_user:$target_group" "$profile"

install -d -m 755 /etc/ssh/sshd_config.d
printf 'PasswordAuthentication no\n' > /etc/ssh/sshd_config.d/99-miniagent.conf
sshd -t
systemctl reload ssh 2>/dev/null || systemctl reload sshd
REMOTE
)
if [[ "$bootstrap_user" == root ]]; then
  remote_command="bash -s -- '$local_user' '$encoded_key'"
else
  remote_command="sudo bash -s -- '$local_user' '$encoded_key'"
fi
ssh -i "$key_file" "${bootstrap_user}@${host}" "$remote_command" <<< "$remote_bootstrap"

unset SSHPASS ssh_password
echo "Provisioning completato. Prova: ssh ${local_user}@${host}"
echo "Al primo accesso scegli Claude Code o Codex e completa il login richiesto dalla CLI."
