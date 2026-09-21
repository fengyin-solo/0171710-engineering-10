# 投标报价计算器 — 统一构建/运行入口
#
# 常用目标:
#   make build       本机构建静态产物到 frontend-user/dist（不依赖 Docker）
#   make dev         本机以与生产相同的 nginx 镜像启动（http://localhost:8082）
#   make up          构建生产镜像并启动（http://localhost:8082）
#   make image       仅构建当前架构镜像
#   make image-multi 构建 ARM64+X86_64 双架构镜像并推送 REGISTRY（需先 docker login）
#   make down        停止并移除容器
#   make clean       清理本机 dist 与依赖缓存

# 版本与构建时间：VERSION 缺失时从 git 推导；推导不出则报错停止。
# BUILD_TIME 固定为 UTC RFC3339；要复现同一镜像，显式传入相同的 VERSION 与 BUILD_TIME。
VERSION ?= $(shell git -C . describe --tags --exact-match 2>/dev/null || git -C . describe --tags 2>/dev/null || git -C . rev-parse --short HEAD 2>/dev/null)
BUILD_TIME ?= $(shell date -u +%Y-%m-%dT%H:%M:%SZ)
REVISION ?= $(shell git -C . rev-parse HEAD 2>/dev/null || echo unknown)

REGISTRY ?=
IMAGE_NAME ?= bid-calculator-frontend
IMAGE_TAG := $(VERSION)
IMAGE_REF := $(if $(REGISTRY),$(REGISTRY)/$(IMAGE_NAME):$(IMAGE_TAG),$(IMAGE_NAME):$(IMAGE_TAG))
PLATFORMS ?= linux/arm64,linux/amd64

DIST_DIR := frontend-user/dist
COMPOSE := docker compose
COMPOSE_DEV := $(COMPOSE) -f docker-compose.yml -f docker-compose.dev.yml
EXPORT_ENV := VERSION='$(VERSION)' BUILD_TIME='$(BUILD_TIME)' REVISION='$(REVISION)'

.PHONY: help build dev-build dev up down image image-multi clean check-env

help:
	@echo '投标报价计算器构建入口'
	@echo '  make build        本机构建静态产物 ($(DIST_DIR))'
	@echo '  make dev          本机 nginx 启动（与生产一致，:8082）'
	@echo '  make up           构建生产镜像并启动（:8082）'
	@echo '  make image        构建当前架构镜像: $(IMAGE_REF)'
	@echo '  make image-multi  双架构构建并推送: $(PLATFORMS)'
	@echo '  make down         停止容器'
	@echo '  make clean        清理本机构建产物与缓存'
	@echo
	@echo 'VERSION=$(VERSION)  BUILD_TIME=$(BUILD_TIME)  REVISION=$(REVISION)'

check-env:
	@if [ -z "$(VERSION)" ]; then \
	  echo '错误：无法推导 VERSION（不在 git 仓库或无提交），请显式指定: make build VERSION=x.y.z' >&2; \
	  exit 1; \
	fi
	@if [ -z "$(BUILD_TIME)" ]; then \
	  echo '错误：BUILD_TIME 为空，请显式传入 UTC 时间: make build BUILD_TIME=2026-01-01T00:00:00Z' >&2; \
	  exit 1; \
	fi

# ---------- 本机静态构建（本地与容器使用同一脚本，输出同一布局） ----------
build: check-env
	VERSION='$(VERSION)' BUILD_TIME='$(BUILD_TIME)' REVISION='$(REVISION)' \
	  sh frontend-user/scripts/build.sh

# ---------- 本机开发：同镜像、同 nginx 配置、同端口、同目录结构 ----------
dev-build: check-env
	VERSION='$(VERSION)' BUILD_TIME='$(BUILD_TIME)' REVISION='$(REVISION)' \
	  sh frontend-user/scripts/build.sh

dev:
	@docker version >/dev/null 2>&1 || { echo '错误：未检测到 Docker，请先启动 Docker。' >&2; exit 1; }
	$(EXPORT_ENV) $(COMPOSE_DEV) up --build -d
	@echo '本机开发服务已启动: http://localhost:8082（与容器生产行为一致）'

# ---------- 生产镜像 ----------
image: check-env
	@docker version >/dev/null 2>&1 || { echo '错误：未检测到 Docker，请先启动 Docker。' >&2; exit 1; }
	$(EXPORT_ENV) sh scripts/build-image.sh --tag '$(IMAGE_REF)'

image-multi: check-env
	@docker version >/dev/null 2>&1 || { echo '错误：未检测到 Docker，请先启动 Docker。' >&2; exit 1; }
	@if [ -z "$(REGISTRY)" ]; then \
	  echo '错误：双架构构建必须推送，请指定 REGISTRY，例如: make image-multi REGISTRY=registry.example.com/app' >&2; \
	  exit 1; \
	fi
	$(EXPORT_ENV) sh scripts/build-image.sh --platforms '$(PLATFORMS)' --push --tag '$(IMAGE_REF)'

# ---------- compose 运行 ----------
up: check-env
	@docker version >/dev/null 2>&1 || { echo '错误：未检测到 Docker，请先启动 Docker。' >&2; exit 1; }
	$(EXPORT_ENV) $(COMPOSE) up --build -d
	@echo '服务已启动: http://localhost:8082'

down:
	-$(COMPOSE) down
	-$(COMPOSE_DEV) down

# ---------- 清理 ----------
clean:
	rm -rf $(DIST_DIR) frontend-user/.cache
	@echo '已清理 $(DIST_DIR) 与 frontend-user/.cache'
