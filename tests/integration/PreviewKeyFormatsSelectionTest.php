<?php
namespace OCA\CameraRawPreviews\Tests\Integration;

use OCP\AppFramework\App;
use OCP\Files\NotFoundException;
use OCP\Files\SimpleFS\ISimpleFile;
use PHPUnit\Framework\TestCase;

/**
 * Integration test for key formats: NEF, CR2, DNG (always), ARW and CR3 (optional when assets are present).
 */
class PreviewKeyFormatsSelectionTest extends TestCase {
    private $server;
    private $userFolder;
    private $previewManager;

    public static function setUpBeforeClass(): void {
        if (!class_exists('OC_App')) {
            self::markTestSkipped('Nextcloud core not available (run make setup-core or run container).');
        }
    }

    protected function setUp(): void {
        $app = new App('camerarawpreviews');
        $this->server = $app->getContainer()->getServer();
        if (class_exists('OC_App')) { \OC_App::loadApp('camerarawpreviews'); }
        $this->userFolder = $this->server->getUserFolder('admin');
        $this->previewManager = $this->server->getPreviewManager();
    }

    public function testPreviewsForKeyFormats() {
        $manifestPath = __DIR__ . '/../assets/manifest.json';
        $cacheDir = __DIR__ . '/../assets/cache';
        $manifest = json_decode(file_get_contents($manifestPath), true) ?: [];
        $want = ['nef'=>true,'cr2'=>true,'dng'=>true,'arw'=>true,'cr3'=>true];
        $processed = 0; $seenAny = 0;
        foreach ($manifest as $entry) {
            $fmt = strtolower($entry['format'] ?? '');
            if (!isset($want[$fmt])) { continue; }
            $fn = $entry['filename'];
            $src = $cacheDir . '/' . $fn;
            if (!file_exists($src)) { continue; }
            $seenAny++;
            $data = file_get_contents($src);
            $file = $this->userFolder->newFile($fn, $data);
            try {
                $preview = $this->previewManager->getPreview($file, 160, 160);
                $this->assertInstanceOf(ISimpleFile::class, $preview);
                $bytes = strlen($preview->getContent());
                $this->assertGreaterThan(500, $bytes, $fmt . ' preview too small: ' . $fn);
                $processed++;
            } catch (NotFoundException $e) {
                $this->fail('Preview not found for ' . $fmt . ' file ' . $fn . ': ' . $e->getMessage());
            }
        }
        // We expect at least NEF, CR2, DNG to be present; ARW and CR3 are optional
        $this->assertGreaterThanOrEqual(3, $seenAny, 'Expected at least 3 key-format assets present (nef, cr2, dng)');
        $this->assertGreaterThanOrEqual(3, $processed, 'Expected to generate previews for at least NEF, CR2, and DNG');
    }
}
