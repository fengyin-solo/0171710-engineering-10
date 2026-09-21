# 投标报价计算器

纯前端投标报价模拟计算工具（单低 / 双低评标模式），构建为 nginx 静态镜像交付。

## 目录结构

```
.
├── docker-compose.yml          # 正式编排（构建镜像运行）
├── docker-compose.dev.yml      # 本地开发覆盖（挂载本机 dist）
├── Makefile                    # 统一入口：本机/容器/跨架构构建
├── .env.example                # 构建参数示例（复制为 .env）
└── frontend-user/
    ├── Dockerfile              # 多阶段构建（deps → builder → runtime）
    ├── nginx/                  # nginx 配置（容器内 /etc/nginx/...）
    ├── scripts/
    │   ├── fetch-deps.sh       # 依赖拉取（锁版本 + sha256 校验 + 超时重试）
    │   ├── build.sh            # 构建脚本（本地与容器内共用同一份）
    │   └── verify_dist.py      # 产物路径自检
    ├── vendor/
    │   ├── dependencies.lock   # 第三方依赖版本与校验和清单
    │   ├── js/  fonts/         # 拉取下来的锁定依赖（git 跟踪）
    ├── src/                    # 唯一的静态文件源目录
    │   ├── index.html.tmpl     # 含 @@APP_VERSION@@ / @@BUILD_TIME@@ 占位符
    │   ├── css/  js/
    └── dist/                   # 构建产物（git 忽略）；容器 web 根 /app 与此 1:1
```

本地开发与容器运行使用**同一套静态文件**：都是 `scripts/build.sh` 产出的 `dist/`，
容器里放到 `/app`，路径结构完全相同（见下「构建链路一致性」）。

## 构建参数

| 参数 | 必填 | 说明 |
|------|------|------|
| `APP_VERSION` | 是 | 版本号，如 git 短 SHA |
| `BUILD_TIME` | 是 | 构建时间，RFC 3339 UTC，如 `2026-09-21T08:00:00Z` |

参数缺失或格式错误时，构建会打印明确错误并停止（`scripts/build.sh` 与 Dockerfile 各校验一次）。

## 快速开始

```bash
# 方式一：Docker（推荐，正式交付方式）
make up                     # 自动注入 VERSION=git 短 SHA、BUILD_TIME=当前 UTC 时间
# 等价于：APP_VERSION=$(git rev-parse --short HEAD) BUILD_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
#         docker compose up --build -d

# 方式二：本机开发（修改源码后重新 make build-local，刷新即可）
make dev                    # 构建 dist 并以只读挂载方式启动同一镜像/同一 nginx 配置

# 方式三：没有 Docker 时的本机预览（同一 dist、同端口 8082）
make serve-local

# 停止
make down          # 或 make dev-down
```

服务地址：**http://localhost:8082**（容器内监听 80，固定映射到宿主 8082）。

## 跨平台构建（ARM64 + X86/AMD64）

基础镜像 `nginx:1.28.3-alpine` 按多架构 index digest 锁定，amd64/arm64 同源；
依赖版本与 sha256 锁定、构建时间固定、产物 mtime 归一化，两台机器重复构建产物一致。

```bash
# 本机多架构（需 buildx；多架构要推仓库时加 PUSH=1）
make image-multi                       # linux/amd64,linux/arm64，--load
make image-multi PUSH=1                # 构建并推送多架构 manifest
PLATFORMS=linux/arm64 make image-multi # 只构建 ARM64
```

## 构建链路一致性

- **唯一源、唯一产物**：源文件只在 `frontend-user/src/`；`dist/` 由 `build.sh` 生成，
  容器 `/app` 直接复制 `dist/`，不存在「本地一套、容器里另一套」。
- **路径一一对应**：HTML 引用 `/assets/...` → 本机 `dist/assets/...` → 容器 `/app/assets/...`；
  `make verify` 会逐一校验引用文件真实存在。
- **版本注入**：构建期把 `APP_VERSION` / `BUILD_TIME` 写入页面 meta、页脚与 `/version.json`，
  本地与容器显示一致。
- **重启一致**：容器只读根文件系统 + tmpfs，无状态写入；`restart: unless-stopped`，
  `/healthz` 健康检查，重启后内容与行为不变。
- **依赖可靠**：拉取有超时（默认 30s）、重试（默认 3 次）与镜像回退（`DEPS_MIRRORS`），
  超时或 sha256 不符即报错停止；下载结果按 sha256 内容寻址缓存，lock 不变则缓存复用。
- **无运行时外网依赖**：Tailwind / Alpine / Inter 字体全部在构建期锁定并内置。

## 测试账号

无需登录，纯前端静态应用。

## 题目内容

> 新建一个 html 应用，用于模拟计算投标报价计算，支持单低和双低模式，比例、限价及分数都可以自定义，且可以任意添加多家报价。并计算显示报价是否有效和报价得分。

## 项目介绍

投标报价模拟计算工具，用于模拟评标过程中的价格分计算。

### 功能说明

1. **评标模式**
   - 单低模式：基准价 = 最低有效报价
   - 双低模式：基准价 = 最低价×权重 + 平均价×权重

2. **限价设置**
   - 上限价：超出则废标
   - 下限价：低于则废标

3. **评分规则**
   - 可配置满分、上浮扣分系数、下浮扣分系数、最低得分
   - 得分公式：得分 = 满分 - |偏离率| × 扣分系数

4. **报价管理**
   - 支持添加/删除多家投标报价
   - 实时计算并显示有效性和得分排名

### 技术栈

- 前端：HTML + TailwindCSS 3.4（锁定本地）+ Alpine.js 3.14（锁定本地）
- 部署：Docker + nginx 1.28（digest 锁定，amd64/arm64）
