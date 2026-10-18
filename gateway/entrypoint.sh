#!/bin/sh
set -eu
umask 077
sh /opt/lab/bootstrap.sh 
exec /docker-entrypoint.sh "$@" 
