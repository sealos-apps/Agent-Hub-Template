#!/usr/bin/env bash
set -euo pipefail

UTMP_GROUP=utmp
if ! getent group "$UTMP_GROUP" >/dev/null 2>&1; then
	UTMP_GROUP=root
fi

if [ ! -e /run/utmp ]; then
	: > /run/utmp
fi
chmod 664 /run/utmp
chown root:"$UTMP_GROUP" /run/utmp
