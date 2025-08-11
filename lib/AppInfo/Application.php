<?php

namespace OCA\CameraRawPreviews\AppInfo;

use OCA\CameraRawPreviews\RawPreviewIProviderV2;
use OCP\AppFramework\Bootstrap\IBootContext;
use OCP\AppFramework\Bootstrap\IBootstrap;
use OCP\AppFramework\Bootstrap\IRegistrationContext;
use OCP\EventDispatcher\IEventDispatcher;
use OCP\AppFramework\App;
use OCP\Util;

class Application extends App implements IBootstrap
{
    private $appName = 'camerarawpreviews';

    public function __construct()
    {
        parent::__construct($this->appName);
    }

    public function register(IRegistrationContext $context): void {
        include_once __DIR__ . '/../../vendor/autoload.php';

        $this->registerProvider($context);
    }

    private function registerScripts(IBootContext $context)
    {
        // Check if Viewer app is available
        if (!class_exists('\OCA\Viewer\Event\LoadViewer')) {
            // Log that Viewer app is not available for debugging
            error_log('Camera Raw Previews: Viewer app LoadViewer event not available');
            return;
        }

        try {
            $eventDispatcher = $context->getServerContainer()->get(IEventDispatcher::class);
            $eventDispatcher->addListener(\OCA\Viewer\Event\LoadViewer::class, function () {
                Util::addScript($this->appName, 'register-viewer');  // adds js/register-viewer.js
                error_log('Camera Raw Previews: Viewer script registered');
            });
        } catch (\Exception $e) {
            error_log('Camera Raw Previews: Error registering viewer scripts: ' . $e->getMessage());
        }
    }

    private function registerProvider(IRegistrationContext $context)
    {
        $server = $this->getContainer()->getServer();
        $mimeTypeDetector = $server->getMimeTypeDetector();
        $mimeTypeDetector->getAllMappings(); // is really needed

        $mimesToDetect = [
            'indd' => ['image/x-indesign'],
            '3fr' => ['image/x-dcraw'],
            'arw' => ['image/x-dcraw'],
            'cr2' => ['image/x-dcraw'],
            'cr3' => ['image/x-dcraw'],
            'crw' => ['image/x-dcraw'],
            'dng' => ['image/x-dcraw'],
            'erf' => ['image/x-dcraw'],
            'fff' => ['image/x-dcraw'],
            'iiq' => ['image/x-dcraw'],
            'kdc' => ['image/x-dcraw'],
            'mrw' => ['image/x-dcraw'],
            'nef' => ['image/x-dcraw'],
            'nrw' => ['image/x-dcraw'],
            'orf' => ['image/x-dcraw'],
            'ori' => ['image/x-dcraw'],
            'pef' => ['image/x-dcraw'],
            'raf' => ['image/x-dcraw'],
            'rw2' => ['image/x-dcraw'],
            'rwl' => ['image/x-dcraw'],
            'sr2' => ['image/x-dcraw'],
            'srf' => ['image/x-dcraw'],
            'srw' => ['image/x-dcraw'],
            'tif' => ['image/x-dcraw'],
            'tiff' => ['image/x-dcraw'],
            'x3f' => ['image/x-dcraw'],
        ];

        $mimeTypeDetector->registerTypeArray($mimesToDetect);
        $context->registerPreviewProvider(RawPreviewIProviderV2::class, '/^((image\/x-dcraw)|(image\/x-indesign))(;+.*)*$/');
    }

    public function boot(IBootContext $context): void {
        $this->registerScripts($context);
        
        // Add fallback script registration for when Viewer event doesn't fire
        try {
            Util::addScript($this->appName, 'register-viewer');
            error_log('Camera Raw Previews: Fallback script registration completed');
        } catch (\Exception $e) {
            error_log('Camera Raw Previews: Error in fallback script registration: ' . $e->getMessage());
        }
    }

}
