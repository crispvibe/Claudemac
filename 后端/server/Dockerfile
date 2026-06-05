FROM golang:alpine as builder

WORKDIR /app/server
COPY . .

RUN go env -w GO111MODULE=on \
    && go env -w GOPROXY=https://goproxy.cn,direct \
    && go env -w CGO_ENABLED=0 \
    && go env \
    && go mod tidy \
    && go build -o server .

FROM alpine:latest

# 设置时区
ENV TZ=Asia/Shanghai
RUN apk update && apk add --no-cache tzdata openntpd \
    && ln -sf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

WORKDIR /app/server

COPY --from=0 /app/server/server ./
COPY --from=0 /app/server/resource ./resource/
COPY --from=0 /app/server/config.docker.yaml ./

# 挂载目录：如果使用了sqlite数据库，可将数据库文件挂载到 /app/server 目录
# VOLUME ["/app/server"]

EXPOSE 8888
ENTRYPOINT ./server -c config.docker.yaml
