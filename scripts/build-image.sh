#!/bin/sh
# build-image.sh — Docker 镜像构建封装（本机单架构 / buildx 跨平台）
#
# 必填环境变量（缺失立即明确报错并停止，与 Dockerfile 内校验形成双保险）:
#   VERSION      版本号
#   BUILD_TIME   构建时间（UTC RFC3339；复现镜像时传入相同值）
#   REVISION     源码版本标识（可选，默认 unknown）
#
# 参数:
#   --tag <ref>           镜像引用（可多次指定）
#   --platforms <list>    跨平台构建，如 linux/arm64,linux/amd64
#   --push                构建后推送（跨平台时必需，多架构清单无法加载到本机 docker）
#   --load                构建后加载到本机 docker（单架构默认）
#   --context <dir>       构建上下文（默认 frontend-user）
#
# 超时控制:
#   依赖拉取超时由 frontend-user/scripts/fetch-deps.sh 处理
#   （FETCH_TIMEOUT / FETCH_RETRIES），失败会明确报错并停止构建。

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CONTEXT_DIR=$SCRIPT_DIR/frontend-user

die() {
    printf '\n镜像构建失败：%s\n' "$*" >&2
    exit 1
}

# ---------- 环境前置检查 ----------
docker version >/dev/null 2>&1 || die "未检测到可用的 Docker 守护进程，请先启动 Docker。"

[ -n "${VERSION:-}" ] || die "缺少必填环境变量 VERSION，例如: VERSION=1.0.0 $0 --tag myapp:1.0.0"
[ -n "${BUILD_TIME:-}" ] || die "缺少必填环境变量 BUILD_TIME（UTC RFC3339），例如: BUILD_TIME=\"\$(date -u +%Y-%m-%dT%H:%M:%SZ)\""
REVISION=${REVISION:-unknown}

TAGS=
PLATFORMS=
PUSH=

while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag)
            [ "$#" -ge 2 ] || die "--tag 需要参数"
            TAGS="$TAGS $2"
            shift 2
            ;;
        --platforms)
            [ "$#" -ge 2 ] || die "--platforms 需要参数"
            PLATFORMS=$2
            shift 2
            ;;
        --push)
            PUSH=1
            shift
            ;;
        --load)
            # 单架构默认即 load 到本机，此参数仅为显式兼容而保留
            shift
            ;;
        --context)
            [ "$#" -ge 2 ] || die "--context 需要参数"
            CONTEXT_DIR=$2
            shift 2
            ;;
        -h|--help)
            grep '^#' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            die "未知参数: $1（见 --help）"
            ;;
    esac
done

[ -n "$TAGS" ] || die "必须通过 --tag 指定至少一个镜像引用"
[ -f "$CONTEXT_DIR/Dockerfile" ] || die "构建上下文缺少 Dockerfile: $CONTEXT_DIR/Dockerfile"

BUILD_ARGS="--build-arg VERSION=$VERSION --build-arg BUILD_TIME=$BUILD_TIME --build-arg REVISION=$REVISION"

TAG_FLAGS=
for t in $TAGS; do
    TAG_FLAGS="$TAG_FLAGS -t $t"
done

if [ -n "$PLATFORMS" ]; then
    # ---------- 跨平台（ARM64 + X86_64 等） ----------
    docker buildx version >/dev/null 2>&1 || die "需要 docker buildx 支持才能跨平台构建（PLATFORMS=$PLATFORMS）"
    case ",$PLATFORMS," in
        *,linux/arm64,*|*,linux/amd64,*) ;;
        *) die "当前仅验证 linux/arm64 与 linux/amd64，收到: $PLATFORMS" ;;
    esac
    [ -n "$PUSH" ] || die "跨平台构建（$PLATFORMS）必须配合 --push，多架构清单无法直接 load 到本机 docker"

    printf '==> 跨平台构建 %s -> %s\n' "$PLATFORMS" "$TAGS"
    # shellcheck disable=SC2086
    docker buildx build \
        --platform "$PLATFORMS" \
        $BUILD_ARGS $TAG_FLAGS \
        --push \
        "$CONTEXT_DIR"
    printf '\n跨平台镜像已推送:%s\n' "$TAGS"
    printf '重复构建前提: 相同源码 + 相同 VERSION/BUILD_TIME + 相同基础镜像 digest（已在 Dockerfile 固定）\n'
else
    # ---------- 本机单架构（统一走 buildx/buildkit，支持 cache mount 与 syntax 指令） ----------
    ACTION_FLAG=--load
    [ -n "$PUSH" ] && ACTION_FLAG=--push
    printf '==> 单架构构建%s -> %s\n' "$([ -n "$PUSH" ] && echo '并推送' || echo '')" "$TAGS"
    # shellcheck disable=SC2086
    docker buildx build $ACTION_FLAG $BUILD_ARGS $TAG_FLAGS "$CONTEXT_DIR"
    for t in $TAGS; do
        printf '已构建镜像: %s (VERSION=%s BUILD_TIME=%s)\n' "$t" "$VERSION" "$BUILD_TIME"
    done
fi
