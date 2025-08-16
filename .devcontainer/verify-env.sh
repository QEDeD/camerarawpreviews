#!/usr/bin/env bash
set -euo pipefail
missing=0

php -v | head -n1
echo "PHP extensions present:" $(php -m | grep -E '^(gd|zip|imagick)$' | tr '\n' ' ')
php -m | grep -q '^gd$' || { echo 'gd extension missing'; missing=1; }
php -m | grep -q '^zip$' || { echo 'zip extension missing'; missing=1; }
php -m | grep -q '^imagick$' || { echo 'imagick extension missing'; missing=1; }
command -v convert >/dev/null || { echo 'ImageMagick convert missing'; missing=1; }
if [ "${missing:-0}" = 1 ]; then
	echo 'Env verification FAILED';
	exit 1;
fi
command -v composer >/dev/null || { echo 'Composer missing'; exit 1; }
command -v make >/dev/null || { echo 'Make missing'; exit 1; }

echo 'All core dev prerequisites present.'
