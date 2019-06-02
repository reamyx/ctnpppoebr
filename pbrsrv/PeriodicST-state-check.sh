#!/bin/env sh
PATH="/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin" 
cd "$(dirname "$0")"


SRVPNM="poebr-server"

#服务状态测试过程,返回测试状态
pidof "$SRVPNM" > "/dev/null"
