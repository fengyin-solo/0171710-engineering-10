# syntax=docker/dockerfile:1.7
#
# 投标报价计算器镜像
#
# 构建参数（必填，缺失会明确报错并停止）：
#   APP_VERSION   版本号
#   BUILD_TIME    构建时间，RFC 3339 UTC，例如 2026-09-21T08:00:00Z
#
# 跨平台：amd64 / arm64 共用同一 index digest 的基础镜像
# docker buildx build --platform linux/amd64,linux/arm64 ...

# ---------- Stage 1: 拉取依赖 ----------
# nginx:1.28.3-alpine（stable），按多架构 manifest list 的 index digest 锁定
ARG BASE_IMAGE=nginx@sha256:a8b39bd9cf0f83869a2162827a0caf6137ddf759d50a171451b335cecc87d236
FROM --platform=$BUILDPLATFORM ${BASE_IMAGE} AS deps

WORKDIR /build
COPY vendor/dependencies.lock ./vendor/dependencies.lock
COPY scripts/fetch-deps.sh ./scripts/fetch-deps.sh

# 内容寻址缓存：lock 不变则整层复用；也可挂载 BuildKit cache 加速
RUN --mount=type=cache,target=/build/vendor/.cache,sharing=locked \
    sh scripts/fetch-deps.sh

# ---------- Stage 2: 组装静态产物 ----------
FROM --platform=$BUILDPLATFORM ${BASE_IMAGE} AS builder

ARG APP_VERSION
ARG BUILD_TIME
RUN test -n "$APP_VERSION" || { echo "ERROR: 缺少构建参数 --build-arg APP_VERSION=<版本号>，构建中止" >&2; exit 1; }
RUN test -n "$BUILD_TIME"  || { echo "ERROR: 缺少构建参数 --build-arg BUILD_TIME=<RFC3339 UTC 时间>，构建中止" >&2; exit 1; }

WORKDIR /build
COPY --from=deps /build/vendor ./vendor
COPY scripts ./scripts
COPY src ./src

# BUILD_TIME(UTC) → epoch，作为产物统一 mtime，保证跨机器字节级可重复
# busybox 与 GNU date 都支持 -d "YYYY-MM-DD HH:MM:SS" 这种解析形式
RUN SOURCE_DATE_EPOCH=$(date -u -d "$(echo "$BUILD_TIME" | sed 's/T/ /; s/Z$//')" +%s) \
    && export SOURCE_DATE_EPOCH \
    && sh scripts/build.sh

# ---------- Stage 3: 运行时（目标平台） ----------
FROM --platform=$TARGETPLATFORM ${BASE_IMAGE} AS runtime

ARG APP_VERSION
ARG BUILD_TIME

# 镜像元数据（不含易变值，保证重复构建镜像 ID 一致）
LABEL org.opencontainers.image.title="bid-calculator-frontend" \
      org.opencontainers.image.description="投标报价计算器（纯静态 + nginx）" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.created="${BUILD_TIME}" \
      org.opencontainers.image.source="bid-calculator"

# 自定义 web 根目录，镜像内不再保留 nginx 默认页
ENV NGINX_WEBROOT=/app
# 官方镜像 entrypoint 启动时做 envsubst：${NGINX_WEBROOT} → /app
COPY nginx/default.conf /etc/nginx/templates/default.conf.template
COPY nginx/snippets/security-headers.conf /etc/nginx/snippets/security-headers.conf
# 构建产物静态资源路径与容器内目录一一对应（容器 /app ←→ 本机 dist/）
COPY --from=builder /build/dist/ /app/

# 容器内监听 80，与 compose 端口映射、文档保持一致
EXPOSE 80

# 运行时与官方镜像保持一致：entrypoint 先 envsubst 渲染模板，再以前台进程启动 nginx
# 健康检查使用 alpine 自带的 busybox wget，无需额外安装
CMD ["nginx", "-g", "daemon off;"]
