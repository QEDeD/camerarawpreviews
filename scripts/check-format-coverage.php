#!/usr/bin/env php
<?php
// Checks that tests/assets/manifest.json has at least one asset per required format.
// Modes:
//  - KEY_FORMATS=cr2,cr3,nef,arw,dng (comma list): require only these
//  - FULL=1: require all formats from MimeTypeMapping (except 'indd' optional unless INCLUDE_INDD=1)

require __DIR__ . '/../vendor/autoload.php';

use OCA\CameraRawPreviews\AppInfo\MimeTypeMapping;
use OCP\Files\IMimeTypeLoader;

class CapturingLoader implements IMimeTypeLoader {
    public array $captured = [];
    public function updateDatabase($path = null) {}
    public function registerTypeArray(array $arr): void { $this->captured = $arr; }
    public function getMimetype(string $filename): string { return 'application/octet-stream'; }
}

function get_supported_formats(): array {
    $loader = new CapturingLoader();
    $mapping = new MimeTypeMapping();
    $mapping->getMimeTypeMappings($loader);
    return array_keys($loader->captured);
}

function read_manifest_formats(string $path): array {
    if (!is_file($path)) { fwrite(STDERR, "Manifest missing: $path\n"); return []; }
    $j = json_decode(file_get_contents($path), true) ?: [];
    $have = [];
    foreach ($j as $e) {
        $fmt = strtolower($e['format'] ?? '');
        if ($fmt) { $have[$fmt] = true; }
    }
    return array_keys($have);
}

$root = realpath(__DIR__ . '/..');
$manifest = $root . '/tests/assets/manifest.json';
$have = read_manifest_formats($manifest);
$haveSet = array_flip($have);

$full = getenv('FULL') === '1';
$key = getenv('KEY_FORMATS');
if ($full) {
    $req = get_supported_formats();
    if (getenv('INCLUDE_INDD') !== '1') { $req = array_values(array_diff($req, ['indd'])); }
} elseif (!empty($key)) {
    $req = array_filter(array_map('strtolower', array_map('trim', explode(',', $key))));
} else {
    $req = ['cr2','nef','dng'];
}

$missing = [];
foreach ($req as $fmt) { if (!isset($haveSet[$fmt])) { $missing[] = $fmt; } }

$out = [
    'required' => $req,
    'present' => $have,
    'missing' => $missing,
];
echo json_encode($out, JSON_PRETTY_PRINT) . "\n";
if (!empty($missing)) {
    fwrite(STDERR, 'Missing format assets: ' . implode(', ', $missing) . "\n");
    exit(2);
}
exit(0);
