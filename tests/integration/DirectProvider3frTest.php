<?php
namespace OCA\CameraRawPreviews\Tests\Integration;

use OCP\AppFramework\App;
use PHPUnit\Framework\TestCase;
use OCA\CameraRawPreviews\RawPreviewIProviderV2;
use OCA\CameraRawPreviews\ExiftoolRunner;
use Psr\Log\LoggerInterface;

class DirectProvider3frTest extends TestCase {
    public static function setUpBeforeClass(): void {
        if (!class_exists('OC_App')) {
            self::markTestSkipped('Nextcloud core not available (run make setup-core).');
        }
        if (!extension_loaded('imagick')) {
            self::markTestSkipped('Imagick not available');
        }
    }

    public function testDirect3frExtraction() {
        $asset = __DIR__ . '/../assets/cache/hasselblad_cf132.3FR';
        if (!file_exists($asset)) {
            $this->markTestSkipped('3FR asset missing');
        }
        $app = new App('camerarawpreviews');
        $server = $app->getContainer()->getServer();
        $logger = $server->get(LoggerInterface::class);
        $userFolder = $server->getUserFolder('admin');
        $file = $userFolder->newFile('t_' . uniqid() . '.3FR', file_get_contents($asset));
        $provider = new RawPreviewIProviderV2($logger, new ExiftoolRunner($logger));
        $this->assertTrue($provider->isAvailable($file), 'Provider not available for 3FR');
        $img = $provider->getThumbnail($file, 200, 200);
        $this->assertNotNull($img, 'Null image returned');
        $this->assertTrue($img->valid(), 'Image invalid');
        $tmp = sys_get_temp_dir() . '/prov3fr_' . uniqid() . '.jpg';
        $img->save($tmp);
        $this->assertFileExists($tmp, 'Output file missing');
        $this->assertGreaterThan(500, filesize($tmp), 'Preview too small');
        @unlink($tmp);
    }
}
