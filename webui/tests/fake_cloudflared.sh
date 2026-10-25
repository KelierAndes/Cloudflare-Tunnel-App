#!/usr/bin/env bash
# 假 cloudflared：只实现同步/取回凭证测试需要的子命令。
set -u

args=("$@")

first="${args[0]:-}"
case "$first" in
  --version)
    echo "cloudflared version 0.0.0-test (built 1970-01-01T00:00 UTC)"
    exit 0
    ;;
  tunnel) ;;
  *)
    echo "unexpected: $*" >&2
    exit 2
    ;;
esac

# 去掉 tunnel 级选项，收集子命令与参数
sub=""
cred=""
rest=()
i=2
while [[ $i -lt ${#args[@]} ]]; do
  a="${args[$i]}"
  case "$a" in
    --origincert|--config|--credentials-file|--cred-file)
      i=$((i + 1))
      value="${args[$i]:-}"
      if [[ "$a" == "--credentials-file" || "$a" == "--cred-file" ]]; then cred="$value"; fi
      ;;
    --output|-o|--no-autoupdate|--overwrite-dns|-f) ;;
    list|token|create|delete|cleanup|run|login|dns) sub="$a";;
    json) ;;
    *) rest+=("$a") ;;
  esac
  i=$((i + 1))
done

case "$sub" in
  list)
    cat <<'JSON'
[{"created_at":"2026-01-02T03:04:05Z","id":"7c3f9a52-1a2b-4c5d-8e9f-0a1b2c3d4e5f","name":"home-nas"},
 {"created_at":"2026-02-03T04:05:06Z","id":"1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d","name":"nas"}]
JSON
    ;;
  token)
    if [[ -z "$cred" ]]; then
      echo "missing credentials file" >&2
      exit 1
    fi
    printf '{"AccountTag":"acct","TunnelID":"%s","TunnelSecret":"c2VjcmV0"}\n' "${rest[0]:-}" > "$cred"
    ;;
  login)
    if [[ -n "${FAKE_HOME_OUT:-}" ]]; then printf '%s' "$HOME" > "$FAKE_HOME_OUT"; fi
    if [[ -n "${FAKE_LOGIN_FAIL:-}" ]]; then
      echo "$FAKE_LOGIN_FAIL" >&2
      exit 1
    fi
    echo "A browser window should have opened at the following URL:"
    echo
    echo "https://dash.cloudflare.com/argotunnel?aud=&callback=https%3A%2F%2Flogin.cloudflareaccess.org%2FTESTTOKEN"
    echo
    echo "If the browser failed to open, please visit the URL above directly in your browser."
    if [[ -n "${FAKE_LOGIN_OK:-}" ]]; then
      # 真实 cloudflared 把证书写到 $HOME/.cloudflared，而不是 --origincert
      mkdir -p "$HOME/.cloudflared"
      printf '%s\n' "-----BEGIN ARGO TUNNEL TOKEN-----" \
        "$(printf 'Z%.0s' $(seq 1 160))" \
        "-----END ARGO TUNNEL TOKEN-----" > "$HOME/.cloudflared/cert.pem"
      exit 0
    fi
    # 真实 cloudflared 会一直等待用户完成授权
    while true; do sleep 1; done
    ;;
  *)
    echo "unhandled subcommand: $sub" >&2
    exit 3
    ;;
esac
