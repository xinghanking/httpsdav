#!/bin/bash
# Source function library.
HTTPSDAV_ROOT=$(readlink -f `dirname "$0"`)
. /etc/rc.d/init.d/functions >/dev/null 2>&1
HTTPD_LANG="C"
# This will prevent initlog from swallowing up a pass-phrase prompt if
# mod_ssl needs a pass-phrase from the user.
INITLOG_ARGS=""
OPTIONS="-C \"ServerRoot $HTTPSDAV_ROOT\" -f $HTTPSDAV_ROOT/conf/httpsdav.conf"
# Path to the apachectl script, server binary, and short-form for messages.
apachectl=/usr/sbin/apachectl
if [[ ! -x $HTTPSDAV_ROOT/bin/httpsdav ]]; then
    rm -fr $HTTPSDAV_ROOT/bin/httpsdav
    ln -s /usr/bin/httpd $HTTPSDAV_ROOT/bin/httpsdav
fi
httpsdav="$HTTPSDAV_ROOT/bin/httpsdav"
prog="httpsdav"
pidfile=${PIDFILE-$HTTPSDAV_ROOT/run/httpsdav.pid}
lockfile=${LOCKFILE-$HTTPSDAV_ROOT/var/subsys/httpsdav}
RETVAL=0
STOP_TIMEOUT=${STOP_TIMEOUT-10}
# The semantics of these two functions differ from the way apachectl does
# things -- attempting to start while running is a failure, and shutdown
# when not running is also a failure.  So we just do it the way init scripts
# are expected to behave here.
start() {
        echo -n $"启动 httpsdav 中: "
        LANG=$HTTPD_LANG daemon --pidfile=${pidfile} $httpsdav $OPTIONS
        RETVAL=$?
        echo
        [ $RETVAL = 0 ] && touch ${lockfile}
        return $RETVAL
}

# When stopping httpd, a delay (of default 10 second) is required
# before SIGKILLing the httpd parent; this gives enough time for the
# httpd parent to SIGKILL any errant children.
stop() {
	echo -n $"关停 $prog 中: "
	killproc -p ${pidfile} -d ${STOP_TIMEOUT} $httpd
	RETVAL=$?
	echo
	[ $RETVAL = 0 ] && rm -f ${lockfile} ${pidfile}
}
reload() {
    echo -n $"重载 $prog: "
    if ! LANG=$HTTPD_LANG $httpsdav $OPTIONS -t >&/dev/null; then
        RETVAL=6
        echo $"not reloading due to configuration syntax error"
        failure $"not reloading $httpsdav due to configuration syntax error"
    else
        # Force LSB behaviour from killproc
        LSB=1 killproc -p ${pidfile} $httpsdav -HUP
        RETVAL=$?
        if [ $RETVAL -eq 7 ]; then
            failure $"httpsdav shutdown"
        fi
    fi
    echo
}

# See how we were called.
case "$1" in
  start)
	start
	;;
  stop)
	stop
	;;
  status)
        status -p ${pidfile} $httpsdav
	RETVAL=$?
	;;
  restart)
	stop
	start
	;;
  condrestart|try-restart)
	if status -p ${pidfile} $httpsdav >&/dev/null; then
		stop
		start
	fi
	;;
  force-reload|reload)
        reload
	;;
  graceful|help|configtest|fullstatus)
	$apachectl $@
	RETVAL=$?
	;;
  *)
	echo $"Usage: $prog {start|stop|restart|condrestart|try-restart|force-reload|reload|status|fullstatus|graceful|help|configtest}"
	RETVAL=2
esac

exit $RETVAL

