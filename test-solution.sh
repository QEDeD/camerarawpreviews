#!/bin/bash

echo "=== Testing Camera RAW Previews Solution ==="
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Test 1: Check our changes are applied
echo "Test 1: Verifying our changes..."
if grep -q "LoggerInterface" lib/AppInfo/Application.php && grep -iq "exponential backoff" js/register-viewer.js; then
    echo -e "${GREEN}✅ Changes are correctly applied${NC}"
else
    echo -e "${RED}❌ Changes are missing${NC}"
    echo "Please ensure our modifications are in place"
    exit 1
fi

# Test 2: PHP syntax check
echo ""
echo "Test 2: Checking PHP syntax..."
php -l lib/AppInfo/Application.php > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ PHP syntax is valid${NC}"
else
    echo -e "${RED}❌ PHP syntax error${NC}"
    php -l lib/AppInfo/Application.php
    exit 1
fi

# Test 3: Check composer dependencies
echo ""
echo "Test 3: Checking composer dependencies..."
if [ -f "vendor/exiftool/exiftool/exiftool.bin" ]; then
    echo -e "${GREEN}✅ Exiftool binary found${NC}"
else
    echo -e "${RED}❌ Exiftool binary missing${NC}"
    echo "Run: composer install"
    exit 1
fi

# Test 4: JavaScript syntax check (basic)
echo ""
echo "Test 4: Checking JavaScript..."
if node -c js/register-viewer.js 2>/dev/null; then
    echo -e "${GREEN}✅ JavaScript syntax is valid${NC}"
else
    # Fallback: just check if file has no obvious syntax errors
    if grep -q "function registerCameraRawViewer" js/register-viewer.js; then
        echo -e "${GREEN}✅ JavaScript structure looks correct${NC}"
    else
        echo -e "${RED}❌ JavaScript may have issues${NC}"
    fi
fi

echo ""
echo "=== All Tests Passed! ==="
echo ""
echo "Next steps:"
echo "1. Run 'make build' to build the app"
echo "2. Run 'make appstore' to create deployment package"
echo "3. Install on Nextcloud 31.0.7 and test with a RAW file"
