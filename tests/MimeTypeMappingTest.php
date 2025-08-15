<?php
namespace OCA\CameraRawPreviews\Tests;

use OCA\CameraRawPreviews\AppInfo\MimeTypeMapping;
use OCP\Files\IMimeTypeLoader;
use PHPUnit\Framework\TestCase;

class MimeTypeMappingTest extends TestCase {
    public function testMappingsCoverSupportedExtensions() {
        if (!interface_exists('OCP\\Files\\IMimeTypeMapping') || !interface_exists('OCP\\Files\\IMimeTypeLoader')) {
            $this->markTestSkipped('Nextcloud OCP mime interfaces not available.');
        }
        $mapping = new MimeTypeMapping();

        $captured = null;
        $loader = $this->getMockBuilder(IMimeTypeLoader::class)->getMock();
        $loader->expects($this->once())
            ->method('registerTypeArray')
            ->with($this->callback(function($arr) use (&$captured) {
                $captured = $arr; return is_array($arr) && !empty($arr);
            }));

        $mapping->getMimeTypeMappings($loader);

        $this->assertIsArray($captured, 'Mappings not captured');

        // Expected extensions supported by provider (RawPreviewBase::isAvailable whitelist)
        $expected = [ 'indd','3fr','arw','cr2','cr3','crw','dng','erf','fff','iiq','kdc','mrw','nef','nrw','orf','ori','pef','raf','rw2','rwl','sr2','srf','srw','tif','tiff','x3f' ];
        foreach ($expected as $ext) {
            $this->assertArrayHasKey($ext, $captured, "Missing mapping for .$ext");
            $mimes = $captured[$ext];
            $this->assertIsArray($mimes);
            $this->assertNotEmpty($mimes, "Empty mapping for .$ext");
            if ($ext === 'indd') {
                $this->assertContains('image/x-indesign', $mimes, 'INDD should map to image/x-indesign');
            } else {
                $this->assertContains('image/x-dcraw', $mimes, ".$ext should map to image/x-dcraw");
            }
        }
    }
}
