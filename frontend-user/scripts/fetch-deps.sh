#!/bin/sh
# fetch-deps.sh — 下载并校验前端第三方依赖（本地构建与 Docker 构建共用）
#
# 用法: fetch-deps.sh <依赖清单> <产物目录> <缓存目录>
# 环境: FETCH_TIMEOUT=单次下载超时秒数(默认30)  FETCH_RETRIES=重试次数(默认3)
#       CACHE_ONLY=1 时只预热内容寻址缓存，不向产物目录拷贝（Docker 分层预热用）
#
# 依赖清单每行三列（# 开头为注释）：
#   <相对产物目录的路径> <SHA256> <下载URL>
#
# 依赖按 SHA256 内容寻址缓存，缓存命中时不访问网络；
# 下载超时、重试耗尽或哈希校验失败都会打印明确错误并以非零码退出。

set -eu

DEPS_FILE=${1:?用法: fetch-deps.sh <依赖清单> <产物目录> <缓存目录>}
OUTPUT_DIR=${2:?缺少产物目录参数}
CACHE_DIR=${3:?缺少缓存目录参数}
FETCH_TIMEOUT=${FETCH_TIMEOUT:-30}
FETCH_RETRIES=${FETCH_RETRIES:-3}

die() {
    printf '错误：%s\n' "$*" >&2
    exit 1
}

[ -f "$DEPS_FILE" ] || die "依赖清单不存在: $DEPS_FILE"

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "$1" | awk '{print $NF}'
    else
        die "未找到 sha256sum/shasum/openssl，无法校验依赖完整性"
    fi
}

# download_to <url> <临时文件>：失败/超时重试，耗尽后明确报错停止
download_to() {
    _url=$1
    _tmp=$2
    _attempt=1
    while :; do
        set +e
        if command -v curl >/dev/null 2>&1; then
            curl -fsSL --connect-timeout 10 --max-time "$FETCH_TIMEOUT" -o "$_tmp" "$_url"
            _rc=$?
        elif command -v wget >/dev/null 2>&1; then
            wget -q -T "$FETCH_TIMEOUT" -O "$_tmp" "$_url"
            _rc=$?
        else
            die "未找到 curl 或 wget，无法拉取依赖"
        fi
        set -e
        [ "$_rc" -eq 0 ] && break
        rm -f "$_tmp"
        if [ "$_attempt" -ge "$FETCH_RETRIES" ]; then
            die "拉取依赖超时或失败: $_url（已重试 ${FETCH_RETRIES} 次，单次超时 ${FETCH_TIMEOUT}s，退出码 $_rc）。请检查网络/代理后重试。"
        fi
        printf '警告：第 %s 次拉取失败（退出码 %s），2 秒后重试...\n' "$_attempt" "$_rc" >&2
        _attempt=$((_attempt + 1))
        sleep 2
    done
}

mkdir -p "$OUTPUT_DIR" "$CACHE_DIR"

# 逐行读取清单（保留行内三列，忽略注释与空行）
while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
        ''|'#'*) continue ;;
    esac
    # shellcheck disable=SC2086
    set -- $line
    [ "$#" -ge 3 ] || die "依赖清单行格式应为: <路径> <SHA256> <URL>，实际: $line"
    target=$1
    expected_hash=$2
    url=$3

    target_dir=$OUTPUT_DIR/$(dirname "$target")
    target_file=$OUTPUT_DIR/$target
    cache_file=$CACHE_DIR/$expected_hash
    [ -n "${CACHE_ONLY:-}" ] || mkdir -p "$target_dir"

    # 命中内容寻址缓存：先校验再使用
    if [ -f "$cache_file" ]; then
        actual_hash=$(sha256_file "$cache_file")
        if [ "$actual_hash" = "$expected_hash" ]; then
            if [ -z "${CACHE_ONLY:-}" ]; then
                cp -f "$cache_file" "$target_file"
            fi
            printf '依赖（缓存命中）: %s\n' "$target"
            continue
        fi
        printf '警告：缓存文件哈希不符，重新下载: %s\n' "$expected_hash" >&2
        rm -f "$cache_file"
    fi

    printf '依赖（下载中）: %s\n' "$target"
    download_to "$url" "$CACHE_DIR/$expected_hash.part"

    actual_hash=$(sha256_file "$CACHE_DIR/$expected_hash.part")
    if [ "$actual_hash" != "$expected_hash" ]; then
        rm -f "$CACHE_DIR/$expected_hash.part"
        die "依赖完整性校验失败: $url
  期望 SHA256: $expected_hash
  实际 SHA256: $actual_hash
请确认 dependencies.txt 中的版本与哈希是否匹配。"
    fi

    mv "$CACHE_DIR/$expected_hash.part" "$cache_file"
    if [ -z "${CACHE_ONLY:-}" ]; then
        cp -f "$cache_file" "$target_file"
    fi
done < "$DEPS_FILE"

printf '全部依赖校验通过。\n'
