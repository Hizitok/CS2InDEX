#!/usr/bin/env bash
# =============================================================================
# CS2InDEX 一键部署脚本
# 用法：bash deploy/deploy.sh [sepolia|mainnet|local]
# =============================================================================
set -euo pipefail

# ── 颜色输出 ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── 参数解析 ──────────────────────────────────────────────────────────────────
NETWORK="${1:-sepolia}"

case "$NETWORK" in
  sepolia|testnet) NETWORK="sepolia"  ;;
  mainnet)         NETWORK="mainnet"  ;;
  local|anvil)     NETWORK="local"    ;;
  *) error "未知网络 '$NETWORK'。用法: bash deploy/deploy.sh [sepolia|mainnet|local]" ;;
esac

# ── 切换到项目根目录 ──────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

echo ""
echo "============================================="
echo "  CS2InDEX 部署脚本  |  网络: $NETWORK"
echo "============================================="
echo ""

# ── 加载 .env ─────────────────────────────────────────────────────────────────
ENV_FILE="$ROOT_DIR/.env"
if [[ -f "$ENV_FILE" ]]; then
  info "加载 .env ..."
  set -o allexport
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +o allexport
else
  warn ".env 不存在，将使用系统环境变量（如需配置请复制 deploy/.env.example 到 .env）"
fi

# ── 检查依赖 ──────────────────────────────────────────────────────────────────
command -v forge >/dev/null 2>&1 || error "未找到 forge，请先安装 Foundry: https://book.getfoundry.sh"
command -v cast  >/dev/null 2>&1 || error "未找到 cast"

# ── 检查私钥 ──────────────────────────────────────────────────────────────────
if [[ -z "${PRIVATE_KEY:-}" ]]; then
  error "未设置 PRIVATE_KEY，请在 .env 中配置"
fi

DEPLOYER_ADDRESS="$(cast wallet address "$PRIVATE_KEY")"
info "部署者地址: $DEPLOYER_ADDRESS"

# ── 确定 RPC 和参数 ───────────────────────────────────────────────────────────
case "$NETWORK" in
  sepolia)
    RPC_URL="${SEPOLIA_RPC_URL:-}"
    [[ -z "$RPC_URL" ]] && error "未设置 SEPOLIA_RPC_URL"
    VERIFY_FLAG=""
    [[ -n "${ETHERSCAN_API_KEY:-}" ]] && VERIFY_FLAG="--verify" || warn "未设置 ETHERSCAN_API_KEY，跳过合约验证"
    EXTRA_FLAGS=""
    ;;
  mainnet)
    RPC_URL="${MAINNET_RPC_URL:-}"
    [[ -z "$RPC_URL" ]] && error "未设置 MAINNET_RPC_URL"
    VERIFY_FLAG=""
    [[ -n "${ETHERSCAN_API_KEY:-}" ]] && VERIFY_FLAG="--verify" || warn "未设置 ETHERSCAN_API_KEY，跳过合约验证"
    EXTRA_FLAGS="--slow"  # 主网加 --slow 防止 nonce 竞争
    warn "主网部署！10 秒后继续，Ctrl+C 取消..."
    sleep 10
    ;;
  local)
    # 本地 anvil 节点
    RPC_URL="${LOCAL_RPC_URL:-http://127.0.0.1:8545}"
    VERIFY_FLAG=""
    EXTRA_FLAGS=""
    # 本地使用 anvil 默认私钥（如未设置）
    if [[ "$PRIVATE_KEY" == "0x"* ]] && [[ "${#PRIVATE_KEY}" -lt 20 ]]; then
      PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
      warn "本地模式：使用 anvil 默认私钥"
    fi
    ;;
esac

# ── 检查 ETH 余额 ─────────────────────────────────────────────────────────────
ETH_BALANCE="$(cast balance "$DEPLOYER_ADDRESS" --rpc-url "$RPC_URL" 2>/dev/null || echo 0)"
info "部署者 ETH 余额: $(cast from-wei "$ETH_BALANCE" ether) ETH"
if [[ "$ETH_BALANCE" == "0" ]]; then
  warn "ETH 余额为 0，部署可能失败"
fi

# ── 编译检查 ──────────────────────────────────────────────────────────────────
info "编译合约..."
forge build --quiet || error "编译失败，请先修复错误"
success "编译通过"

# ── 运行测试（可选，主网强制） ────────────────────────────────────────────────
if [[ "$NETWORK" == "mainnet" ]]; then
  info "主网部署前跑全量测试..."
  forge test --quiet || error "测试失败，主网部署中止"
  success "全量测试通过"
else
  if [[ "${RUN_TESTS:-true}" == "true" ]]; then
    info "跑测试..."
    forge test --quiet || error "测试失败，请修复后重试（跳过测试：RUN_TESTS=false）"
    success "测试通过"
  else
    warn "已跳过测试（RUN_TESTS=false）"
  fi
fi

# ── 执行部署 ──────────────────────────────────────────────────────────────────
info "开始部署到 $NETWORK ..."
echo ""

# 构建 forge script 命令（不含 --verify，单独处理验证）
FORGE_CMD=(
  forge script deploy/Deploy.s.sol
  --rpc-url "$RPC_URL"
  --private-key "$PRIVATE_KEY"
  --broadcast
  -vvvv
)

[[ -n "$EXTRA_FLAGS" ]] && FORGE_CMD+=($EXTRA_FLAGS)

# 主网 USDC 地址（如有设置）
if [[ -n "${USDC_ADDRESS:-}" ]]; then
  export USDC_ADDRESS
fi

"${FORGE_CMD[@]}" || error "部署失败"

# ── 合约验证（可选，需要 ETHERSCAN_API_KEY）────────────────────────────────
if [[ -n "$VERIFY_FLAG" && -n "${ETHERSCAN_API_KEY:-}" ]]; then
  info "验证合约（Etherscan）..."
  forge script deploy/Deploy.s.sol \
    --rpc-url "$RPC_URL" \
    --verify \
    --etherscan-api-key "$ETHERSCAN_API_KEY" \
    --resume \
    || warn "合约验证失败（不影响部署），可稍后手动验证"
fi

echo ""
success "部署完成！"

# ── 读取并展示部署结果 ────────────────────────────────────────────────────────
CHAIN_ID="$(cast chain-id --rpc-url "$RPC_URL")"
DEPLOYED_JSON="$ROOT_DIR/deploy/deployed.${CHAIN_ID}.json"

if [[ -f "$DEPLOYED_JSON" ]]; then
  echo ""
  echo "============================================="
  echo "  部署地址（已保存到 $DEPLOYED_JSON）"
  echo "============================================="

  # 用 python 或 node 解析 JSON（优先 python3）
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$DEPLOYED_JSON" <<'EOF'
import json, sys
data = json.load(open(sys.argv[1]))
labels = [("USDC","usdc"),("Factory","factory"),("Vault","vault"),
          ("Oracle","oracle"),("NFT","nft"),("Router","router")]
for label, key in labels:
    print(f"  {label:<10}: {data.get(key,'?')}")
print()
for p in data.get("pools",[]):
    print(f"  Pool: {p['name']}")
    print(f"    pool  : {p['pool']}")
    print(f"    engine: {p['engine']}")
EOF
  else
    cat "$DEPLOYED_JSON"
  fi

  # ── 自动更新前端配置 ──────────────────────────────────────────────────────
  FRONTEND_CONFIG="$ROOT_DIR/frontend/src/config/contracts.ts"
  if [[ -f "$FRONTEND_CONFIG" && command -v python3 >/dev/null 2>&1 ]]; then
    info "更新前端合约配置..."
    python3 - "$DEPLOYED_JSON" "$FRONTEND_CONFIG" "$CHAIN_ID" <<'PYEOF'
import json, sys, re

data    = json.load(open(sys.argv[1]))
cfg     = open(sys.argv[2]).read()
chainId = sys.argv[3]

# 替换常量地址（POOL 取第一个 pool，即 CS2-Global-Index）
first_pool = data.get("pools", [{}])[0].get("pool", "")
for key, val in [("FACTORY", data.get("factory","")),
                 ("VAULT",   data.get("vault","")),
                 ("USDC",    data.get("usdc","")),
                 ("ROUTER",  data.get("router","")),
                 ("NFT",     data.get("nft","")),
                 ("POOL",    first_pool)]:
    cfg = re.sub(
        rf'({key}\s*:\s*[\'"])0x[0-9a-fA-F]+([\'"])',
        lambda m, v=val: f"{m.group(1)}{v}{m.group(2)}",
        cfg
    )

open(sys.argv[2], "w").write(cfg)
print(f"  前端配置已更新: {sys.argv[2]}")
PYEOF
    success "前端配置更新完成"
  fi
else
  warn "未找到部署结果 JSON（$DEPLOYED_JSON）"
fi

echo ""
echo "============================================="
echo "  后续操作"
echo "============================================="
echo "  1. 启动 Oracle 服务："
echo "     cd oracle-service && npm start"
echo ""
echo "  2. 验证合约（如自动验证失败）："
echo "     见 deploy/README.md #验证合约"
echo ""
if [[ "$NETWORK" == "mainnet" ]]; then
  echo "  3. [重要] 将 Factory 所有权转移给多签钱包："
  echo "     cast send <FACTORY> 'transferOwnership(address)' <MULTISIG>"
  echo ""
fi
echo "============================================="
echo ""
