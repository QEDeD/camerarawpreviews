<?php
namespace OCA\CameraRawPreviews\Tests\Integration;

use PHPUnit\Framework\TestCase;

class EnvSanityTest extends TestCase {
    public static function setUpBeforeClass(): void {
        if (!class_exists('OC_App')) {
            self::markTestSkipped('Nextcloud core not available. Run container: make run-nc-container');
        }
    }

    public function testCoreAndAppEnabledAndMappingActive(): void {
        // Core loaded
        $this->assertTrue(class_exists('OC_App'), 'OC_App class missing (core not loaded)');

        // App enabled
        $enabled = false;
        try {
            if (class_exists('OC_App')) {
                $enabled = \call_user_func(['OC_App','isEnabled'], 'camerarawpreviews');
            }
        } catch (\Throwable $e) {}
        $this->assertTrue((bool)$enabled, 'App camerarawpreviews not enabled');

        // Mapping active: .3fr resolves to image/x-dcraw
        $mt = \OC::$server->getMimeTypeLoader();
        $mime = $mt->getMimetype('foo.3fr');
        $this->assertSame('image/x-dcraw', $mime, '3FR mapping not applied');

        // Optional: Imagick TIFF support (informative; enforced by Makefile preflight when FULL coverage)
        $hasImagick = \extension_loaded('imagick');
        if ($hasImagick) {
            $hasTiff = \count(\Imagick::queryformats('TIFF')) > 0;
            if (!$hasTiff) {
                fwrite(STDERR, "[WARN] Imagick loaded but TIFF delegate missing; TIFF previews may skip.\n");
            }
            $this->assertTrue(true); // keep test green
        } else {
            fwrite(STDERR, "[WARN] Imagick extension missing; TIFF previews may skip.\n");
            $this->assertTrue(true);
        }
    }
}
