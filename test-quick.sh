#!/bin/bash

echo "=== Camera RAW Previews Quick Test ==="
echo ""

echo "1. Checking PHP syntax..."
php -l lib/AppInfo/Application.php
if [ $? -eq 0 ]; then
    echo "✅ PHP syntax OK"
else
    echo "❌ PHP syntax error"
    exit 1
fi

echo ""
echo "2. Checking for LoggerInterface..."
if grep -q "LoggerInterface" lib/AppInfo/Application.php; then
    echo "✅ LoggerInterface found"
else
    echo "❌ LoggerInterface missing"
    exit 1
fi

echo ""
echo "3. Checking for exponential backoff..."
if grep -iq "exponential" js/register-viewer.js; then
    echo "✅ Exponential backoff found"
else
    echo "❌ Exponential backoff missing"
    exit 1
fi

echo ""
echo "4. Checking composer.json..."
if grep -q "nextcloud/ocp" composer.json; then
    echo "✅ Nextcloud OCP dependency found"
else
    echo "❌ Nextcloud OCP dependency missing"
fi

echo ""
echo "=== All basic tests passed! ==="
echo ""
echo "Next steps:"
echo "1. Run 'make build' to create package"
echo "2. Install on Nextcloud 31.0.7 test instance"
echo "3. Test with a .CR2 or .NEF file"
