<?php

use OCA\CameraRawPreviews\RawPreviewBase;
use PHPUnit\Framework\TestCase;
use Psr\Log\LoggerInterface;

final class MimeRegexTest extends TestCase {
    public function testRegexAllowsExpectedMimes() {
    $dummyLogger = new class implements LoggerInterface {
            public function emergency($message, array $context = array()) {}
            public function alert($message, array $context = array()) {}
            public function critical($message, array $context = array()) {}
            public function error($message, array $context = array()) {}
            public function warning($message, array $context = array()) {}
            public function notice($message, array $context = array()) {}
            public function info($message, array $context = array()) {}
            public function debug($message, array $context = array()) {}
            public function log($level, $message, array $context = array()) {}
        };
        $base = new RawPreviewBase($dummyLogger);
        $rx = $base->getMimeType();
    $this->assertTrue((bool)preg_match('#^/.+/$#', $rx), 'Expected a regex string');
    $this->assertTrue((bool)preg_match($rx, 'image/x-dcraw'), 'dcraw mime not matched');
    $this->assertTrue((bool)preg_match($rx, 'image/x-indesign'), 'indesign mime not matched');
    $this->assertTrue((bool)preg_match($rx, 'application/octet-stream'), 'octet-stream mime not matched');
    }
}
