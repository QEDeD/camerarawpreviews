<?php

namespace OCA\CameraRawPreviews\AppInfo;

use OCA\CameraRawPreviews\RawPreviewIProviderV2;
use OCP\AppFramework\Bootstrap\IBootContext;
use OCP\AppFramework\Bootstrap\IBootstrap;
use OCP\AppFramework\Bootstrap\IRegistrationContext;
use OCP\EventDispatcher\IEventDispatcher;
use OCP\AppFramework\App;
use OCP\Util;
use Psr\Log\LoggerInterface;

class Application extends App implements IBootstrap
{
    private const APP_ID = 'camerarawpreviews';

    public function __construct()
    {
        parent::__construct(self::APP_ID);
    }

    public function register(IRegistrationContext $context): void
    {
        include_once __DIR__ . '/../../vendor/autoload.php';
        $this->registerProvider($context);
    }

    private function registerScripts(IBootContext $context)
    {
        $logger = $context->getServerContainer()->get(LoggerInterface::class);

        // Check if Viewer app is available
        if (!class_exists('\OCA\Viewer\Event\LoadViewer')) {
            $logger->info('Viewer app LoadViewer event not available, using direct registration', ['app' => self::APP_ID]);
            // Fallback: register script immediately for NC 31 compatibility
            Util::addScript(self::APP_ID, 'register-viewer');
            return;
        }

        try {
            $eventDispatcher = $context->getServerContainer()->get(IEventDispatcher::class);
            $eventDispatcher->addListener(\OCA\Viewer\Event\LoadViewer::class, function () use ($logger) {
                Util::addScript(self::APP_ID, 'register-viewer');
                $logger->debug('Viewer script registered via LoadViewer event', ['app' => self::APP_ID]);
            });
            $logger->debug('LoadViewer event listener registered', ['app' => self::APP_ID]);
        } catch (\Exception $e) {
            $logger->error('Error registering viewer scripts: ' . $e->getMessage(), ['app' => self::APP_ID]);
            // Fallback if event registration fails
            Util::addScript(self::APP_ID, 'register-viewer');
        }
    }

    private function registerProvider(IRegistrationContext $context)
    {
        // Use existing MimeTypeMapping registration class for mapping definitions
        // (relies on autoloaded OCA\CameraRawPreviews\AppInfo\MimeTypeMapping implementing IMimeTypeMapping)
        // Narrow regex to our RAW mapping only; avoids accidental generic matches
    // Broaden regex to allow application/octet-stream (uncategorized RAW uploads) and InDesign again
        $context->registerPreviewProvider(RawPreviewIProviderV2::class, '/^((image\/x-dcraw)|(image\/x-indesign)|(application\/octet-stream))(;+.*)*$/');
        // Temporary debug marker (remove after 3FR selection issue resolved)
        try {
            $logger = $this->getContainer()->getServer()->get(LoggerInterface::class);
            $logger->info('Registered RawPreviewIProviderV2 with regex image/x-dcraw', ['app' => self::APP_ID]);
        } catch (\Throwable $e) {
/* ignore logging failures */
        }
    }

    public function boot(IBootContext $context): void
    {
        $this->registerScripts($context);
        $this->ensureProviderRegistered($context);
    }

    /**
     * Fallback safety: if our preview provider was not registered early enough
     * (e.g. during certain CLI test bootstrap paths), inject it directly into
     * the PreviewManager's internal provider list so selection can consider it.
     * This is a temporary workaround aiding integration test reliability.
     */
    private function ensureProviderRegistered(IBootContext $context): void
    {
        try {
            $sc = $context->getServerContainer();
            $logger = $sc->get(LoggerInterface::class);
            if (!method_exists($sc, 'getPreviewManager')) {
                return;
            }
            $pm = $sc->getPreviewManager();
            if (!$pm) {
                return;
            }
            $found = false;
            $ref = new \ReflectionObject($pm);
            foreach ($ref->getProperties() as $prop) {
                $prop->setAccessible(true);
                $val = $prop->getValue($pm);
                if (is_array($val)) {
                    foreach ($val as $prov) {
                        if (is_object($prov) && get_class($prov) === RawPreviewIProviderV2::class) {
                            $found = true;
                            break 2;
                        }
                    }
                }
            }
            if ($found) {
                return;
            }
            // Create provider instance
            $provider = new RawPreviewIProviderV2($sc->get(LoggerInterface::class));
            // Attempt to append into first array-like provider property
            foreach ($ref->getProperties() as $prop) {
                $prop->setAccessible(true);
                $val = $prop->getValue($pm);
                if (is_array($val)) {
                    $val[] = $provider;
                    $prop->setValue($pm, $val);
                    $logger->info('Injected RawPreviewIProviderV2 into PreviewManager (fallback path)', ['app' => self::APP_ID, 'property' => $prop->getName()]);
                    return;
                }
            }
            $logger->info('Unable to inject provider (no suitable property found)', ['app' => self::APP_ID]);
        } catch (\Throwable $e) {
            try {
                $logger?->warning('Provider injection failed: ' . $e->getMessage(), ['app' => self::APP_ID]);
            } catch (\Throwable $ignore) {
            }
        }
    }
}
