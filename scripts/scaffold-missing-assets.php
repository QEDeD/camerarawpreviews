#!/usr/bin/env php
<?php
// Outputs JSON stubs for formats supported by the provider but missing from tests/assets/manifest.json
// Usage: php scripts/scaffold-missing-assets.php > build/missing-assets.template.json

// Keep in sync with RawPreviewBase::$supported
function get_supported_formats(): array {
    return [ 'indd','3fr','arw','cr2','cr3','crw','dng','erf','fff','iiq','kdc','mrw','nef','nrw','orf','ori','pef','raf','rw2','rwl','sr2','srf','srw','tif','tiff','x3f' ];
}

$root = realpath(__DIR__ . '/..');
$manifestPath = $root . '/tests/assets/manifest.json';
$haveFormats = [];
if (is_file($manifestPath)) {
    $data = json_decode(file_get_contents($manifestPath), true) ?: [];
    foreach ($data as $e) {
        $fmt = strtolower($e['format'] ?? '');
        if ($fmt) { $haveFormats[$fmt] = true; }
    }
}

$all = get_supported_formats();
$required = $all; // include INDD

$missing = array_values(array_diff($required, array_keys($haveFormats)));

$stubs = [];
foreach ($missing as $fmt) {
    $filename = 'sample.' . $fmt;
    $stubs[] = [
        'url' => '',
        'filename' => $filename,
        'sha1' => 'auto',
        'format' => $fmt,
        'cameraVendor' => 'Unknown',
        'modelHint' => 'Unknown',
        // Default reasonable per-file cap; adjust per entry if needed
        'size_limit' => 50000000,
        'expectedTag' => null,
        'labels' => ['MISSING_URL']
    ];
}

echo json_encode($stubs, JSON_PRETTY_PRINT) . "\n";
if (empty($stubs)) {
    fwrite(STDERR, "No missing formats; manifest covers all supported formats.\n");
}
exit(0);
