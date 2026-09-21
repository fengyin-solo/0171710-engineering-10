# syntax=docker/dockerfile:1.7
#
# 投标报价计算器 — 镜像构建
#
# 静态文件目录在本地与容器中完全统一：
#   public/ ──(scripts/build.sh)──> dist/ ──COPY──> /usr/share/nginx/html
# 本机开发用 docker compose 的 dev override bind mount 同一份 dist/。
#
# 必填构建参数（缺失或为空会立即明确报错并停止构建）:
#   --build-arg VERSION=x.y.z
#   --build-arg BUILD_TIME=2026-01-01T00:00:00Z
# 可选:
#   --build-arg REVISION=<git sha>
#
# 跨平台（ARM64 / X86_64 可重复构建）:
#   - 基础镜像按多架构 OCI index digest 固定，两架构拉到的内容确定一致
#   - builder 使用 BUILDPLATFORM（只做下载/文本替换，与目标架构无关）
#   - 最终阶段按 TARGETPLATFORM 选择对应架构镜像
#   构建: docker buildx build --platform linux/arm64,linux/amd64 ...
#
# 可重复性:
#   同一份源码 + 相同 VERSION/BUILD_TIME 构建出的镜像层内容一致
#   （BUILD_TIME 需由调用方固定，例如由 SOURCE_DATE_EPOCH 转换而来）。

# nginx:alpine 多架构索引（nginx 1.31.6, alpine），同时适用于 TARGETPLATFORM 与 BUILDPLATFORM
ARG NGINX_IMAGE=nginx@sha256:62ff2089abf5a9ed33bd232895bef5e22f7bb4b200675cec49a5ebc48e3d4ac8

# ---------- builder：与目标架构无关，固定在构建机平台执行 ----------
FROM --platform=$BUILDPLATFORM ${NGINX_IMAGE} AS builder

# 必填构建参数：在首个 RUN 中强校验，缺失立即给出明确错误并停止
ARG VERSION
ARG BUILD_TIME
ARG REVISION=unknown
# 依赖拉取超时/重试（可在构建时覆盖，见 scripts/fetch-deps.sh）
ARG FETCH_TIMEOUT=30
ARG FETCH_RETRIES=3

WORKDIR /build

# 仅先复制构建脚本与依赖清单：该层只在脚本/依赖版本变化时失效
COPY scripts/ ./scripts/
COPY dependencies.txt ./dependencies.txt

# 预热依赖：下载结果存入 BuildKit cache mount，源码改动不触发重新拉取
RUN --mount=type=cache,id=bid-calc-vendor,target=/build/.cache/vendor \
    if [ -z "$VERSION" ]; then \
      echo '错误：缺少必填构建参数 --build-arg VERSION=x.y.z，构建停止。' >&2; exit 1; \
    fi; \
    if [ -z "$BUILD_TIME" ]; then \
      echo '错误：缺少必填构建参数 --build-arg BUILD_TIME=YYYY-MM-DDThh:mm:ssZ，构建停止。' >&2; exit 1; \
    fi; \
    chmod +x scripts/build.sh scripts/fetch-deps.sh; \
    staging=$(mktemp -d); \
    FETCH_TIMEOUT="$FETCH_TIMEOUT" FETCH_RETRIES="$FETCH_RETRIES" CACHE_ONLY=1 \
      sh scripts/fetch-deps.sh dependencies.txt "$staging" .cache/vendor; \
    rm -rf "$staging"

# 复制静态源文件（唯一来源 public/）后执行统一构建脚本（依赖从预热缓存恢复）
COPY public/ ./public/
RUN --mount=type=cache,id=bid-calc-vendor,target=/build/.cache/vendor \
    VERSION="$VERSION" BUILD_TIME="$BUILD_TIME" REVISION="$REVISION" \
    SKIP_DEPS=1 sh scripts/build.sh

# ---------- 运行时：按目标架构选择镜像 ----------
FROM --platform=$TARGETPLATFORM ${NGINX_IMAGE}

ARG VERSION
ARG BUILD_TIME
ARG REVISION=unknown

LABEL org.opencontainers.image.title="bid-calculator-frontend" \
      org.opencontainers.image.description="投标报价计算器静态前端（nginx 托管）" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.created="${BUILD_TIME}"

# 启动方式与官方镜像保持一致：/docker-entrypoint.sh + nginx -g 'daemon off;'（继承自基础镜像，不再覆盖）
# 暴露端口固定为 80（compose 统一映射 8082:80）
EXPOSE 80

# 清理官方镜像默认静态页面，避免与本应用产物混杂
RUN rm -rf /usr/share/nginx/html/*

# 拷贝构建产物：dist 布局与容器内 web root 一一对应
COPY --from=builder /build/dist/ /usr/share/nginx/html/

# 统一站点配置与安全头片段
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY docker/nginx-includes/security-headers.conf /etc/nginx/security-headers.conf

# 健康检查与 compose 保持一致（busybox wget 为 nginx:alpine 自带）
HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=5s \
    CMD wget -q --spider http://127.0.0.1:80/healthz || exit 1

# 构建期元数据以环境变量留存（仅静态信息，容器重启不变化）
ENV APP_VERSION=${VERSION} \
    APP_BUILD_TIME=${BUILD_TIME} \
    APP_REVISION=${REVISION}
