<?php
@ini_set('memory_limit','512M');
$assetRel = 'tests/assets/cache/hasselblad_cf132.3FR';
$asset = __DIR__ . '/../' . $assetRel;
if (!file_exists($asset)) { fwrite(STDERR, "Asset not found: $assetRel\n"); exit(2);} 
require __DIR__ . '/../nextcloud/lib/base.php';
require __DIR__ . '/../vendor/autoload.php';

use OCA\CameraRawPreviews\RawPreviewIProviderV2;
use OCA\CameraRawPreviews\ExiftoolRunner;
use Psr\Log\LoggerInterface;

$server = \OC::$server;
$logger = $server->get(LoggerInterface::class);
$userFolder = $server->getUserFolder('admin');
$contents = file_get_contents($asset);
$file = $userFolder->newFile('diag_3fr_' . uniqid() . '.3FR', $contents);

$provider = new RawPreviewIProviderV2($logger, new ExiftoolRunner($logger));

$mime = $file->getMimeType();
$ext = strtolower($file->getExtension());
$available = $provider->isAvailable($file) ? 'yes' : 'no';

$start = microtime(true);
fwrite(STDERR, "Attempting thumbnail extraction...\n");
$preview = null;
try {
    $preview = $provider->getThumbnail($file, 200, 200);
} catch (Throwable $e) {
    fwrite(STDERR, "Exception during getThumbnail: " . $e->getMessage() . "\n");
}
$elapsed = round((microtime(true) - $start)*1000,2);

if ($preview && $preview->valid()) {
    // OCP\Image doesn't expose getContent(); write to temp file for size
    $tmpOut = sys_get_temp_dir() . '/diag3fr_' . uniqid() . '.jpg';
    $preview->save($tmpOut);
    $len = @filesize($tmpOut) ?: 0;
    echo json_encode([
        'status' => 'ok',
        'mime' => $mime,
        'ext' => $ext,
        'available' => $available,
        'preview_bytes' => $len,
        'out_file' => $tmpOut,
        'elapsed_ms' => $elapsed
    ], JSON_PRETTY_PRINT) . "\n";
} else {
    echo json_encode([
        'status' => 'fail',
        'mime' => $mime,
        'ext' => $ext,
        'available' => $available,
        'elapsed_ms' => $elapsed
    ], JSON_PRETTY_PRINT) . "\n";
}
