#!/bin/env sh
PATH="/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin"
cd "$(dirname "$0")"

#"LINEUP","LINEDW","USERUP","USERDW"分别指示线路和用户连接的启停
LU="${6::4}"; IPPM="${6:4}"; UD="${CONNECT_TIME:+DW}"; UD="${UD:-UP}"

#分离线路对接参数
LFWID="$( echo "$IPPM" | jq -r ".lfwid|strings" )"
UFWID="$( echo "$IPPM" | jq -r ".ufwid|strings" )"
DINST="$( echo "$IPPM" | jq -r ".dinst|strings" )"
MSGPF="$( echo "$IPPM" | jq -r ".msgpf|strings" )"
[[ -z "$LFWID" || -z "$UFWID" || -z "$DINST" || -z "$MSGPF"  ]] && exit 1

#基本消息数据
EVTMSG="$LU$UD $DINST $IPLOCAL $IPREMOTE $MACREMOTE"

#区别连接类型配置目标参数及附加消息数据
[ "$LU" == "LINE" ] && {
    FWID="$LFWID"; RTID="$UFWID"; ATTACH="${DNS1:-223.5.5.5} ${DNS2:-114.114.114.114}"; }
[ "$LU" == "USER" ] && {
    FWID="$UFWID"; RTID="$LFWID"; ATTACH="$PEERNAME ZW01"; }

#复位转发规则及路由表
ip rule list iif "$IFNAME" | while read; do ip rule del iif "$IFNAME"; done
ip route flush table "$RTID"

#连接UP: 清除地址及添加转发规则, 连接DOWN: 收集统计数据
[ "$UD" == "UP" ] && {
    COUNT=""; ip addr del "$IPLOCAL" dev "$IFNAME"
    ip rule add iif "$IFNAME" pref "$FWID" lookup "$FWID"
    ip route add default dev "$IFNAME" table "$RTID"; }
[ "$UD" == "DW" ] && COUNT="$CONNECT_TIME $BYTES_RCVD $BYTES_SENT"

#发送事件消息
[ -p "$MSGPF" ] && exec 10<>"$MSGPF" && \
flock -x -w 15 10 && echo "$EVTMSG $ATTACH $COUNT" >&10; exec 10<&-

exit 0

#环境变量
#  MACREMOTE=AC:4E:91:41:AD:98  [ PPPOE插件拨号时 ]
#  IFNAME=ppp120
#  CONNECT_TIME=23              [ 仅接口DOWN时可用 ]
#  IPLOCAL=192.168.16.20
#  PPPLOGNAME=root
#  BYTES_RCVD=43416             [ 仅接口DOWN时可用 ]
#  ORIG_UID=0
#  SPEED=115200
#  BYTES_SENT=73536             [ 仅接口DOWN时可用 ]
#  IPREMOTE=192.168.16.40
#  PPPD_PID=21420
#  PWD=/
#  PEERNAME=zxkt
#  DEVICE=/dev/pts/1
