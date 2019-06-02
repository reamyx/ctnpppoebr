#!/bin/env sh
PATH="/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin"; cd "$(dirname "$0")"

IMGNM="ctnpppoebr" BASE="imginit"

#从参数或环境变量确定仓库路径
PUSH="$1" PUSH="${PUSH:-$PSPATH}"
IMGNMPL="${PUSH:+$PUSH/}$IMGNM" BASEPL="${PUSH:+$PUSH/}$BASE"

#获取基础镜像
[ -n "$BASE" ] && {
    docker pull "$BASEPL" && docker tag "$BASEPL" "$BASE"
    (( "$(docker image list "$BASE" | wc -l)" < 2 )) && \
    { echo "依赖镜像[ $BASE ]检查失败,构建终止."; exit; }; }

#构建,远程推送
docker build -t "$IMGNM" ./ && echo "构建镜像[ $IMGNM ]完成." && \
[ -n "$PUSH" ] && docker tag "$IMGNM" "$IMGNMPL" && \
docker push "$IMGNMPL" && echo "推送镜像[ $IMGNMPL ]完成." && \
docker image remove "$IMGNMPL"

exit 0
