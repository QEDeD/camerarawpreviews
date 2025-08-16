<?php
declare(strict_types=1);

// Simple JSON linter for one or more files. Exits non-zero on any error.
// Usage: php scripts/lint-json.php <file> [more files...]

$paths = $argv;
array_shift($paths);
if (!$paths) {
    fwrite(STDERR, "Usage: php scripts/lint-json.php <files...>\n");
    exit(2);
}

$rc = 0;
foreach ($paths as $p) {
    if (!is_file($p)) {
        fwrite(STDERR, "Not a file: $p\n");
        $rc = 1;
        continue;
    }
    $data = file_get_contents($p);
    if ($data === false) {
        fwrite(STDERR, "Cannot read: $p\n");
        $rc = 1;
        continue;
    }
    json_decode($data);
    if (json_last_error() !== JSON_ERROR_NONE) {
        fwrite(STDERR, "$p: " . json_last_error_msg() . "\n");
        $rc = 1;
    } else {
        fwrite(STDOUT, "$p: OK\n");
    }
}

exit($rc);
