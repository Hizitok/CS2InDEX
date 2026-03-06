#!/usr/bin/env bash
# =============================================================================
# sync-addresses.sh
# 将 deploy/deployed.{chainId}.json 的合约地址同步到：
#   - frontend/src/config/contracts.ts
#   - marketmaker/.env
#
# 用法：
#   bash scripts/sync-addresses.sh [chainId]
#   chainId 默认 1301（unichain-sepolia）
# =============================================================================
set -euo pipefail

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${BLUE}[sync]${NC} $*"; }
success() { echo -e "${GREEN}[sync]${NC} $*"; }
warn()    { echo -e "${YELLOW}[sync]${NC} WARN: $*"; }
error()   { echo -e "${RED}[sync]${NC} ERROR: $*"; exit 1; }

# ── 路径 ──────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

CHAIN_ID="${1:-}"

# 如果没有传 chainId，从已有的 deployed.*.json 中推断
if [[ -z "$CHAIN_ID" ]]; then
  DEPLOYED_FILES=("$ROOT_DIR"/deploy/deployed.*.json)
  if [[ ${#DEPLOYED_FILES[@]} -eq 0 || ! -f "${DEPLOYED_FILES[0]}" ]]; then
    error "未找到任何 deploy/deployed.*.json，请先运行 deploy.sh"
  fi
  # 取最新修改的那个
  DEPLOYED_JSON="$(ls -t "$ROOT_DIR"/deploy/deployed.*.json | head -1)"
  CHAIN_ID="$(basename "$DEPLOYED_JSON" | sed 's/deployed\.\(.*\)\.json/\1/')"
else
  DEPLOYED_JSON="$ROOT_DIR/deploy/deployed.${CHAIN_ID}.json"
fi

[[ -f "$DEPLOYED_JSON" ]] || error "找不到 $DEPLOYED_JSON"
info "读取部署文件: $DEPLOYED_JSON (chainId=$CHAIN_ID)"

command -v python3 >/dev/null 2>&1 || error "需要 python3 来解析 JSON"

# ── 用 python3 解析 JSON ───────────────────────────────────────────────────────
read -r USDC FACTORY VAULT ORACLE NFT ROUTER FIRST_POOL <<< "$(python3 - "$DEPLOYED_JSON" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
pools = d.get("pools", [])
first_pool = pools[0]["pool"] if pools else ""
print(d.get("usdc",""), d.get("factory",""), d.get("vault",""),
      d.get("oracle",""), d.get("nft",""), d.get("router",""), first_pool)
PYEOF
)"

info "地址:"
echo "  USDC:    $USDC"
echo "  Factory: $FACTORY"
echo "  Vault:   $VAULT"
echo "  Router:  $ROUTER"
echo "  NFT:     $NFT"
echo "  Pool:    $FIRST_POOL (第一个 Pool)"

# ── 1. 同步前端 addresses.local.ts（不被 git 追踪）────────────────────────────
FRONTEND_ADDR="$ROOT_DIR/frontend/src/config/addresses.local.ts"
FRONTEND_EXAMPLE="$ROOT_DIR/frontend/src/config/addresses.local.ts.example"

# 如果本地文件不存在，从 example 复制
if [[ ! -f "$FRONTEND_ADDR" && -f "$FRONTEND_EXAMPLE" ]]; then
  cp "$FRONTEND_EXAMPLE" "$FRONTEND_ADDR"
  info "addresses.local.ts 不存在，已从 example 创建"
fi

if [[ -f "$FRONTEND_ADDR" ]]; then
  info "更新前端地址: $FRONTEND_ADDR"
  python3 - "$DEPLOYED_JSON" "$FRONTEND_ADDR" <<'PYEOF'
import json, sys, re

data = json.load(open(sys.argv[1], encoding='utf-8'))
cfg  = open(sys.argv[2], encoding='utf-8').read()

first_pool = (data.get("pools") or [{}])[0].get("pool", "")

replacements = [
  ("FACTORY", data.get("factory", "")),
  ("VAULT",   data.get("vault",   "")),
  ("USDC",    data.get("usdc",    "")),
  ("ROUTER",  data.get("router",  "")),
  ("NFT",     data.get("nft",     "")),
  ("POOL",    first_pool),
]

for key, val in replacements:
  if not val:
    continue
  cfg = re.sub(
    rf'({key}\s*:\s*[\'"])0x[0-9a-fA-F]+([\'"])',
    lambda m, v=val: f"{m.group(1)}{v}{m.group(2)}",
    cfg
  )

open(sys.argv[2], "w", encoding='utf-8').write(cfg)
PYEOF
  success "前端地址已更新"
else
  warn "前端地址文件不存在，跳过: $FRONTEND_ADDR"
fi

# ── 2. 同步做市商 .env ────────────────────────────────────────────────────────
MM_DIR="$ROOT_DIR/marketmaker"
MM_ENV="$MM_DIR/.env"
MM_ENV_EXAMPLE="$MM_DIR/.env.example"

# 如果 .env 不存在，从 .env.example 复制
if [[ ! -f "$MM_ENV" ]]; then
  if [[ -f "$MM_ENV_EXAMPLE" ]]; then
    cp "$MM_ENV_EXAMPLE" "$MM_ENV"
    info "做市商 .env 不存在，已从 .env.example 创建"
  else
    # 从零创建
    cat > "$MM_ENV" <<'TMPL'
# Market Maker — 由 sync-addresses.sh 自动生成
RPC_URL=
PRIVATE_KEY=

POOL_ADDRESS=
VAULT_ADDRESS=
TOKEN_ADDRESS=

GRID_LEVELS=4
GRID_STEP=2.0
BASE_SIZE=1.0
BASE_MARGIN=100.0
MAX_LEVERAGE=4
MARTINGALE_MULT=2.0
MARTINGALE_MAX_LEVEL=4
POLL_INTERVAL=5000
PX_DECIMALS=6
TMPL
    info "做市商 .env 已从模板创建"
  fi
fi

info "更新做市商 .env: $MM_ENV"

# 读取根目录 .env 里的 RPC（SEPOLIA_RPC_URL 优先）
ROOT_ENV="$ROOT_DIR/.env"
CURRENT_RPC=""
if [[ -f "$ROOT_ENV" ]]; then
  CURRENT_RPC="$(grep -E '^SEPOLIA_RPC_URL=' "$ROOT_ENV" | head -1 | cut -d'=' -f2- || true)"
  if [[ -z "$CURRENT_RPC" ]]; then
    CURRENT_RPC="$(grep -E '^LOCAL_RPC_URL=' "$ROOT_ENV" | head -1 | cut -d'=' -f2- || true)"
  fi
fi

# 辅助函数：在 .env 里设置 KEY=VALUE（存在则替换，不存在则追加）
set_env_val() {
  local file="$1" key="$2" val="$3"
  if grep -qE "^${key}=" "$file" 2>/dev/null; then
    # 替换（兼容 macOS 和 Linux 的 sed）
    sed -i.bak "s|^${key}=.*|${key}=${val}|" "$file" && rm -f "${file}.bak"
  else
    echo "${key}=${val}" >> "$file"
  fi
}

set_env_val "$MM_ENV" "POOL_ADDRESS"  "$FIRST_POOL"
set_env_val "$MM_ENV" "VAULT_ADDRESS" "$VAULT"
set_env_val "$MM_ENV" "TOKEN_ADDRESS" "$USDC"

if [[ -n "$CURRENT_RPC" ]]; then
  set_env_val "$MM_ENV" "RPC_URL" "$CURRENT_RPC"
  info "  RPC_URL 从根 .env 同步: $CURRENT_RPC"
fi

success "做市商 .env 已更新"

# ── 检查是否还有需要手动填写的字段 ────────────────────────────────────────────
MISSING=()
for key in PRIVATE_KEY RPC_URL; do
  val="$(grep -E "^${key}=" "$MM_ENV" | head -1 | cut -d'=' -f2-)"
  if [[ -z "$val" || "$val" == "0x..." || "$val" =~ ^http://127 ]]; then
    MISSING+=("$key")
  fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo ""
  warn "以下字段需要手动填写 $MM_ENV:"
  for k in "${MISSING[@]}"; do echo "  → $k"; done
fi

echo ""
success "地址同步完成！"
