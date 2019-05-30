#!/bin/env sh
PATH="/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin"; cd "$(dirname "$0")"
exec 4>&1; ECHO(){ echo "${@}" >&4; }; exec 3<>"/dev/null"; exec 0<&3;exec 1>&3;exec 2>&3

SRVPNM="poebr-server"

#先行服务停止
for ID in {1..30}; do pkill -f "$SRVPNM" || break; sleep "0.5"; done
[ "$1" == "stop" ] && exit 0

#环境变量未能提供配置数据时从配置文件读取
[ -z "$SRVCFG" ] && SRVCFG="$( jq -scM ".[0]|objects" "./workcfg.json" )"

DINIF="$( echo "$SRVCFG" | jq -r ".pbrsrv.dlinif|strings"  )"
ACTNM="$( echo "$SRVCFG" | jq -r ".pbrsrv.actname|strings" )"
SRVNM="$( echo "$SRVCFG" | jq -r ".pbrsrv.srvname|strings" )"
MAXCN="$( echo "$SRVCFG" | jq -r ".pbrsrv.maxcnct|numbers" )"
PMACN="$( echo "$SRVCFG" | jq -r ".pbrsrv.pmacnct|numbers" )"

DINIF="${DINIF:-eth0}"
ACTNM="${ACTNM:-YN-QJ-MSK-8.MAN.NE42E-$HOSTNAME}"
SRVNM="${SRVNM:-Internet.Dialing.X58CN}"
MAXCN="${MAXCN:-1}"; (( MAXCN < 1 )) && MAXCN=1; (( MAXCN > 1000 )) && MAXCN=1000
PMACN="${PMACN:-0}"; (( PMACN < 0 )) && PMACN=0

WPPPD="$PWD/pbrwatch.sh"
IFPF="pppbr"
FWDB="./fwidalloc.db"
FWTB="fwidalloc"

#初始化转发表ID,结构( lfwid, ufwid, dinst, ctlid, asktm )
rm -rf "$FWDB";
sqlite3 "$FWDB" "
    CREATE TABLE $FWTB(
    lfwid INTEGER  PRIMARY KEY NOT NULL,
    ufwid INTEGER  UNIQUE NOT NULL,
    dinst CHAR(32) UNIQUE,
    ctlid INTEGER  UNIQUE,
    asktm INTEGER );"
for LFWID in $( seq "1000" "$((1000+MAXCN-1))" ); do
    UFWID="$((LFWID+1000))"
    sqlite3 -cmd ".timeout 3000" "$FWDB" \
    "INSERT INTO $FWTB ( lfwid, ufwid ) VALUES( $LFWID, $UFWID );"; done

#连接跟踪阻断,转发放行,TCP-MSS规则, -m state --state UNTRACKED
FWRL=( -i "${IFPF}+" -j NOTRACK )
iptables -t raw -D PREROUTING "${FWRL[@]}"; iptables -t raw -A PREROUTING "${FWRL[@]}"
FWRL=( -i "${IFPF}+" -j ACCEPT )
iptables -t filter -D SRVFWD "${FWRL[@]}"; iptables -t filter -A SRVFWD "${FWRL[@]}"
FWRL=( -o "${IFPF}+" -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu )
iptables -t mangle -D SRVMFW "${FWRL[@]}"; iptables -t mangle -A SRVMFW "${FWRL[@]}"

#启动服务
exec -a "$SRVPNM" pppoe-server -F -I "$DINIF" \
-C "$ACTNM" -S "$SRVNM" -N "$MAXCN" -q "$WPPPD" -x "$PMACN" -r -i -k 

exit 126


#频次限制和拨入禁止
#ebtables -t filter -I INPUT 1 -i eth0 -d Broadcast \
#-p PPP_DISC --limit 1/second --limit-burst 1 -j ACCEPT
#ebtables -t filter -I INPUT 2 -i eth0 -d Broadcast \
#-p PPP_DISC -j DROP

