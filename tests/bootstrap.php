<?php

// Standalone-friendly bootstrap: Attempt to include Nextcloud core bootstrap; if missing, mark tests skipped.

setlocale(LC_ALL, 'C');
setlocale(LC_CTYPE, 'C');

// Composer autoload (project classes)
$autoload = __DIR__ . '/../vendor/autoload.php';
if (file_exists($autoload)) {
	require_once $autoload;
}

$coreDir = __DIR__ . '/../nextcloud-placeholder'; // placeholder for search
// Try relative path to local Nextcloud extraction (developer flow)
$localNcBase = __DIR__ . '/../nextcloud';
if (is_dir($localNcBase)) {
	@ini_set('memory_limit','512M');
	$baseFile = realpath($localNcBase . '/lib/base.php');
	if ($baseFile) {
		require_once $baseFile; // initializes Nextcloud base
		if (class_exists('OC_App')) {
			// Minimal setup: register app paths
			\call_user_func(['OC_App','loadApp'], 'camerarawpreviews');
		}
	}
}

// Container flow: include core base from /var/www/html when running inside NC container
if (!class_exists('OC_App')) {
	$containerBase = '/var/www/html/lib/base.php';
	if (is_file($containerBase)) {
		@ini_set('memory_limit','512M');
		require_once $containerBase;
		if (class_exists('OC_App')) {
			\call_user_func(['OC_App','loadApp'], 'camerarawpreviews');
		}
	}
}
// Fallback skip flag if still no core
if (!class_exists('OC_App')) {
	if (!defined('CRP_STANDALONE_SKIP')) {
		define('CRP_STANDALONE_SKIP', true);
	}
}
