#!/bin/bash
# FinderQuickActions 一键构建 + 安装 + 注册扩展
# 用法：在本项目根目录执行  scripts/deploy.sh
# 依赖：Xcode 命令行工具、xcodegen（brew install xcodegen）
set -e

DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DIR"

SCHEME="FinderQuickActions"
BUNDLE_ID="com.finderquickactions.app.FinderExtension"
APP_SRC="$DIR/build/DerivedData/Build/Products/Release/FinderQuickActions.app"
APP_DEST="/Applications/右键助手.app"
APP_DEST_OLD="/Applications/FinderQuickActions.app"

echo "==> [1/5] 生成 Xcode 工程"
xcodegen generate

echo "==> [2/5] 编译（Release）"
xcodebuild -project FinderQuickActions.xcodeproj -scheme "$SCHEME" \
    -configuration Release -derivedDataPath build/DerivedData build \
    > /tmp/fqa_build.log 2>&1 || {
    echo "编译失败，日志：/tmp/fqa_build.log"
    tail -60 /tmp/fqa_build.log
    exit 1
}

if [ ! -d "$APP_SRC" ]; then
    echo "未找到构建产物：$APP_SRC" >&2
    exit 1
fi

echo "==> [3/5] 生成空白模板与默认配置 ~/.finderquickactions"
# 清掉外部注入的 PYTHONHOME/PYTHONPATH（如 TRAE 自带的 python），否则系统 python3 会找不到标准库
env -u PYTHONHOME -u PYTHONPATH "/usr/bin/python3" "$DIR/scripts/make_templates.py" || true
rm -f "$HOME/.finderquickactions/request.json"

echo "==> [4/5] 安装到 /Applications"
killall FinderQuickActions 2>/dev/null || true
pluginkit -r "$APP_DEST_OLD/Contents/PlugIns/FinderQuickActionsFinderExtension.appex" 2>/dev/null || true
rm -rf "$APP_DEST_OLD"
rm -rf "$APP_DEST"
ditto "$APP_SRC" "$APP_DEST"
pluginkit -a "$APP_DEST/Contents/PlugIns/FinderQuickActionsFinderExtension.appex" 2>/dev/null || true

echo "==> [5/5] 启动宿主并注册 Finder 扩展"
# 让 LaunchServices 重新登记，避免系统设置里显示旧的名称与空白图标
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
# 同一 bundle id 若残留多条注册（例如旧构建路径），系统可能选中失效的那条 → 显示旧名/空白图标，这里清掉
"$LSREGISTER" -u "$APP_SRC" 2>/dev/null || true
"$LSREGISTER" -u "$APP_SRC/Contents/PlugIns/FinderQuickActionsFinderExtension.appex" 2>/dev/null || true
"$LSREGISTER" -f "$APP_DEST" 2>/dev/null || true
open "$APP_DEST"
/System/Library/CoreServices/pbs -update 2>/dev/null || true
pluginkit -e use -i "$BUNDLE_ID" || echo "（pluginkit 未立即返回，稍后可在系统设置里勾选）"
killall Finder 2>/dev/null || true

echo ""
echo "部署完成。如果右键菜单还没出现："
echo "  1) 系统设置 → 通用 → 登录项与扩展 → Finder 扩展 → 勾选 右键助手"
echo "  2) 终端执行： killall Finder"
echo ""
echo "配置目标文件夹：编辑 ~/.finderquickactions/config.json 里的 targetFolders"