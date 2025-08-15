<?php
namespace OCA\CameraRawPreviews\Tests;

use OCA\CameraRawPreviews\RawPreviewBase;
use OCA\CameraRawPreviews\ExiftoolRunner;
use Psr\Log\NullLogger;

// Only run when phpunit present
if (!class_exists('PHPUnit\\Framework\\TestCase')) { return; }

class DummyRunner extends ExiftoolRunner {
    private array $data;
    public function __construct(array $data) { parent::__construct(new NullLogger()); $this->data = $data; }
    public function runJsonPreviewData(string $path): array { return $this->data; }
    public function extractPreviewTag(string $sourcePath, string $tag, string $destPath): void { /* noop */ }
    public function applyOrientation(string $sourcePath, string $previewPath): void { /* noop */ }
}

class TestableRawPreviewBase extends RawPreviewBase {
    private bool $tiffCompat;
    public function __construct(array $jsonData, bool $tiffCompat) {
        $runner = new DummyRunner($jsonData);
        parent::__construct(new NullLogger(), $runner);
        $this->tiffCompat = $tiffCompat;
    }
    protected function isTiffCompatible(): bool { return $this->tiffCompat; }
    public function selectTag(string $path): array { return $this->getBestPreviewTag($path); }
}

class RawPreviewBaseTagTest extends \PHPUnit\Framework\TestCase {
    public function testSelectFirstPreferredJpgTag() {
        $data = [[ 'FileType' => 'RAW', 'JpgFromRaw' => 'X', 'PreviewImage' => 'Y' ]];
        $o = new TestableRawPreviewBase($data, false);
        $tag = $o->selectTag('/tmp/f.raw');
        $this->assertSame(['tag'=>'JpgFromRaw','ext'=>'jpg'],$tag);
    }

    public function testFallsBackToTiffWhenSourceFile() {
        $data = [[ 'FileType' => 'TIFF' ]];
        $o = new TestableRawPreviewBase($data, true);
        $tag = $o->selectTag('/tmp/f.tiff');
        $this->assertSame(['tag'=>'SourceFile','ext'=>'tiff'],$tag);
    }

    public function testSelectsExplicitTiffPreviewTagWhenPresent() {
        // FileType not TIFF (so SourceFile shortcut not taken) but TIFF preview tag available
        $data = [[ 'FileType' => 'RAW', 'PreviewTIFF' => 'X' ]];
        $o = new TestableRawPreviewBase($data, true);
        $tag = $o->selectTag('/tmp/f.raw');
        $this->assertSame(['tag'=>'PreviewTIFF','ext'=>'tiff'],$tag);
    }

    public function testSelectsThumbnailTiffTagWhenPresent() {
        // Ensure non-TIFF FileType so SourceFile early return is not used
        $data = [[ 'FileType' => 'RAW', 'ThumbnailTIFF' => 'X' ]];
        $o = new TestableRawPreviewBase($data, true);
        $tag = $o->selectTag('/tmp/f.raw');
        $this->assertSame(['tag'=>'ThumbnailTIFF','ext'=>'tiff'],$tag);
    }

    public function testRunnerFailureRaisesException() {
        $this->expectException(\Exception::class);
        // Simulate Exiftool failure by injecting a runner that throws
        $failingRunner = new class extends ExiftoolRunner {
            public function __construct() { parent::__construct(new NullLogger()); }
            public function runJsonPreviewData(string $path): array { throw new \Exception('Simulated exiftool failure'); }
        };
        // Minimal subclass exposing protected tag selection with failing runner
        $o = new class($failingRunner) extends RawPreviewBase {
            public function __construct($runner) { parent::__construct(new NullLogger(), $runner); }
            public function forceSelect(string $p) { return $this->getBestPreviewTag($p); }
            protected function isTiffCompatible(): bool { return true; }
        };
        $o->forceSelect('/tmp/any.raw');
    }

    public function testThrowsWhenNoPreview() {
        $this->expectException(\Exception::class);
        $data = [[ 'FileType' => 'UNKNOWN' ]];
        $o = new TestableRawPreviewBase($data, false);
        $o->selectTag('/tmp/f.unknown');
    }
}
