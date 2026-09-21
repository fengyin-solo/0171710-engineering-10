#!/bin/sh
# build.sh — 静态站点构建（本地开发与容器镜像构建使用同一份脚本）
#
# 输入: frontend-user/public/           静态源文件（唯一来源，本地与容器共用）
# 输出: frontend-user/dist/             构建产物（本地 nginx 与容器内 nginx 挂/拷同一份）
#
# 必填变量:
#   VERSION      版本号，如 1.2.3 或 v1.2.3（缺失立即报错停止）
#   BUILD_TIME   构建时间（RFC3339/UTC，缺失立即报错停止）
# 可选变量:
#   REVISION     源码版本标识（默认 unknown，便于溯源）
#   SOURCE_DIR   源目录（默认脚本上级目录/public）
#   OUTPUT_DIR   产物目录（默认脚本上级目录/dist）
#   CACHE_DIR    依赖缓存目录（默认脚本上级目录/.cache/vendor）
#   SKIP_DEPS    非空时跳过第三方依赖下载（依赖需已在产物中，CI 离线场景使用）
#
# 产物布局:
#   dist/index.html, dist/css/*, dist/js/*, dist/vendor/*, dist/version.json
# 该布局与容器内 /usr/share/nginx/html 完全一致（见 Dockerfile / nginx.conf）。

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APP_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

SOURCE_DIR=${SOURCE_DIR:-$APP_DIR/public}
OUTPUT_DIR=${OUTPUT_DIR:-$APP_DIR/dist}
CACHE_DIR=${CACHE_DIR:-$APP_DIR/.cache/vendor}
REVISION=${REVISION:-unknown}

die() {
    printf '\n构建失败：%s\n' "$*" >&2
    exit 1
}

# ---------- 1. 构建参数校验：缺失立即报错并停止 ----------
[ -n "${VERSION:-}" ] || die "缺少必填构建参数 VERSION（示例: VERSION=1.0.0 BUILD_TIME=\"$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo 2026-01-01T00:00:00Z)\" sh scripts/build.sh）"
[ -n "${BUILD_TIME:-}" ] || die "缺少必填构建参数 BUILD_TIME（RFC3339 UTC 时间，示例: BUILD_TIME=\"$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo 2026-01-01T00:00:00Z)\"）"

# 只允许安全字符，避免注入 HTML/JSON 或破坏 sed 替换
# VERSION: 字母数字 . _ - + /；BUILD_TIME/REVISION 再加 : 和空格
printf '%s' "$VERSION" | grep -Eq '^[A-Za-z0-9._+/v-]+$' \
    || die "VERSION 含非法字符: $VERSION（仅允许字母数字 . _ - + / v）"
printf '%s' "$BUILD_TIME" | grep -Eq '^[A-Za-z0-9._:+ /T-]+$' \
    || die "BUILD_TIME 含非法字符: $BUILD_TIME"
printf '%s' "$REVISION" | grep -Eq '^[A-Za-z0-9._:+ /T-]*$' \
    || die "REVISION 含非法字符: $REVISION"

[ -d "$SOURCE_DIR" ] || die "静态源目录不存在: $SOURCE_DIR"
[ -f "$SOURCE_DIR/index.html" ] || die "源入口文件不存在: $SOURCE_DIR/index.html"

printf '==> 构建投标报价计算器\n'
printf '    VERSION    : %s\n' "$VERSION"
printf '    BUILD_TIME : %s\n' "$BUILD_TIME"
printf '    REVISION   : %s\n' "$REVISION"
printf '    源目录     : %s\n' "$SOURCE_DIR"
printf '    产物目录   : %s\n' "$OUTPUT_DIR"

# ---------- 2. 清理旧产物（避免残留文件进入镜像/本地服务） ----------
printf '==> 清理旧产物\n'
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# ---------- 3. 复制静态源文件（保留 css/js 目录结构） ----------
printf '==> 复制静态源文件\n'
cp -R "$SOURCE_DIR/." "$OUTPUT_DIR/"

# ---------- 4. 固化第三方依赖（带超时/重试/哈希校验/缓存） ----------
if [ -z "${SKIP_DEPS:-}" ]; then
    printf '==> 拉取并校验第三方依赖\n'
    FETCH_TIMEOUT=${FETCH_TIMEOUT:-30} FETCH_RETRIES=${FETCH_RETRIES:-3} \
        sh "$SCRIPT_DIR/fetch-deps.sh" "$APP_DIR/dependencies.txt" "$OUTPUT_DIR" "$CACHE_DIR"
else
    printf '==> 使用已预热的第三方依赖（SKIP_DEPS 已设置）\n'
    # Docker 构建中依赖由前序层预热到缓存目录，此处按清单恢复到产物目录
    [ -d "$CACHE_DIR" ] || die "SKIP_DEPS=1 但依赖缓存目录不存在: $CACHE_DIR"
    while IFS= read -r dep_line || [ -n "$dep_line" ]; do
        case "$dep_line" in ''|'#'*) continue ;; esac
        # shellcheck disable=SC2086
        set -- $dep_line
        dep_target=$1; dep_hash=$2
        [ -f "$CACHE_DIR/$dep_hash" ] || die "依赖缓存缺失: $dep_target（哈希 $dep_hash），请取消 SKIP_DEPS 重新构建"
        mkdir -p "$OUTPUT_DIR/$(dirname "$dep_target")"
        cp -f "$CACHE_DIR/$dep_hash" "$OUTPUT_DIR/$dep_target"
    done < "$APP_DIR/dependencies.txt"
fi

# ---------- 5. 注入版本与构建时间 ----------
printf '==> 注入版本信息\n'
[ -f "$OUTPUT_DIR/index.html" ] || die "产物中缺少 index.html"
sed \
    -e "s|@APP_VERSION@|$VERSION|g" \
    -e "s|@APP_BUILD_TIME@|$BUILD_TIME|g" \
    -e "s|href=\"css/style.css\"|href=\"css/style.css?v=$VERSION\"|g" \
    -e "s|src=\"js/app.js\"|src=\"js/app.js?v=$VERSION\"|g" \
    "$SOURCE_DIR/index.html" > "$OUTPUT_DIR/index.html"

# 生成机器可读的版本信息，由 nginx 在 /version.json 暴露
cat > "$OUTPUT_DIR/version.json" <<EOF
{
  "name": "bid-calculator-frontend",
  "version": "$VERSION",
  "revision": "$REVISION",
  "buildTime": "$BUILD_TIME"
}
EOF

# ---------- 6. 产物自检 ----------
printf '==> 校验构建产物\n'
required="index.html version.json css/style.css js/app.js vendor/tailwindcss/3.4.17/tailwind.min.js vendor/alpinejs/3.14.1/alpine.min.js"
for f in $required; do
    [ -f "$OUTPUT_DIR/$f" ] || die "构建产物缺失: $OUTPUT_DIR/$f（静态资源路径必须与 nginx root 目录结构对应）"
done

# 注入标记必须已替换；页面不得再引用运行时外网 CDN（保证容器/本机无外网时行为一致）
grep -q '@APP_VERSION@' "$OUTPUT_DIR/index.html" && die "index.html 中版本占位符未被替换"
grep -q '@APP_BUILD_TIME@' "$OUTPUT_DIR/index.html" && die "index.html 中构建时间占位符未被替换"
if grep -Eq 'https?://(cdn|unpkg|fonts)\.' "$OUTPUT_DIR/index.html"; then
    die "index.html 仍引用运行时外部资源（cdn/unpkg/fonts），请改为 dist/vendor 下的本地固化资源"
fi

printf '\n构建完成：%s\n' "$OUTPUT_DIR"
printf '版本: %s  构建时间: %s\n' "$VERSION" "$BUILD_TIME"
