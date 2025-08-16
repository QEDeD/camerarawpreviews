<?php
namespace OCA\CameraRawPreviews\Tests\Integration;

use OCP\AppFramework\App;
use PHPUnit\Framework\TestCase;
use OCP\Files\NotFoundException;
use OCP\Files\SimpleFS\ISimpleFile;

/**
 * Focused test: ensure PreviewManager actually produces a preview for 3FR asset (currently expected to FAIL until provider selection fixed).
 */
class Preview3frSelectionTest extends TestCase {
    private $server;
    private $userFolder;
    private $previewManager;

    public static function setUpBeforeClass(): void {
        if (!class_exists('OC_App')) {
            self::markTestSkipped('Nextcloud core not available (run make setup-core or run container).');
        }
        if (!extension_loaded('imagick')) {
            self::markTestSkipped('Imagick not available');
        }
    }

    protected function setUp(): void {
        $app = new App('camerarawpreviews');
        $this->server = $app->getContainer()->getServer();
        if (class_exists('OC_App')) { \OC_App::loadApp('camerarawpreviews'); }
        $this->userFolder = $this->server->getUserFolder('admin');
        $this->previewManager = $this->server->getPreviewManager();
    // No manual MIME mapping injection here; we rely on the app being enabled in a real Nextcloud instance
    }

    public function test3frPreviewGenerated() {
        $asset = __DIR__ . '/../assets/cache/hasselblad_cf132.3FR';
        if (!file_exists($asset)) {
            $this->markTestSkipped('3FR asset missing');
        }
        $data = file_get_contents($asset);
        $file = $this->userFolder->newFile('sel_' . uniqid() . '.3FR', $data);
    // Debug: record mime type resolved by Nextcloud for 3FR file
    $mime = $file->getMimeType();
    fwrite(STDERR, "[DEBUG] 3FR file mime: $mime\n");
        $this->assertSame('image/x-dcraw', $mime, '3FR mapping not applied (expected image/x-dcraw)');
        try {
            $preview = $this->previewManager->getPreview($file, 180, 180);
        } catch (NotFoundException $e) {
            $this->fail('PreviewManager threw NotFoundException for 3FR: ' . $e->getMessage());
            return;
        }
        $this->assertInstanceOf(ISimpleFile::class, $preview, 'PreviewManager did not return a SimpleFS file');
        $bytes = strlen($preview->getContent());
        $this->assertGreaterThan(500, $bytes, '3FR preview too small');
    }
}
