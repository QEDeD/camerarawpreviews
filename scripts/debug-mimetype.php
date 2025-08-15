<?php
@ini_set('memory_limit','512M');
require __DIR__ . '/../nextcloud/lib/base.php';
$server = \OC::$server;
$rootFolder = $server->getRootFolder();
$userFolder = $server->getUserFolder('admin');
$local = __DIR__ . '/../tests/assets/cache/hasselblad_cf132.3FR';
if (!file_exists($local)) { fwrite(STDERR,"Missing asset file\n"); exit(1);} 
$data=file_get_contents($local);
$file=$userFolder->newFile('hasselblad_cf132.3FR',$data);
$mimetype = $file->getMimeType();
echo "Detected MIME: $mimetype\n";
