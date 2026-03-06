#!/usr/bin/env bash
# =============================================================================
# start-dev.sh
# 一键启动开发环境：做市商（后台）+ 前端（前台）
#
# 用法：
#   bash scripts/start-dev.sh            # 同时启动前端 + 做市商
#   bash scripts/start-dev.sh --no-mm    # 仅启动前端
#   bash scripts/start-dev.sh --mm-only  # 仅启动做市商
# =============================================================================
set -euo pipefail

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${BLUE}[dev]${NC}  $*"; }
success() { echo -e "${GREEN}[dev]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[dev]${NC}  WARN: $*"; }
error()   { echo -e "${RED}[dev]${NC}  ERROR: $*"; exit 1; }
section() { echo -e "\n${CYAN}══════════════════════════════════════${NC}"; echo -e "${CYAN}  $*${NC}"; echo -e "${CYAN}══════════════════════════════════════${NC}\n"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

START_MM=true
START_FE=true

for arg in "$@"; do
  case "$arg" in
    --no-mm)   START_MM=false ;;
    --mm-only) START_FE=false ;;
    *) warn "未知参数 $arg，忽略" ;;
  esac
done

MM_DIR="$ROOT_DIR/marketmaker"
FE_DIR="$ROOT_DIR/frontend"

MM_PID=""
FE_PID=""
MM_LOG="$ROOT_DIR/.mm.log"

# ── 清理函数（Ctrl+C 时执行）─────────────────────────────────────────────────
cleanup() {
  echo ""
  info "正在退出..."
  if [[ -n "$MM_PID" ]] && kill -0 "$MM_PID" 2>/dev/null; then
    info "停止做市商 (pid=$MM_PID)..."
    kill "$MM_PID" 2>/dev/null || true
  fi
  if [[ -n "$FE_PID" ]] && kill -0 "$FE_PID" 2>/dev/null; then
    info "停止前端 (pid=$FE_PID)..."
    kill "$FE_PID" 2>/dev/null || true
  fi
  success "已退出"
  exit 0
}

trap cleanup INT TERM

# ── 检查 marketmaker .env ─────────────────────────────────────────────────────
check_mm_env() {
  local mm_env="$MM_DIR/.env"
  if [[ ! -f "$mm_env" ]]; then
    warn "做市商 .env 不存在，先运行地址同步："
    echo "  bash scripts/sync-addresses.sh"
    return 1
  fi

  local missing=()
  for key in PRIVATE_KEY RPC_URL POOL_ADDRESS VAULT_ADDRESS TOKEN_ADDRESS; do
    local val
    val="$(grep -E "^${key}=" "$mm_env" 2>/dev/null | head -1 | cut -d'=' -f2- || true)"
    if [[ -z "$val" || "$val" == "0x0000000000000000000000000000000000000000" ]]; then
      missing+=("$key")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    warn "做市商 .env 缺少以下配置，请先填写:"
    for k in "${missing[@]}"; do echo "  → marketmaker/.env: $k="; done
    return 1
  fi
  return 0
}

# ── 检查依赖 ──────────────────────────────────────────────────────────────────
check_deps() {
  local dir="$1" name="$2"
  if [[ ! -d "$dir/node_modules" ]]; then
    info "$name: 安装依赖..."
    npm install --prefix "$dir" --silent
  fi
}

# ── 启动做市商 ────────────────────────────────────────────────────────────────
start_mm() {
  section "启动做市商"

  if ! check_mm_env; then
    warn "跳过做市商启动（配置不完整）"
    START_MM=false
    return
  fi

  check_deps "$MM_DIR" "做市商"

  info "做市商日志 → $MM_LOG"
  info "启动做市商（后台运行）..."

  # ts-node 直接运行，日志写到文件，同时 tail 到 stderr 加前缀
  (cd "$MM_DIR" && npx ts-node src/index.ts 2>&1) | \
    awk '{ print "\033[0;35m[mm]\033[0m  " $0; fflush() }' &
  MM_PID=$!

  # 等一秒确认进程没有立刻崩溃
  sleep 1
  if ! kill -0 "$MM_PID" 2>/dev/null; then
    warn "做市商启动失败（查看日志: $MM_LOG）"
    MM_PID=""
    START_MM=false
    return
  fi

  success "做市商已启动 (pid=$MM_PID)"
}

# ── 启动前端 ──────────────────────────────────────────────────────────────────
start_fe() {
  section "启动前端 (Next.js)"

  if [[ ! -f "$FE_DIR/package.json" ]]; then
    error "前端目录不存在: $FE_DIR"
  fi

  # 检查 .env.local
  if [[ ! -f "$FE_DIR/.env.local" ]]; then
    warn "frontend/.env.local 不存在，NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID 未配置"
    warn "可能导致 WalletConnect 功能异常"
  fi

  check_deps "$FE_DIR" "前端"

  info "启动 Next.js dev server..."
  (cd "$FE_DIR" && npm run dev 2>&1) | \
    awk '{ print "\033[0;34m[fe]\033[0m   " $0; fflush() }' &
  FE_PID=$!

  success "前端已启动 (pid=$FE_PID)"
}

# ── 主流程 ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}╔════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  CS2InDEX 开发环境启动             ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════╝${NC}"
echo ""

if $START_MM; then start_mm; fi
if $START_FE; then start_fe; fi

if [[ -z "$MM_PID" && -z "$FE_PID" ]]; then
  error "没有任何服务启动成功"
fi

echo ""
success "服务已就绪："
$START_MM && [[ -n "$MM_PID" ]] && echo "  做市商: 后台运行 (pid=$MM_PID) — 日志见上方 [mm] 前缀行"
$START_FE && [[ -n "$FE_PID" ]] && echo "  前端:   http://localhost:3000"
echo ""
info "按 Ctrl+C 退出所有服务"
echo ""

# ── 等待子进程结束 ────────────────────────────────────────────────────────────
# 如果前端在前台，wait 会阻塞直到 Ctrl+C
wait
