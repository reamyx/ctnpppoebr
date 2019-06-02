#!/bin/env sh
PATH="/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin"; cd "$(dirname "$0")"
exec 4>&1; ECHO(){ echo "${@}" >&4; }; exec 3<>"/dev/null"; exec 0<&3;exec 1>&3;exec 2>&3

#本程序执行其它服务程序委托的账号检查及密码查询工作
#参数$1为JSON格式字符串,用于提供用户认证相关参数,具体内容及表义取决于调用程序
#标准输出首行提供密码,次行输出可选的描述信息
#输出字串中的'\0'被视作换行符'\n'处理,非0状态码指示认证失败

#PPPD程序(expandpwd插件)和SOCKD服务调用参数解释:
# { "method": "CHAP", "usercnm": "abc000", "usercpw": "xxx", "ipparm": "xxx",
#   "srvpid": "2233", "srvname": "PPTP", "asessid": "0FA5A89B7E", ... }
#属性解释:
#  method    认证方法: "PAP", "CHAP", "SKDPW"
#  usercnm   对端认证名称
#  usercpw   提交密码明文,仅PAP方法时适用
#  ipparm    pppd程序之ipparm选项值(仅PPPD)
#  srvpid    服务主进程PID
#  asessid   认证关联的会话ID
#  srvname   服务名称

#用户名称
UNM="$( echo "$1" | jq -rcM ".usercnm|strings" )"

#测试数据
[ "$UNM" == "vtest" ] && { ECHO "2019"; ECHO "vtest-2019-ok"; exit 0; }

#从IPPARM参数提取ETCD服务器URL和实例ID
IPPARM="$( echo "$1" | jq -rcM ".ipparm|strings" )"; IPPARM="${IPPARM:4}"
ETCDNM="$( echo "$IPPARM" | jq -r ".etcds|strings" )"
INST="$( echo "$IPPARM" | jq -r ".dinst|strings" )"
[[ -z "$ETCDNM" || -z "$INST" ]] && { ECHO "Necessary Parameter Absence."; exit 1; }

#etcd账户目录: "/pbrsrvauth/* KEY:名称,VAL: '{"passwd":"abc000","limit":2,"expire":""}'

#查寻用户信息
UPM="$( etcdctl --endpoints "$ETCDNM" get "/pbrsrvauth/$UNM" )"
[ -z "$UPM" ] && { ECHO "Specified User Account Does Not Exist."; exit 2; }

#账户过期检查
USEXP="$( echo "$UPM" | jq -r ".expire|strings" | tr "/" " " )"
[ -n "$USEXP" ] && (( "$( date -d "$USEXP" "+%s" )" < "$( date "+%s" )" )) && {
    ECHO "Specified User Account Expired."; exit 3; }

#并发数检查: 名称-地址-实例ID
USLMT="$( echo "$UPM" | jq -r ".limit|numbers" )"; USLMT="${USLMT:-1}"
(( USLMT > 0 )) && {
    OLCNT="$( etcdctl --endpoints "$ETCDNM" ls -p "/pbrsrvst" | awk -v nk="$INST" -v nm="$UNM" \
    'BEGIN{i=0};{gsub(".*/","",$1)};$1~"^"nm"-.+-.*"{if($1!~nk"$")i++};END{print i}' )"
    (( OLCNT >= USLMT )) && { ECHO "Reached Nnumber Of Connections Limit."; exit 4; }; }

#密码提取和响应
UPW="$( echo "$UPM" | jq -r ".passwd|strings" )"
ECHO "$UPW"; ECHO "Welcome to use, Powered by Zhixia(reamyx@126.com)."; exit 0

