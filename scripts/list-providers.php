<?php
@ini_set('memory_limit','512M');
// Locate Nextcloud base.php flexibly: either sibling 'nextcloud' (dev core checkout) or installed root (container)
$candidates = [
    __DIR__ . '/../nextcloud/lib/base.php',                                  // local core checkout
    __DIR__ . '/../../lib/base.php',                                        // mounted inside container (custom_apps/app/scripts -> ../../lib)
    __DIR__ . '/../../../lib/base.php',                                     // defensive extra level
];
$baseFound = null;
foreach ($candidates as $c) { if (is_file($c)) { $baseFound = $c; break; } }
if (!$baseFound) { fwrite(STDERR, "Unable to locate Nextcloud base.php (checked: " . implode(',', $candidates) . ")\n"); exit(3); }
require $baseFound;
require __DIR__ . '/../vendor/autoload.php';

use OCP\Preview\IPreview;
use OCP\Files\Node;
use Psr\Log\LoggerInterface;

// Allow selecting an asset via environment variable (default to 3FR)
$envAsset = getenv('ASSET') ?: '';
$assetRel = $envAsset !== '' ? $envAsset : 'tests/assets/cache/hasselblad_cf132.3FR'; // target asset to probe selection
fwrite(STDERR, "Starting provider listing...\n");
$asset = __DIR__ . '/../' . $assetRel;
if (!file_exists($asset)) { fwrite(STDERR, "Asset not found: $assetRel\n"); exit(2);} 
$server = \OC::$server;
fwrite(STDERR, "Server container acquired.\n");
// Ensure apps loaded (may register preview providers)
if (class_exists('OC_App')) { \OC_App::loadApps(); }
$rootFolder = $server->getRootFolder();
$logger = $server->get(LoggerInterface::class);
$userFolder = $server->getUserFolder('admin');
$contents = file_get_contents($asset);
$file = $userFolder->newFile('prov_3fr_' . uniqid() . '.3FR', $contents);

// Acquire preview manager robustly
$previewManager = null; $pmError = null;
try {
    fwrite(STDERR, "Attempting primary IPreview acquisition...\n");
    $previewManager = $server->get(IPreview::class);
} catch (\Throwable $e) {
    $pmError = 'IPreview get() failed: ' . $e->getMessage();
}
if ($previewManager === null) {
    foreach (['OC\\PreviewManager','\\OC\\PreviewManager','OCP\\Preview\\PreviewManager'] as $cand) {
        if (!class_exists($cand)) { continue; }
        try {
            fwrite(STDERR, "Trying fallback $cand...\n");
            $previewManager = $server->query($cand);
            $pmError = null; break;
        } catch (\Throwable $e) {
            $pmError .= ' | Fallback ' . $cand . ' failed: ' . $e->getMessage();
        }
    }
}
if ($previewManager === null) {
    fwrite(STDERR, "Preview manager acquisition failed.\n");
    echo json_encode(['error'=>'preview_manager_unavailable','detail'=>$pmError], JSON_PRETTY_PRINT) . "\n";
    exit(0);
}
fwrite(STDERR, "Preview manager acquired.\n");
// Use reflection to access providers (internal)
// Reflect internal provider lists; collect unique objects preserving first-seen order
$ref = new ReflectionObject($previewManager);
$rawProviders = [];
foreach ($ref->getProperties() as $prop) {
    $prop->setAccessible(true);
    if (stripos($prop->getName(),'provider') === false) { continue; }
    $val = $prop->getValue($previewManager);
    if (is_array($val)) {
        foreach ($val as $p) { $rawProviders[] = $p; }
    } elseif (is_object($val)) { $rawProviders[] = $val; }
}

$seen = [];
$providers = [];
foreach ($rawProviders as $p) {
    if (!is_object($p)) { continue; }
    $hash = spl_object_hash($p);
    if (isset($seen[$hash])) { continue; }
    $seen[$hash] = true;
    $providers[] = $p;
}
if (!$providers) { fwrite(STDERR, "No providers discovered via reflection.\n"); }
fwrite(STDERR, "Providers (distinct) found: " . count($providers) . "\n");

$out = [];
foreach ($providers as $idx => $provider) {
    $class = get_class($provider);
    $avail = 'n/a';
    $mimePattern = null;
    try {
        if (method_exists($provider,'getMimeType')) { $mimePattern = @$provider->getMimeType(); }
        if (method_exists($provider,'isAvailable')) {
            $avail = $provider->isAvailable($file) ? 'yes' : 'no';
        }
    } catch (Throwable $e) { $avail = 'err:' . $e->getMessage(); }
    $out[] = [
        'order' => $idx,
        'class' => $class,
        'available_for_3fr' => $avail,
        'mime_pattern' => $mimePattern,
    ];
}
// Attempt standard preview fetch
$thumb = null; $err = null; $t0=microtime(true);
try { $thumb = $previewManager->getPreview($file, 200, 200, true); } catch (Throwable $e) { $err = $e->getMessage(); }
$elapsed = round((microtime(true)-$t0)*1000,2);
$res = [
    'asset' => basename($asset),
    'providers' => $out,
    'preview_generated' => ($thumb && method_exists($thumb,'valid') ? ($thumb->valid()?'yes':'no') : (is_object($thumb)?'unknown':'no')),
    'error' => $err,
    'elapsed_ms' => $elapsed,
    'mime_detected' => $file->getMimeType(),
    'note' => 'order reflects internal enumeration sequence (first match generally wins)'
];

echo json_encode($res, JSON_PRETTY_PRINT) . "\n";
