#!/bin/sh
# 静态站点构建脚本（本地开发与 Docker 构建共用，保证产物一致）
#
# 必填环境变量：
#   APP_VERSION  版本号（如 git 短 SHA 或语义化版本）
#   BUILD_TIME   构建时间（RFC 3339 / ISO 8601，如 2026-09-21T08:00:00Z）
#
# 可选环境变量：
#   DEPS_CACHE_DIR / DEPS_TIMEOUT / DEPS_TRIES / DEPS_MIRRORS 透传给 fetch-deps.sh
#
# 产物：dist/ —— 与容器内 web 根目录（/app）结构完全一致
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
DIST_DIR="$PROJECT_DIR/dist"

# ---------- 1. 构建参数校验（缺失即明确报错并停止） ----------
if [ -z "${APP_VERSION:-}" ]; then
    echo "ERROR: 缺少构建参数 APP_VERSION（版本号），构建中止" >&2
    echo "       示例: APP_VERSION=1.0.0 BUILD_TIME=\$(date -u +%Y-%m-%dT%H:%M:%SZ) sh scripts/build.sh" >&2
    exit 1
fi
if [ -z "${BUILD_TIME:-}" ]; then
    echo "ERROR: 缺少构建参数 BUILD_TIME（构建时间，RFC 3339），构建中止" >&2
    exit 1
fi

# 简单格式校验：YYYY-MM-DDThh:mm:ssZ
case "$BUILD_TIME" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) ;;
    *)
        echo "ERROR: BUILD_TIME 格式无效: $BUILD_TIME" >&2
        echo "       要求 RFC 3339/ISO 8601 UTC 格式，例如 2026-09-21T08:00:00Z" >&2
        exit 1
        ;;
esac

echo "==> 开始构建: version=$APP_VERSION build_time=$BUILD_TIME"

# ---------- 2. 拉取/校验第三方依赖（失败会中止） ----------
sh "$SCRIPT_DIR/fetch-deps.sh"

# ---------- 3. 清理旧产物，重建目录 ----------
rm -rf "$DIST_DIR"
mkdir -p \
    "$DIST_DIR/assets/css" \
    "$DIST_DIR/assets/js" \
    "$DIST_DIR/assets/fonts"

# ---------- 4. 复制源码与已锁定依赖（路径即线上路径） ----------
cp "$PROJECT_DIR/src/css/style.css"        "$DIST_DIR/assets/css/style.css"
cp "$PROJECT_DIR/src/js/app.js"            "$DIST_DIR/assets/js/app.js"
cp "$PROJECT_DIR/vendor/js/tailwind.js"    "$DIST_DIR/assets/js/tailwind.js"
cp "$PROJECT_DIR/vendor/js/alpine.min.js"  "$DIST_DIR/assets/js/alpine.min.js"
cp "$PROJECT_DIR/vendor/fonts/"*.woff2     "$DIST_DIR/assets/fonts/"

# Inter 字体（本地 latin 子集，去掉对 Google Fonts 的运行时依赖）
cat > "$DIST_DIR/assets/fonts/inter.css" <<'FONTS_CSS'
@font-face {
  font-family: 'Inter';
  font-style: normal;
  font-display: swap;
  font-weight: 400;
  src: url(./inter-latin-400-normal.woff2) format('woff2');
  unicode-range: U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,U+0304,U+0308,U+0329,U+2000-206F,U+2074,U+20AC,U+2122,U+2191,U+2193,U+2212,U+2215,U+FEFF,U+FFFD;
}
@font-face {
  font-family: 'Inter';
  font-style: normal;
  font-display: swap;
  font-weight: 500;
  src: url(./inter-latin-500-normal.woff2) format('woff2');
  unicode-range: U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,U+0304,U+0308,U+0329,U+2000-206F,U+2074,U+20AC,U+2122,U+2191,U+2193,U+2212,U+2215,U+FEFF,U+FFFD;
}
@font-face {
  font-family: 'Inter';
  font-style: normal;
  font-display: swap;
  font-weight: 600;
  src: url(./inter-latin-600-normal.woff2) format('woff2');
  unicode-range: U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,U+0304,U+0308,U+0329,U+2000-206F,U+2074,U+20AC,U+2122,U+2191,U+2193,U+2212,U+2215,U+FEFF,U+FFFD;
}
@font-face {
  font-family: 'Inter';
  font-style: normal;
  font-display: swap;
  font-weight: 700;
  src: url(./inter-latin-700-normal.woff2) format('woff2');
  unicode-range: U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,U+0304,U+0308,U+0329,U+2000-206F,U+2074,U+20AC,U+2122,U+2191,U+2193,U+2212,U+2215,U+FEFF,U+FFFD;
}
FONTS_CSS

# ---------- 5. 注入版本与构建时间到 HTML ----------
# 使用 | 作为 sed 分隔符；APP_VERSION / BUILD_TIME 不应包含该字符
case "$APP_VERSION$BUILD_TIME" in
    *'|'*) echo "ERROR: APP_VERSION / BUILD_TIME 不允许包含字符 '|'" >&2; exit 1 ;;
esac
sed -e "s|@@APP_VERSION@@|$APP_VERSION|g" \
    -e "s|@@BUILD_TIME@@|$BUILD_TIME|g" \
    "$PROJECT_DIR/src/index.html.tmpl" > "$DIST_DIR/index.html"

# 同步提供机器可读的版本信息
cat > "$DIST_DIR/version.json" <<EOF
{
  "version": "$APP_VERSION",
  "buildTime": "$BUILD_TIME"
}
EOF

# ---------- 6. 规范化时间戳，保证不同机器重复构建产物字节一致 ----------
# Dockerfile 会把 SOURCE_DATE_EPOCH 设为与 BUILD_TIME 同一时刻
if [ -n "${SOURCE_DATE_EPOCH:-}" ] && command -v touch >/dev/null 2>&1; then
    # 纯 POSIX：把 epoch 转成 UTC 的 YYYYMMDDhhmm.ss，不依赖 GNU 的 -d @epoch
    days=$((SOURCE_DATE_EPOCH / 86400))
    secs=$((SOURCE_DATE_EPOCH % 86400))
    hour=$((secs / 3600)); secs=$((secs % 3600))
    min=$((secs / 60)); sec=$((secs % 60))

    # is_leap <year> → 输出 1/0：能被4整除且（不能被100整除或能被400整除）
    is_leap() {
        _y=$1
        if [ $((_y % 4)) -eq 0 ] && { [ $((_y % 100)) -ne 0 ] || [ $((_y % 400)) -eq 0 ]; }; then
            echo 1
        else
            echo 0
        fi
    }

    year=1970
    while :; do
        ydays=365; [ "$(is_leap "$year")" = 1 ] && ydays=366
        [ "$days" -lt "$ydays" ] && break
        days=$((days - ydays)); year=$((year + 1))
    done

    set -- 31 28 31 30 31 30 31 31 30 31 30 31
    month=1
    while [ "$month" -le 12 ]; do
        eval "md=\${$month}"
        [ "$month" -eq 2 ] && [ "$(is_leap "$year")" = 1 ] && md=29
        [ "$days" -lt "$md" ] && break
        days=$((days - md)); month=$((month + 1))
    done
    mday=$((days + 1))
    touch_time=$(printf '%04d%02d%02d%02d%02d.%02d' "$year" "$month" "$mday" "$hour" "$min" "$sec")
    find "$DIST_DIR" -type f -exec touch -h -t "$touch_time" {} +
fi

echo "==> 构建完成，产物目录: $DIST_DIR"
find "$DIST_DIR" -type f | sort | sed "s|$DIST_DIR/|    |"
