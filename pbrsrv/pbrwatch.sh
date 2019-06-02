#!/bin/env sh
PATH="/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin"
cd "$(dirname "$0")"; exec 3<>"/dev/null"; exec 0<&3;exec 1>&3;exec 2>&3

# 注意: 由pppoe-server启动的pppd进程需要继承已打开的"文件描述符4"
# 注意: pppd-wrap类程序对"文件描述符4"的修改将导致"pppd-wrap"进程被终止

#控制器ID和接口前缀
CTLID="$$"; IPRF="pppbr"; PBRNM="$HOSTNAME"

#生成用户拨入实例ID
read -t 1 INST < "/proc/sys/kernel/random/uuid" || INST="$(uuidgen)"
INST="$( echo "$INST" | tr "[a-z-]" "[A-Z\0]" )"; INST="${INST:15:16}"
DINST="$INST"

#转发表ID申请和释放过程
FWDB="./fwidalloc.db"; FWTB="fwidalloc"; LFWID=""; UFWID=""
FWID_GET() {
    #释放已分配资源
    [ "$1" == "release" ] && { sqlite3 -cmd ".timeout 3000" "$FWDB" "UPDATE $FWTB SET
    dinst=NULL,ctlid=NULL,asktm=NULL WHERE dinst==\"$DINST\" AND ctlid==$CTLID;"; return; }
    #资源分配异常测试: 撤销超过90秒且对应实例控制进程已消亡的申请记录
    local ID=""; local LPNM=""; local UPNM=""; for ID in \
    $( exec sqlite3 -cmd ".timeout 3000" "$FWDB" "SELECT lfwid,dinst FROM $FWTB \
    WHERE dinst IS NOT NULL AND strftime(\"%s\")-(asktm+90)>0;" ); do
    LPNM="pppd-line-${ID##*|}-${ID%%|*}"; UPNM="pppd-user-${ID##*|}-$PBRNM"
    pidof "$LPNM" && pidof "$UPNM" && continue
    pkill -f "$LPNM" || ( sleep 10; pkill -f "$UPNM" )&
    sqlite3 -cmd ".timeout 3000" "$FWDB" \
    "UPDATE $FWTB SET dinst=NULL,ctlid=NULL,asktm=NULL WHERE lfwid==\"${ID%%|*}\";"; done
    #尝试为当前实例分配转发表ID
    ID="$( exec sqlite3 -cmd ".timeout 3000" "$FWDB" "BEGIN;
    UPDATE $FWTB SET dinst=\"$DINST\",ctlid=$CTLID,asktm=strftime(\"%s\")
    WHERE lfwid==(SELECT lfwid FROM $FWTB WHERE dinst IS NULL ORDER BY RANDOM() LIMIT 1);
    SELECT lfwid,ufwid FROM $FWTB WHERE dinst==\"$DINST\" AND ctlid==$CTLID; COMMIT;" )"
    #分离申请的线路和用户转发表ID
    LFWID="${ID%%|*}"; UFWID="${ID##*|}"; }
    
#转发表ID申请
FWID_GET; [[ -n "$LFWID" && -n "$UFWID" ]] || exit 1 

#管道消息接收和发送过程,消息空窗期间可用作延时阻塞
MSGPF="./MSGPIPE.$LFWID"; rm -rf "$MSGPF"*
MSGPF="$MSGPF.$DINST"; MSGLN=(); MSGFD=""
MSG_DELAY() {
    [ -p "$MSGPF" ] || { rm -rf "$MSGPF"; mkfifo "$MSGPF"; }
    [[ "$1" =~ ^"CLOSE"|"CLEAN"$ ]] && { exec 98<&-; MSGFD=""
    [ "$1" == "CLEAN" ] && rm -rf "$MSGPF"; return; }
    [ -z "$MSGFD" ] && { exec 98<>"$MSGPF" && MSGFD=98; }
    [ -z "$MSGFD" ] && return; [ "$1" == "SEND"  ] && { 
    flock -x -w 5 98; echo "${@:2}" >&98; flock -u 98; return; }
    MSGLN=(); [ "$1" == "INIT" ] && return
    read -t "$1" -u 98 MSGLN[0]; MSGLN=( ${MSGLN[0]} ); }
#消息管道初始化
MSG_DELAY INIT

#资源清理及延时终止
CLEAN_AND_EXIT() {
    MSG_DELAY CLEAN; FWID_GET "release"; pkill -f "$USPNM"; pkill -f "$LNPNM"
    wait; exec -a "PBRWATCH-Delay-To-Exit-$DINST-$HOSTNAME" sleep "3"; }

#线路拨号名称,物理接口
LNPNM="pppd-line-$DINST-$LFWID"
LIFNM="${IPRF}line$LFWID"
DFEXT="eth1"

#用户连接及会话参数
ARGS=( $2 )
SRVNM="${ARGS[7]#\'}"; SRVNM="${SRVNM%\'}"
DLIIF="${ARGS[3]}"
USESS="${ARGS[5]}"
USPNM="pppd-user-$DINST-$PBRNM"
UIFNM="${IPRF}user$LFWID"
ATHPT="./accountck.sh"

#接入时间,文件路径
DLSTM="$( date "+%F/%T/%Z" )"
IPSCR="./ipcpscript.sh"
STDTF="LOGSTAT.$LFWID"; rm -rf "$STDTF"*; STDTF="$STDTF.$DINST"
exec 99>"$STDTF"; ECHO(){ echo "${@}" >&99; }

#等待历史实例结束
for ID in {1..30}; do
pkill -f "$LNPNM" || pkill -f "$USPNM" || break; MSG_DELAY "0.3"; done

#环境变量未能提供配置数据时从配置文件读取
[ -z "$SRVCFG" ] && SRVCFG="$( jq -scM ".[0]|objects" "./workcfg.json" )"
LNOIF="$( echo "$SRVCFG" | jq -r ".pbrsrv.lndlif|strings" )"
LNDNM="$( echo "$SRVCFG" | jq -r ".pbrsrv.lnuser|strings" )"
LNDPW="$( echo "$SRVCFG" | jq -r ".pbrsrv.lnpswd|strings" )"
ETCDS="$( echo "$SRVCFG" | jq -r ".pbrsrv.etcdnm|strings" )"
LNOIF="${LNOIF:-$DFEXT}"; ETCDS="${ETCDS:-http://etcdser:2379}"

#连接信息,单行JSON串传入PPPD(jq命令不支持字符串内包含换行符)
IPPM="{ \"lfwid\": \"$LFWID\", \"ufwid\": \"$UFWID\",
        \"dinst\": \"$DINST\", \"msgpf\": \"$MSGPF\", \"etcds\": \"$ETCDS\" }"
IPPM="$( echo "$IPPM" | jq -cM "." )"

#初始化线路状态,启动线路拨号
( MSG_DELAY 0.3; MSG_DELAY CLOSE; exec -a "$LNPNM" pppd ifname "$LIFNM" \
  lock nodetach maxfail 2 lcp-echo-failure 4 lcp-echo-interval 5 \
  noauth refuse-eap nomppe user "$LNDNM" password "$LNDPW" mtu 1492 mru 1492 \
  ip-up-script "$PWD/$IPSCR" ip-down-script "$PWD/$IPSCR" usepeerdns \
  nolog ipparam "LINE$IPPM" plugin "rp-pppoe.so" "$LNOIF"; )&

#等待线路拨号成功后继续,超时或失败终止本次拨入
ECHO "Waiting Line Startup.."
for ID in {1..60}; do MSG_DELAY "0.4"; [ "${MSGLN[0]}" == "LINEUP" ] && break
    pidof "$LNPNM" && (( ID < 60 )) && continue; CLEAN_AND_EXIT; done

#验证消息源,提取线路参数,在此为拨入连接互换"本地-对端"地址参数
[ "${MSGLN[1]}" == "$DINST" ] || {
    ECHO "Message Source Error, exit. ($DINST)"; CLEAN_AND_EXIT; }
IPLC="${MSGLN[3]}"; IPRM="${MSGLN[2]}"; SMAC="${MSGLN[4]}"
DNS1="${MSGLN[5]}"; DNS2="${MSGLN[6]}"; ECHO "${MSGLN[@]}"

#启动拨入连接,使用本地认证插件
#使用子程序执行用户pppd以规避用户主动离线无法触发用户pppd的离线脚本执行的问题
#初步判断是接入服务程序收到PADT包后触发的子进程SIGTERM信号会导致处于ppp会话终
#止阶段的PPPD直接终止从而跳过IPCP终止脚本执行
( MSG_DELAY 0.3; MSG_DELAY CLOSE; exec -a "$USPNM" pppd ifname "$UIFNM" nolog \
  lock nodetach lcp-echo-failure 4 lcp-echo-interval 5 noaccomp nopcomp \
  default-asyncmap mru 1492 mtu 1492 auth refuse-eap refuse-pap chap-interval 600 \
  ms-dns "$DNS1" ms-dns "$DNS2" "$IPLC:$IPRM" ipparam "USER$IPPM" \
  ip-up-script "$PWD/$IPSCR" ip-down-script "$PWD/$IPSCR" \
  plugin "expandpwd.so" pwdprovider "$PWD/$ATHPT" \
  plugin "rp-pppoe.so" "$DLIIF" rp_pppoe_sess "$USESS" rp_pppoe_service "$SRVNM" )&

#终止类信号处理: 启动终止计数器,关闭状态检测及推送指示
SET_TO_EXIT() { TMSP=1; DLTM="$DLQK"; PUSH=""; LUST=""; TMSIG="NO"; }
TERM_SIG_RCV() { [ -z "$TMSIG" ] && { SET_TO_EXIT; TMSIG="YES"; MSG_DELAY SEND; }; }
trap "TERM_SIG_RCV" SIGQUIT SIGTERM

#为etcdctl启用AIPv3支持: export ETCDCTL_API="3"

#守护期周期性执行连接状态检测及注册TTL刷新
#指示消息: MSGLN=() "LU-UD $DINST $IPLC $IPRM $RMAC $DNS1/PNM $DNS2 $CNTM $BRCV $BSNT"
DLTM=15; DLQK=0.5; RCNT=20; TMSP=0
STKET=""; PUSH=""; LUST="CK"; FLCS=""; TMSIG=""; LOGDT=""
while (( RCNT > 0 )); do
    (( RCNT-=TMSP )); MSG_DELAY "$DLTM"
    
    #线路控制进程测试
    [ "$LUST" == "CK" ] && { pidof "$LNPNM" || LUST="LF"; }
    [ "$LUST" == "LF" ] && { SET_TO_EXIT; FLCS="${FLCS:-LineTerminated}"; pkill -f "$USPNM"; }
    
    #用户控制进程测试
    [ "$LUST" == "CK" ] && { pidof "$USPNM" || LUST="UF"; }
    [ "$LUST" == "UF" ] && { SET_TO_EXIT; FLCS="${FLCS:-UserTerminated}"; pkill -f "$LNPNM"; }
    
    #TREM类信号延迟超时测试
    (( RCNT == 8 )) && [ "$TMSIG" == "YES" ] && {
        FLCS="${FLCS:-TunnelClosed}"; LUST="TC"; pkill -SIGHUP -f "$USPNM"; }
    
    #常规周期(空消息)条件执行状态注册,首次推送或过期续期为实时监视使用SET操作
    [[ -z "${MSGLN[0]}" && -n "$PUSH" ]] && { [ "$PUSH" == "U" ] && \
        etcdctl --endpoints "$ETCDS" update --ttl "20" "/pbrsrvst/$STKET" "$LOGDT" || \
        etcdctl --endpoints "$ETCDS" set --ttl "20" "/pbrsrvst/$STKET" "$LOGDT"; PUSH="U"; }
    
    #消息源验证失败(包括常规周期事件)时忽略当前事件消息
    [ "${MSGLN[1]}" == "$DINST" ] || continue
    
    #收到线路失败消息时置位线路失败标记并预置一次立即状态检测
    [ "${MSGLN[0]}" == "LINEDW" ] && (( TMSP == 0 )) && { LUST="LF"; MSG_DELAY SEND; continue; }
    
    #用户连接事件: 配置状态数据和状态注册指示
    [[ "${MSGLN[0]}" =~ ^"USERUP"|"USERDW"$ && -n "${MSGLN[5]}" ]] && {
        #用户上线: 设置用户状态并预置一次立即状态注册
        [ "${MSGLN[0]}" == "USERUP" ] && {
            UDSTAT="Activated"; PUSH="S"; LOGDT=""
            STKET="${MSGLN[5]}-${MSGLN[3]}-$DINST"; MSG_DELAY SEND; }
        #用户离线: 置位停止标记,为日志附加统计数据
        [ "${MSGLN[0]}" == "USERDW" ] && {
            RCNT=0; FLCS="${FLCS:-UserTerminated}"; UDSTAT="$FLCS"
            LOGDT=",\"cntime\": ${MSGLN[7]},\"upflow\": ${MSGLN[8]},\"dwflow\": ${MSGLN[9]}"; }
        #格式化日志数据
        LOGDT="{ \"lacmac\": \"$SMAC\", \"ustmac\": \"${MSGLN[4]}\",
                 \"gwaddr\": \"${MSGLN[2]}\", \"usaddr\": \"${MSGLN[3]}\",
                 \"sgdns1\": \"$DNS1\", \"sgdns2\": \"$DNS2\",
                 \"lndlnm\": \"$LNDNM\", \"usname\": \"${MSGLN[5]}\",
                 \"udstat\": \"$UDSTAT\", \"uptime\": \"$DLSTM\",
                 \"instid\": \"$DINST\", \"pbrcnm\": \"$PBRNM\" $LOGDT }"
        LOGDT="$( echo "$LOGDT" | jq -M "." )"; ECHO "$LOGDT"; }
    #离线日志更新,状态注销
    (( RCNT == 0 )) && {
        etcdctl --endpoints "$ETCDS" set -ttl 1209600 "/pbrsrvlog/${MSGLN[5]}/$DINST" "$LOGDT"
        etcdctl --endpoints "$ETCDS" set -ttl 1 "/pbrsrvst/$STKET" "$LOGDT"; }
    done

CLEAN_AND_EXIT; exit 126

