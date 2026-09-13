# 使用官方 nginx 镜像（跨平台支持 ARM 和 X86）
FROM --platform=$BUILDPLATFORM nginx:alpine

# 设置工作目录
WORKDIR /usr/share/nginx/html

# 删除默认页面
RUN rm -rf ./*

# 复制静态文件
COPY index.html .
COPY css/ ./css/
COPY js/ ./js/

# 复制 nginx 配置
COPY nginx.conf /etc/nginx/conf.d/default.conf

# 暴露端口
EXPOSE 80

# 启动 nginx
CMD ["nginx", "-g", "daemon off;"]
