<?php

namespace OCA\CameraRawPreviews;

use OCP\Files\File;
use OCP\Files\FileInfo;
use OCP\IImage;
use OCP\Preview\IProviderV2;
use OCP\Preview\IProvider2;
use Psr\Log\LoggerInterface;

class RawPreviewIProviderV2 extends RawPreviewBase implements IProviderV2
{
    public function getMimeType(): string
    {
        $mt = parent::getMimeType();
        if (isset($this->logger)) {
            $this->logger->info('Provider getMimeType', ['app' => $this->appName, 'pattern' => $mt]);
        }
        return $mt;
    }

    public function isAvailable(FileInfo $file): bool
    {
        $res = parent::isAvailable($file);
        if (isset($this->logger) && method_exists($file, 'getName')) {
            $this->logger->info('Provider isAvailable invoked', [
                'app' => $this->appName,
                'name' => $file->getName(),
                'ext' => strtolower($file->getExtension()),
                'result' => $res ? 'yes' : 'no'
            ]);
        }
        return $res;
    }

    public function getThumbnail(File $file, int $maxX, int $maxY): ?IImage
    {
        if (isset($this->logger) && method_exists($file, 'getName')) {
            $this->logger->info('Provider getThumbnail start', [
                'app' => $this->appName,
                'name' => $file->getName(),
                'ext' => strtolower($file->getExtension()),
                'maxX' => $maxX,
                'maxY' => $maxY
            ]);
        }
        return $this->getThumbnailInternal($file, $maxX, $maxY);
    }
}
