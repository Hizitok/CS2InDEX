#!/usr/bin/env bash
# =============================================================================
# sync-pools.sh — 从 deploy/pools.config.json 同步 Pool 配置到 Deployer.sol
#
# 用法：bash scripts/sync-pools.sh
#
# 背景：Deploy.s.sol (forge 脚本) 直接在运行时读取 pools.config.json。
#       Deployer.sol (Remix 合约) 无法读取文件，须把配置硬编码进 _initPools()。
#       本脚本负责将 JSON 配置同步到 Deployer.sol，保持两者一致。
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG="$ROOT_DIR/deploy/pools.config.json"
DEPLOYER="$ROOT_DIR/deploy/Deployer.sol"

[[ -f "$CONFIG"   ]] || { echo "[ERROR] 未找到 $CONFIG";   exit 1; }
[[ -f "$DEPLOYER" ]] || { echo "[ERROR] 未找到 $DEPLOYER"; exit 1; }

command -v python3 >/dev/null 2>&1 || { echo "[ERROR] 需要 python3"; exit 1; }

python3 -X utf8 - "$CONFIG" "$DEPLOYER" <<'PYEOF'
import json, sys, re
sys.stdout.reconfigure(encoding='utf-8', errors='replace')

config_path, deployer_path = sys.argv[1], sys.argv[2]

with open(config_path, encoding='utf-8') as f:
    pools = json.load(f)

if not pools:
    print("[ERROR] pools.config.json 为空")
    sys.exit(1)

# 生成 POOLS.push 行
lines = []
for p in pools:
    price    = int(p['initialPrice'])
    dec      = int(p['pxDecimals'])
    name     = p['name']
    dollar   = price / (10 ** dec)
    price_str = f"{price:_}"   # 393_500_000
    lines.append(f'        POOLS.push(PoolConfig("{name}", {price_str}, {dec})); // ${dollar:.2f}')

new_body = '\n'.join(lines)

with open(deployer_path, 'r', encoding='utf-8') as f:
    content = f.read()

# 替换 _initPools() 函数体
pattern = r'(    function _initPools\(\) internal \{\n)(?:.*\n)*?(    \})'
replacement = r'\g<1>' + new_body + '\n' + r'\g<2>'
new_content, n = re.subn(pattern, replacement, content)

if n == 0:
    print("[WARN] 未找到 _initPools() 函数，Deployer.sol 未修改")
    sys.exit(1)

if new_content == content:
    print(f"[OK]  Deployer.sol 已是最新 ({len(pools)} 个 Pool，无需修改)")
else:
    with open(deployer_path, 'w', encoding='utf-8') as f:
        f.write(new_content)
    print(f"[OK]  已同步 {len(pools)} 个 Pool 到 Deployer.sol")

for p in pools:
    price = int(p['initialPrice'])
    dec   = int(p['pxDecimals'])
    print(f"        - {p['name']}  ${price / 10**dec:.2f}")
PYEOF
