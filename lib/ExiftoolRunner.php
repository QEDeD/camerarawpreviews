<?php

namespace OCA\CameraRawPreviews;

use Exception;
use Psr\Log\LoggerInterface;

/**
 * ExiftoolRunner centralizes invocation of exiftool so RawPreviewBase can be
 * unit tested by injecting a dummy instance.
 */
class ExiftoolRunner
{
    private $converter; // resolved command string (cached)
    private LoggerInterface $logger;
    private string $appName;

    public function __construct(LoggerInterface $logger, string $appName = 'camerarawpreviews')
    {
        $this->logger = $logger;
        $this->appName = $appName;
    }

    /**
     * Retrieve JSON containing preview related tags.
     * @param string $path
     * @return array
     */
    public function runJsonPreviewData(string $path): array
    {
        $cmd = $this->getConverter() . ' -json -preview:all -FileType ' . $this->escape($path);
        $json = shell_exec($cmd);
        $data = json_decode($json, true);
        if (!is_array($data)) {
            return [[]];
        }
        return $data;
    }

    /**
     * Extract a specific preview tag's binary content to destination file.
     * @throws Exception when extraction failed or result too small
     */
    public function extractPreviewTag(string $sourcePath, string $tag, string $destPath): void
    {
        $cmd = $this->getConverter() . ' -ignoreMinorErrors -b -' . $tag . ' ' . $this->escape($sourcePath) . ' > ' . $this->escape($destPath);
        shell_exec($cmd);
        clearstatcache(true, $destPath);
        if (!file_exists($destPath) || filesize($destPath) < 100) {
            throw new Exception('Unable to extract valid preview data');
        }
    }

    /**
     * Copy orientation tag from RAW into preview image
     */
    public function applyOrientation(string $sourcePath, string $previewPath): void
    {
        $cmd = $this->getConverter() . ' -ignoreMinorErrors -TagsFromFile ' . $this->escape($sourcePath) . ' -orientation -overwrite_original ' . $this->escape($previewPath);
        shell_exec($cmd);
    }

    /**
     * Resolve converter command (static perl or perl script)
     * @throws Exception
     */
    protected function getConverter(): string
    {
        if ($this->converter !== null) {
            return $this->converter;
        }

        $exifToolPath = realpath(__DIR__ . '/../vendor/exiftool/exiftool');

        if ($exifToolPath !== false && strpos(php_uname('m'), 'x86') === 0 && php_uname('s') === 'Linux') {
            $perlBin = $exifToolPath . '/exiftool.bin';
            $perlBinIsExecutable = is_executable($perlBin);
            if (!$perlBinIsExecutable && is_writable($perlBin)) {
                $perlBinIsExecutable = chmod($perlBin, 0744);
            }
            if ($perlBinIsExecutable) {
                $this->converter = $perlBin;
                return $this->converter;
            }
        }

        $exifToolScript = ($exifToolPath ?: (__DIR__ . '/../vendor/exiftool/exiftool')) . '/exiftool';

        $perlBin = \OC_Helper::findBinaryPath('perl');
        if ($perlBin !== null) {
            $this->converter = $perlBin . ' ' . $exifToolScript;
            return $this->converter;
        }

        $perlBin = exec('command -v perl');
        if (!empty($perlBin)) {
            $this->converter = $perlBin . ' ' . $exifToolScript;
            return $this->converter;
        }

        throw new Exception('No perl executable found. Camera Raw Previews app will not work.');
    }

    private function escape(string $arg): string
    {
        return "'" . str_replace("'", "'\\''", $arg) . "'";
    }
}
