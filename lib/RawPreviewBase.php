<?php

namespace OCA\CameraRawPreviews;


use Exception;
use Imagick;
use OCP\Files\File;
use OCP\Files\FileInfo;
use OCP\Files\NotFoundException;
use OCP\Files\NotPermittedException;
use OCP\IImage;
use OCP\Image;
use OCP\Lock\LockedException;
use Psr\Log\LoggerInterface;

class RawPreviewBase
{
    protected $driver; // legacy unused
    protected $logger;
    protected $appName;
    protected $tmpFiles = [];
    protected ExiftoolRunner $runner;

        public function __construct(LoggerInterface $logger, ?ExiftoolRunner $runner = null)
    {
        $this->logger = $logger;
        $this->appName = 'camerarawpreviews';
            $this->runner = $runner ?: new ExiftoolRunner($logger, $this->appName);
    }

    /**
     * @return string
     */
    public function getMimeType(): string
    {
    // Also allow application/octet-stream to catch RAW files not recognized by core yet; filtered by extension in isAvailable
    return '/^((image\/x-dcraw)|(image\/x-indesign)|(application\/octet-stream))(;+.*)*$/';
    }

    /**
     * @param FileInfo $file
     * @return bool
     */
    public function isAvailable(FileInfo $file): bool
    {
        $ext = strtolower($file->getExtension());
        $supported = [ 'indd','3fr','arw','cr2','cr3','crw','dng','erf','fff','iiq','kdc','mrw','nef','nrw','orf','ori','pef','raf','rw2','rwl','sr2','srf','srw','tif','tiff','x3f' ];
        $ok = true;
        if (!in_array($ext, $supported, true)) { $ok = false; }
        if ($ok && ($ext === 'tiff' || $ext === 'tif') && !$this->isTiffCompatible()) { $ok = false; }
        if ($ok && $file->getSize() <= 0) { $ok = false; }
        // Log decision path (debug level)
        if (method_exists($file,'getName')) {
            $this->logger->debug('isAvailable check', [
                'app' => $this->appName,
                'name' => $file->getName(),
                'ext' => $ext,
                'size' => $file->getSize(),
                'result' => $ok ? 'yes' : 'no'
            ]);
        }
        return $ok;
    }

    protected function getThumbnailInternal(File $file, int $maxX, int $maxY): ?IImage
    {
    $overallStart = microtime(true);
        try {
            $localPath = $this->getLocalFile($file);
        } catch (Exception $e) {
            $this->logger->warning($e->getMessage(), ['app' => $this->appName, 'exception' => $e]);
            return null;
        }

    try {
            $this->logger->debug('Preview pipeline start', [
                'app' => $this->appName,
                'name' => $file->getName(),
                'ext' => strtolower($file->getExtension()),
                'size' => $file->getSize(),
                'maxX' => $maxX,
                'maxY' => $maxY,
            ]);
            $tagData = $this->getBestPreviewTag($localPath);
            $previewTag = $tagData['tag'];
            $this->logger->debug('Selected preview tag', [
                'app' => $this->appName,
                'name' => $file->getName(),
                'tag' => $previewTag,
                'ext' => $tagData['ext']
            ]);


            if ($previewTag === 'SourceFile') {
                // load the original file as fallback when TIFF has no preview embedded
                $previewImageTmpPath = $localPath;
                $this->logger->debug('Using SourceFile directly (no embedded preview)', [
                    'app' => $this->appName,
                    'name' => $file->getName()
                ]);
            } else {
    $extractStart = microtime(true);
        $previewImageTmpPath = sys_get_temp_dir() . '/' . md5($localPath . uniqid('', true)) . '.' . $tagData['ext'];
                $this->tmpFiles[] = $previewImageTmpPath;

                //extract preview image using exiftool to file
        $this->runner->extractPreviewTag($localPath, $previewTag, $previewImageTmpPath);
                if (filesize($previewImageTmpPath) < 100) {
                    throw new Exception('Unable to extract valid preview data');
                }

                //update previewImageTmpPath  with orientation data
        $this->runner->applyOrientation($localPath, $previewImageTmpPath);
                $extractElapsedMs = (microtime(true) - $extractStart) * 1000;
                $this->logger->debug('Extracted preview tag', [
                    'app' => $this->appName,
                    'name' => $file->getName(),
                    'tag' => $previewTag,
                    'tmp' => $previewImageTmpPath,
                    'bytes' => @filesize($previewImageTmpPath) ?: 0,
                    'extract_ms' => isset($extractElapsedMs) ? round($extractElapsedMs,2) : null
                ]);
            }

            $image = new Image;

            // we have checked for tiff support in getBestPreviewTag
            if ($tagData['ext'] === 'tiff') {
                $imagick = new Imagick($previewImageTmpPath);
                $imagick->autoOrient();
                $imagick->setImageFormat('jpg');
                $image->loadFromData($imagick->getImageBlob());
            } else {
                $image->loadFromFile($previewImageTmpPath);
            }

            $image->fixOrientation();
            $image->scaleDownToFit($maxX, $maxY);
            $previewBytes = @filesize($previewImageTmpPath) ?: 0;
            $overallElapsedMs = (microtime(true) - $overallStart) * 1000;

            $this->logger->debug('Preview extracted', [
                'app' => $this->appName,
                'fileSize' => $file->getSize(),
                'previewBytes' => $previewBytes,
                'tag' => $previewTag,
                'ext' => $tagData['ext'],
                't_ms' => round($overallElapsedMs, 2),
                'extraction_ms' => isset($extractElapsedMs) ? round($extractElapsedMs, 2) : null,
                'sourceIsPreview' => $previewTag === 'SourceFile'
            ]);

            $this->cleanTmpFiles();

            //check if image object is valid
            if (!$image->valid()) {
                return null;
            }
            return $image;
        } catch (Exception $e) {
            $this->logger->warning($e->getMessage(), ['app' => $this->appName, 'exception' => $e]);

            $this->cleanTmpFiles();
            return null;
        }
    }

    /**
     * Get a path to either the local file or temporary file
     *
     * @param File $file
     * @return string
     * @throws LockedException
     * @throws NotFoundException
     * @throws NotPermittedException
     */
    private function getLocalFile(File $file): string
    {
        $useTempFile = $file->isEncrypted() || !$file->getStorage()->isLocal();
        if ($useTempFile) {
            $absPath = \OC::$server->getTempManager()->getTemporaryFile();
            $in = $file->fopen('r');
            $out = fopen($absPath, 'w');
            if ($in === false || $out === false) {
                if (is_resource($in)) { fclose($in); }
                if (is_resource($out)) { fclose($out); }
                throw new \RuntimeException('Unable to open streams for temporary copy');
            }
            stream_copy_to_stream($in, $out);
            fclose($in);
            fclose($out);
            $this->tmpFiles[] = $absPath;
            return $absPath;
        } else {
            return $file->getStorage()->getLocalFile($file->getInternalPath());
        }
    }

    /**
     * @param string $tmpPath
     * @return array
     * @throws Exception
     */
    protected function getBestPreviewTag(string $tmpPath): array
    {
    $previewData = $this->runner->runJsonPreviewData($tmpPath);
        $fileType = $previewData[0]['FileType'] ?? 'n/a';

        // potential tags in priority
        $tagsToCheck = [
            'JpgFromRaw',
            'PageImage',
            'PreviewImage',
            'OtherImage',
            'ThumbnailImage',
        ];

        // tiff tags that need extra checks
        $tiffTagsToCheck = [
            'PreviewTIFF',
            'ThumbnailTIFF'
        ];

        // return at first found tag
        foreach ($tagsToCheck as $tag) {
            if (!isset($previewData[0][$tag])) {
                continue;
            }
            return ['tag' => $tag, 'ext' => 'jpg'];
        }

        // we know we can handle TIFF files directly
        if ($fileType === 'TIFF' && $this->isTiffCompatible()) {
            return ['tag' => 'SourceFile', 'ext' => 'tiff'];
        }

        // extra logic for tiff previews
        foreach ($tiffTagsToCheck as $tag) {
            if (!isset($previewData[0][$tag])) {
                continue;
            }
            if (!$this->isTiffCompatible()) {
                throw new Exception('Needs imagick to extract TIFF previews');
            }
            return ['tag' => $tag, 'ext' => 'tiff'];
        }
        throw new Exception('Unable to find preview data');
    }

    /**
     * @return bool
     */
    protected function isTiffCompatible(): bool
    {
        return extension_loaded('imagick') && count(\Imagick::queryformats('TIFF')) > 0;
    }

    /**
     * Clean any generated temporary files
     */
    private function cleanTmpFiles()
    {
        foreach ($this->tmpFiles as $tmpFile) {
            if (is_string($tmpFile) && $tmpFile !== '' && file_exists($tmpFile)) {
                @unlink($tmpFile);
            }
        }

        $this->tmpFiles = [];
    }
}
