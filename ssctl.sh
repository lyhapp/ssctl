#!/bin/bash
#Author:Driver_C
#Blog:http://chenjingyu.cn

VERSION=1.0.1

helpmsg() {
	echo "Version $VERSION"
	echo 'usage: ssctl.sh [OPTION]...'
	echo
	echo 'Options:'
	echo '  server       Ssserver contral'
	echo '      start        Start ssserver by /etc/shadowsocks.json'
	echo '      stop         Stop ssserver'
	echo '      restart      Restart ssserver'
	echo '  addport      Usage:addport <PORT> <data> [description] Add a new port for user'
	echo '  delport      Usage:delport <PORT> Delete port'
	echo '  drop         Iptables contral'
	echo '      add          Useage:add <PORT> Add port to iptables DROP list'
	echo '      del          Useage:del <PORT|all> Delete a port from iptables DROP list or delete all'
	echo
	confex
}

confex() {
	echo '#####The configuration file format example#####'
	echo 'Configuration file path /etc/shadowsocks.json' 
	echo '{'
	echo '    "server":"0.0.0.0",'
	echo '    "local_address":"127.0.0.1",'
	echo '    "local_port":1080,'
	echo '    "port_password":{'
	echo '        "10001":"password1",'
	echo '        "10002":"password2",'
	echo '        "10003":"password3"'
	echo '    },'
	echo '    "timeout":300,'
	echo '    "method":"aes-256-cfb",'
	echo '    "fast_open": false,'
	echo '    "workers":3'
	echo '}'
	echo
}

confcheck() {
	CONF=`grep 'port_password' /etc/shadowsocks.json`
	if [ -z "$CONF" ];then
		echo
		echo '#####Error in configuration file format#####'
		echo '#####   Please refer to the example    #####'
		echo 'Configuration file path /etc/shadowsocks.json' 
		echo 
		confex
		exit
	fi
}

croncheck() {
	CRONROOT=/var/spool/cron/root
	DIR=`cd "$(dirname "$0")";pwd`
	NAME=`basename $0`
	PWDPATH="$DIR/$NAME"
	CHECK=`grep "$PWDPATH check" $CRONROOT`
	CLEAN1=`grep "$PWDPATH drop del all" $CRONROOT`
	CLEAN2=`grep 'iptables -Z' $CRONROOT`
	[ -z "$CHECK" ] && echo "* * * * * /bin/bash $PWDPATH check &> /dev/null" >> $CRONROOT
	[ -z "$CLEAN1" ] && echo "10 0 1 * * /bin/bash $PWDPATH drop del all &> /dev/null" >> $CRONROOT
	[ -z "$CLEAN2" ] && echo "0 0 1 * * iptables -Z &> /dev/null" >> $CRONROOT
}

server() {
	case $1 in
	start)
    	ssserver --user nobody -c /etc/shadowsocks.json -d start
    	;;
	stop)
    	ssserver -d stop
    	;;
	restart)
    	ssserver -d stop
	for i in {1..20};do
		echo -n '='
    		sleep 0.1
	done
	echo
    	ssserver --user nobody -c /etc/shadowsocks.json -d start
    	;;
	*)
	helpmsg
		;;
	esac
}

addport() {
	[[ ! $1 =~ [0-9]+ ]] && echo 'Port wrong' && exit
	[[ ! $2 =~ [0-9]+ ]] && echo 'Data wrong' && exit
	PORT=`grep $1 /etc/shadowsocks.json`
	[ -n "$PORT" ] && echo 'This port already exists' && exit
	PASSWD=`cat /dev/urandom | tr -dc '0-9a-zA-Z' | head -c 20`
	iptables -A OUTPUT -p tcp --sport $1
	sed -ri "/port_password/a\        \"$1\"\:\"$PASSWD\"," /etc/shadowsocks.json
	WORKERS=`grep -E '"[0-9]+":"[[:alnum:]_]+"' /etc/shadowsocks.json | wc -l`
	sed -ri "s/(.*workers\":).*/\1$WORKERS/" /etc/shadowsocks.json
	echo "$1 $2 $3" >> /etc/ssuser.conf
	server restart
	echo "Port:$1 Password:$PASSWD"
}

delport() {
	[[ ! $1 =~ [0-9]+ ]] && echo 'Port wrong' && exit
	NUM=`iptables -vnL OUTPUT --line-numbers | grep "spt:$1" | awk '{print $1}'`
	[ -z $NUM ] && echo 'Can not find this port' && exit
	iptables -D OUTPUT $NUM
	sed -ri "/$1/d" /etc/shadowsocks.json
	WORKERS=`grep -E '"[0-9]+":"[[:alnum:]_]+"' /etc/shadowsocks.json | wc -l`
	sed -ri "s/(.*workers\":).*/\1$WORKERS/" /etc/shadowsocks.json
	sed -ri "/$1/d" /etc/ssuser.conf
	server restart
	echo "Delete $1 successd"
}

drop() {
	case $1 in
	del)
		if [ "$2" = "all" ];then
			DROPNUM=`iptables -vnL INPUT --line-numbers | grep "DROP" | grep -E 'dpt:[0-9]+' | awk '{print $1}'`
			for i in $DROPNUM;do
				NUM=`iptables -vnL INPUT --line-numbers | grep "DROP" | grep -E 'dpt:[0-9]+' | head -n1 | awk '{print $1}'`
				iptables -D INPUT $NUM
			done
		else
			[[ ! $2 =~ [0-9]+ ]] && echo 'Port wrong' && exit
			DROP=`iptables -vnL INPUT --line-numbers | grep "dpt:$2" | awk '{print $1}'`
			iptables -D INPUT $DROP
		fi
		;;
	add)
		[[ ! $2 =~ [0-9]+ ]] && echo 'Port wrong' && exit
		iptables -A INPUT -p tcp --dport $2 -j DROP
		;;
	*)
	helpmsg
		;;
	esac
}

check() {
	PORT=`awk '{print $1}' /etc/ssuser.conf`
	for i in $PORT;do
		DATACONF=`grep "$i" /etc/ssuser.conf | awk '{print $2}'`
		DATANUM=$[${DATACONF}*1024*1024*1024]
		DATANOW=`iptables -vnL OUTPUT -x | grep "spt:$i" | awk '{print $2}'`
		if [ $DATANOW -gt $DATANUM ];then
			drop add $i
		fi
	done
}

main() {
	case $1 in
	addport)
		confcheck
		croncheck
		addport $2 $3 $4
	;;
	delport)
		confcheck
		croncheck
		delport $2
	;;
	drop)
		confcheck
		croncheck
		drop $2 $3
	;;
	server)
		confcheck
		croncheck
		server $2
	;;
	check)
		check
	;;
	*)
	helpmsg
	;;
	esac
}

main $1 $2 $3 $4
