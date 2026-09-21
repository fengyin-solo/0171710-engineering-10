#!/bin/sh
# 拉取第三方依赖（本地构建与容器构建共用）
#
# 特性：
#   - 版本与 sha256 由 vendor/dependencies.lock 锁定
#   - 下载内容按 sha256 缓存（DEPS_CACHE_DIR），命中缓存只做校验，可重复产出
#   - 单文件下载超时（DEPS_TIMEOUT，默认 30s）、重试（DEPS_TRIES，默认 3）
#   - 支持镜像前缀回退（DEPS_MIRRORS，默认仅 https://）
#   - 拉取失败或校验和不符：打印明确错误并以非零码退出
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
LOCK_FILE="$PROJECT_DIR/vendor/dependencies.lock"
VENDOR_DIR="$PROJECT_DIR/vendor"
DEPS_CACHE_DIR=${DEPS_CACHE_DIR:-"$VENDOR_DIR/.cache"}
DEPS_TIMEOUT=${DEPS_TIMEOUT:-30}
DEPS_TRIES=${DEPS_TRIES:-3}
# 镜像前缀需以 / 结尾；按顺序尝试
DEPS_MIRRORS=${DEPS_MIRRORS:-"https://"}

if [ ! -f "$LOCK_FILE" ]; then
    echo "ERROR: 依赖清单不存在: $LOCK_FILE" >&2
    exit 1
fi

mkdir -p "$DEPS_CACHE_DIR"

# 下载单个文件到指定路径：download <url> <dest>
download() {
    _url=$1
    _dest=$2
    if command -v curl >/dev/null 2>&1; then
        curl --fail --silent --show-error --location \
             --connect-timeout "$DEPS_TIMEOUT" --max-time "$DEPS_TIMEOUT" \
             --output "$_dest" "$_url"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -T "$DEPS_TIMEOUT" -O "$_dest" "$_url"
    else
        echo "ERROR: 需要 curl 或 wget 来拉取依赖，当前环境均未找到" >&2
        exit 1
    fi
}

# 校验文件 sha256：check_sha256 <file> <expected>
check_sha256() {
    _file=$1
    _expected=$2
    _actual=$(sha256sum "$_file" | awk '{print $1}')
    if [ "$_actual" != "$_expected" ]; then
        return 1
    fi
}

# 按镜像顺序、带重试地下载：fetch_with_retry <url_path> <dest>
fetch_with_retry() {
    _url_path=$1
    _dest=$2
    _attempt=1
    # shellcheck disable=SC2086
    for _mirror in $DEPS_MIRRORS; do
        while [ "$_attempt" -le "$DEPS_TRIES" ]; do
            _url="${_mirror}${_url_path}"
            echo "  → 下载 $_url (尝试 $_attempt/$DEPS_TRIES, 超时 ${DEPS_TIMEOUT}s)"
            if download "$_url" "$_dest"; then
                return 0
            fi
            echo "  ! 第 $_attempt 次拉取失败（可能超时）" >&2
            _attempt=$((_attempt + 1))
        done
        echo "  ! 镜像 $_mirror 拉取失败，尝试下一个镜像源" >&2
        _attempt=1
    done
    return 1
}

fail=0
echo "==> 校验/拉取第三方依赖"

# 逐行读取清单（跳过空行与注释行）
while IFS='|' read -r relpath expected_sha url_path; do
    [ -n "${relpath:-}" ] || continue
    case "$relpath" in \#*) continue ;; esac

    target="$PROJECT_DIR/$relpath"
    cached="$DEPS_CACHE_DIR/$expected_sha"
    mkdir -p "$(dirname "$target")"

    # 1) 已存在且校验通过 → 跳过
    if [ -f "$target" ] && check_sha256 "$target" "$expected_sha"; then
        echo "  = $relpath 已存在且校验通过，跳过"
        continue
    fi

    # 2) 缓存命中（内容寻址）→ 直接恢复
    if [ -f "$cached" ] && check_sha256 "$cached" "$expected_sha"; then
        cp "$cached" "$target"
        echo "  = $relpath 使用本地缓存"
        continue
    fi

    # 3) 网络拉取（临时文件，成功后原子替换）
    tmp="$target.tmp.$$"
    if ! fetch_with_retry "$url_path" "$tmp"; then
        echo "ERROR: 依赖拉取超时或失败: $url_path" >&2
        echo "       可设置 DEPS_MIRRORS 切换镜像源后重试，例如:" >&2
        echo "       DEPS_MIRRORS='https://npm.elemecdn.com/ https://'" >&2
        rm -f "$tmp"
        fail=1
        continue
    fi

    if ! check_sha256 "$tmp" "$expected_sha"; then
        echo "ERROR: 依赖校验和不符: $relpath" >&2
        echo "       期望 $expected_sha" >&2
        echo "       实际 $(sha256sum "$tmp" | awk '{print $1}')" >&2
        rm -f "$tmp"
        fail=1
        continue
    fi

    mv "$tmp" "$target"
    cp "$target" "$cached"
    echo "  + $relpath 拉取并校验通过"
done < "$LOCK_FILE"

if [ "$fail" -ne 0 ]; then
    echo "ERROR: 存在依赖拉取失败，构建中止" >&2
    exit 1
fi

echo "==> 所有依赖就绪"
