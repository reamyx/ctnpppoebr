#!/bin/env sh
PATH="/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin"; cd "$(dirname "$0")"

IMGNM="pbrsrv" BASE="imginit"

#从参数或环境变量确定仓库路径
PUSH="$1" PUSH="${PUSH:-$PSPATH}"
IMGNM="${PUSH:+$PUSH/}$IMGNM" BASEPL="${PUSH:+$PUSH/}$BASE"

#获取基础镜像
[ -n "$BASE" ] && docker pull "$BASEPL" && \
docker tag "$BASEPL" "$BASE" || { echo "依赖镜像[ $BASE ]拉取失败,构建终止."; exit; }

#构建
docker build -t "$IMGNM" ./ && echo "构建镜像[ $IMGNM ]完成."

#推送
[ -n "$PUSH" ] && docker push "$IMGNM" && echo "推送镜像[ $IMGNM ]完成."



exit 0
