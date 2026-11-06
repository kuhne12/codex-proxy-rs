#!/usr/bin/env bash
# 专用 SSH 密钥只允许部署本仓库镜像，凭据从标准输入读取且不落入持久配置
set -Eeuo pipefail
umask 077

root="${1:?usage: deploy-production.sh INSTALL_DIR}"
cd "$root"
root="$PWD"
state="$root/.runtime/cd"
mkdir -p "$state"
chmod 700 "$state"
exec 9>"$state/deploy.lock"
flock -w 900 9 || { echo 'Another deployment is still running' >&2; exit 1; }

command="${SSH_ORIGINAL_COMMAND:-}"
if [[ ! "$command" =~ ^deploy\ (sha256:[a-f0-9]{64})\ ([a-f0-9]{40})\ ([0-9]+-[0-9]+)$ ]]; then
  echo 'Only deploy DIGEST COMMIT RUN-ATTEMPT is allowed' >&2
  exit 2
fi
digest="${BASH_REMATCH[1]}"
commit="${BASH_REMATCH[2]}"
run="${BASH_REMATCH[3]}"
image="ghcr.io/kuhne12/codex-proxy-rs@$digest"
compose=(docker compose -f "$root/deploy/compose.instance.yaml")
export DOCKER_CONFIG
DOCKER_CONFIG="$(mktemp -d "$state/docker-auth.XXXXXX")"
cleanup() { rm -rf "$DOCKER_CONFIG"; }
trap cleanup EXIT
# GITHUB_TOKEN 只在本次拉取期间使用，部署结束删除 Docker 登录文件
IFS= read -r registry_token
[[ -n "$registry_token" && ${#registry_token} -le 4096 ]] || exit 2
printf '%s' "$registry_token" | docker login ghcr.io -u kuhne12 --password-stdin >/dev/null
unset registry_token

head_commit="$(git ls-remote https://github.com/kuhne12/codex-proxy-rs.git refs/heads/main | cut -f1)"
if [[ "$head_commit" != "$commit" ]]; then
  echo "Skipping superseded commit $commit (main is $head_commit)"
  exit 0
fi
"${compose[@]}" config --quiet
docker pull "$image"
test "$(docker image inspect --format '{{.Architecture}}' "$image")" = arm64
test "$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' "$image")" = "$commit"
container="$("${compose[@]}" ps -q codex-proxy-rs)"
test -n "$container"
test "$(docker inspect --format '{{.State.Health.Status}}' "$container")" = healthy
previous_image="$(docker inspect --format '{{.Config.Image}}' "$container")"
# 构建与拉取可能耗时，停止服务前再次阻止旧提交覆盖更新的 main
head_commit="$(git ls-remote https://github.com/kuhne12/codex-proxy-rs.git refs/heads/main | cut -f1)"
if [[ "$head_commit" != "$commit" ]]; then
  echo "Skipping superseded commit $commit"
  exit 0
fi
available_kb="$(df -Pk "$root" | awk 'END {print $4}')"
test "$available_kb" -gt 2097152 || { echo 'At least 2 GiB free disk space is required' >&2; exit 1; }
backup="$state/backups/$(date -u +%Y%m%dT%H%M%SZ)-$run"
mkdir -p "$backup"
cp deploy/config.yaml deploy/compose.instance.yaml "$backup/"
printf '%s\n' "$previous_image" > "$backup/previous-image.txt"

migration_state() {
  # 密码由数据库容器环境展开，不传入宿主进程参数
  # shellcheck disable=SC2016
  "${compose[@]}" exec -T postgres sh -c \
    'export PGPASSWORD="$POSTGRES_PASSWORD"; exec psql -X -At -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT version, encode(checksum, '\''hex'\''), success FROM _sqlx_migrations ORDER BY version"'
}
healthy() {
  local path
  for path in healthz readyz; do
    test "$(curl --noproxy '*' -sS --max-time 10 -o /dev/null -w '%{http_code}' "http://127.0.0.1:18082/$path")" = 204 || return 1
  done
}
replace_image() {
  python3 - "$image" <<'PY'
from pathlib import Path
import os, re, sys
path = Path("deploy/compose.instance.yaml")
content, count = re.subn(r"(?ms)(^  codex-proxy-rs:\n.*?^    image: )[^\n]+",
                         lambda m: m[1] + sys.argv[1], path.read_text(), count=1)
assert count == 1, "Application image entry not found"
temporary = path.with_suffix(".yaml.tmp")
temporary.write_text(content)
temporary.chmod(path.stat().st_mode & 0o777)
os.replace(temporary, path)
PY
}
stopped=0
changed=0
recover() {
  local result="$?"
  trap - ERR HUP INT TERM
  set +e
  if [[ "$stopped" = 1 ]]; then
    if [[ "$changed" = 0 ]]; then
      "${compose[@]}" up -d --no-build --no-deps --wait --wait-timeout 300 codex-proxy-rs
    else
      # 已执行迁移时禁止盲目降级或自动还原数据库，避免覆盖升级后的写入
      "${compose[@]}" stop codex-proxy-rs
      if migration_state > "$backup/migrations-after-failure.txt" &&
          cmp -s "$backup/migrations-before.txt" "$backup/migrations-after-failure.txt"; then
        cp "$backup/compose.instance.yaml" deploy/compose.instance.yaml
        if "${compose[@]}" up -d --no-build --no-deps --wait --wait-timeout 300 codex-proxy-rs && healthy; then
          echo "Previous image restored: $previous_image"
        else
          echo 'Previous image could not recover; operator action required' >&2
        fi
      else
        echo "Database migration state changed or is unknown; application stopped. Backup: $backup" >&2
      fi
    fi
  fi
  echo "Deployment failed; backup: $backup" >&2
  exit "$result"
}
trap recover ERR
# 让信号也进入恢复流程；SSH keepalive 断开时不继续无监督写入
trap 'false' HUP INT TERM
stopped=1
"${compose[@]}" stop codex-proxy-rs
migration_state > "$backup/migrations-before.txt"
# shellcheck disable=SC2016
"${compose[@]}" exec -T postgres sh -c \
  'export PGPASSWORD="$POSTGRES_PASSWORD"; exec pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' \
  > "$backup/database.dump"
test -s "$backup/database.dump"
"${compose[@]}" exec -T postgres pg_restore --list < "$backup/database.dump" >/dev/null
# 会话锚点与数据库备份一起保留，日志与 Redis 不参与自动恢复
docker run --rm --user 0 --entrypoint tar --network none --read-only \
  --mount "type=bind,src=$root/.runtime/data,dst=/data,readonly" \
  "$previous_image" -C /data -czf - . > "$backup/runtime-data.tar.gz"
gzip -t "$backup/runtime-data.tar.gz"
changed=1
replace_image
"${compose[@]}" config --quiet
"${compose[@]}" up -d --no-build --no-deps --wait --wait-timeout 300 codex-proxy-rs
healthy
container="$("${compose[@]}" ps -q codex-proxy-rs)"
test "$(docker inspect --format '{{.Config.Image}}' "$container")" = "$image"
test "$(docker inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' "$container")" = "$commit"
stopped=0
trap - ERR HUP INT TERM
printf '%s\t%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$commit" "$image" "$backup" >> "$state/history.tsv"
printf '%s\n' "$commit" > "$state/current-commit"
printf '%s\n' "$image" > "$state/current-image"
echo "Deployed $commit"
echo "Image: $image"
echo "Backup: $backup"
