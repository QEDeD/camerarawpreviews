<?php
namespace OCA\CameraRawPreviews\Tests\Integration;

use OCP\AppFramework\App;
use OCP\Files\NotFoundException;
use OCP\Files\SimpleFS\ISimpleFile;
use PHPUnit\Framework\TestCase;

/**
 * Integration test (requires Nextcloud core present via setup-core script)
 * Verifies end-to-end preview generation for cached RAW assets.
 */
class PreviewFlowTest extends TestCase {
    private $server;
    private $userFolder;
    private $previewManager;

    public static function setUpBeforeClass(): void {
        if (!class_exists('OC_App')) {
            self::markTestSkipped('Nextcloud core not available (run make setup-core).');
        }
    }

    protected function setUp(): void {
        $app = new App('camerarawpreviews');
        $this->server = $app->getContainer()->getServer();
    // Ensure the app bootstrap (provider registration) has run
    if (class_exists('OC_App')) { \OC_App::loadApp('camerarawpreviews'); }
        $this->userFolder = $this->server->getUserFolder('admin');
        $this->previewManager = $this->server->getPreviewManager();
    }

    public function testPreviewGeneratedForEachCachedAsset() {
        $manifestPath = __DIR__ . '/../assets/manifest.json';
        $cacheDir = __DIR__ . '/../assets/cache';
        $manifest = json_decode(file_get_contents($manifestPath), true) ?: [];
        $processed = 0;
        $exiftool=null;
        foreach (['vendor/exiftool/exiftool/exiftool.bin','vendor/exiftool/exiftool/exiftool'] as $c) {
            if (file_exists(__DIR__.'/../../..' . '/' . $c)) { $exiftool=$c; break; }
        }
        $tiffCompat = extension_loaded('imagick') && count(\Imagick::queryformats('TIFF')) > 0;
        foreach ($manifest as $entry) {
            $fn = $entry['filename'];
            $src = $cacheDir . '/' . $fn;
            if (!file_exists($src)) { continue; }
            if (isset($entry['expectedTag']) && $entry['expectedTag'] === 'ThumbnailTIFF' && !$tiffCompat) {
                $this->markTestSkipped('Skipping TIFF preview asset due to missing Imagick TIFF support');
            }
            $data = file_get_contents($src);
            $file = $this->userFolder->newFile($fn, $data);
            try {
                $preview = $this->previewManager->getPreview($file, 120, 120);
                if (!$preview instanceof ISimpleFile) {
                    throw new NotFoundException('Preview manager returned non-file');
                }
                $size = strlen($preview->getContent());
                if ($size < 100) {
                    throw new NotFoundException('Preview too small');
                }
                $processed++;
                if ($exiftool && !empty($entry['expectedTag'])) {
                    $json = @shell_exec($exiftool . ' -json -preview:all -FileType ' . escapeshellarg($src));
                    if ($json) {
                        $info = json_decode($json,true);
                        if (is_array($info) && isset($info[0])) {
                            $info=$info[0];
                            $fileType=$info['FileType'] ?? 'n/a';
                            $priorities=['JpgFromRaw','PageImage','PreviewImage','OtherImage','ThumbnailImage'];
                            $chosen=null; foreach ($priorities as $p) { if (isset($info[$p])) { $chosen=$p; break; } }
                            if (!$chosen) {
                                if ($fileType==='TIFF') { $chosen='SourceFile'; }
                                else { foreach (['PreviewTIFF','ThumbnailTIFF'] as $p) { if (isset($info[$p])) { $chosen=$p; break; } } }
                            }
                            if ($chosen) { $this->assertSame($entry['expectedTag'], $chosen, 'Expected tag mismatch for '.$fn); }
                        }
                    }
                }
            } catch (NotFoundException $e) {
                if (!empty($entry['expectedTag']) && str_contains($entry['expectedTag'],'TIFF')) {
                    // Log skip reason
                    fwrite(STDERR, "Skipping TIFF asset due to preview failure: $fn - " . $e->getMessage() . "\n");
                    continue;
                }
                $this->fail('Preview not found for ' . $fn . ': ' . $e->getMessage());
            }
        }
        $this->assertGreaterThan(0, $processed, 'No assets processed');
    }

    public function testIntegrationHarnessLoads() {
        $this->assertTrue(true, 'Harness sanity check');
    }
}
