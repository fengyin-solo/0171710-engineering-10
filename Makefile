# 投标报价计算器 —— 统一构建入口
#
# 常用目标：
#   make build-local   本机生成 frontend-user/dist（版本=当前 git 短 SHA）
#   make serve-local   用 Python 静态服务器在 :8082 预览 dist（无需 Docker）
#   make up            docker compose 构建并后台启动（:8082）
#   make dev           本地开发模式（挂载 dist，改完源码跑 make build-local）
#   make image-multi   buildx 同时构建 amd64+arm64（需 --push 或 --load 场景）
#   make clean         清理 dist 与依赖缓存

SHELL := /bin/sh

VERSION      ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo unknown)
# 跨平台生成 RFC 3339 UTC 时间（GNU/BSD/macOS date 兼容写法）
BUILD_TIME   ?= $(shell date -u +%Y-%m-%dT%H:%M:%SZ)
IMAGE        ?= bid-calculator-frontend
PLATFORMS    ?= linux/amd64,linux/arm64

.EXPORT_ALL_VARIABLES:

.PHONY: help build-local serve-local up down dev dev-down image-multi clean verify

help:
	@echo "可用目标："
	@echo "  build-local   本机构建静态产物到 frontend-user/dist (VERSION=$(VERSION))"
	@echo "  serve-local   本机 :8082 预览（与容器同一套文件/路径）"
	@echo "  up            docker compose 构建并启动 http://localhost:8082"
	@echo "  dev           本地开发：先 build-local 再以挂载方式启动"
	@echo "  image-multi   buildx 跨架构构建 ($(PLATFORMS))"
	@echo "  verify        校验产物引用路径全部存在"
	@echo "  clean         清理 dist 与依赖缓存"

# ---------- 本机构建（与 Docker 构建共用 scripts/build.sh） ----------
build-local:
	APP_VERSION=$(VERSION) BUILD_TIME=$(BUILD_TIME) sh frontend-user/scripts/build.sh

# ---------- 无 Docker 时的本机预览：同源路径、同端口 ----------
serve-local: build-local
	@echo "预览地址: http://localhost:8082 （Ctrl-C 退出）"
	cd frontend-user/dist && python3 -m http.server 8082

# ---------- Docker：正式方式 ----------
up:
	APP_VERSION=$(VERSION) BUILD_TIME=$(BUILD_TIME) docker compose up --build -d

down:
	docker compose down

# ---------- Docker：本地开发方式（挂载 dist，实时改文件） ----------
dev: build-local
	APP_VERSION=$(VERSION) BUILD_TIME=$(BUILD_TIME) \
	  docker compose -f docker-compose.yml -f docker-compose.dev.yml up --build

dev-down:
	docker compose -f docker-compose.yml -f docker-compose.dev.yml down

# ---------- 跨架构构建（ARM64 + X86/AMD64），产物可重复 ----------
# 基础镜像按 index digest 锁定；BUILD_TIME 固定后，两台机器产出镜像内容一致。
# 需要推到 registry 时追加 PUSH=1（多架构无法 --load 到本地）
image-multi:
	docker buildx create --use --name bid-calculator-builder 2>/dev/null || true
	docker buildx build \
	  --platform $(PLATFORMS) \
	  --build-arg APP_VERSION=$(VERSION) \
	  --build-arg BUILD_TIME=$(BUILD_TIME) \
	  -t $(IMAGE):$(VERSION) \
	  $(if $(PUSH),--push,--load) \
	  -f frontend-user/Dockerfile .

# ---------- 产物自检：HTML 中引用的本地资源必须全部存在 ----------
verify: build-local
	@python3 frontend-user/scripts/verify_dist.py

# ---------- 清理 ----------
clean:
	rm -rf frontend-user/dist frontend-user/vendor/.cache
	@echo "已清理 dist 与依赖缓存"
