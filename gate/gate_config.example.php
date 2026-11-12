<?php
// Copy to /home/USER/psyko_private/gate_config.php (NOT inside public_html).
define('GATE_LICENCE_CONTRACT', '0x2Bdf3cB9138F3Ef71DD6A83aB24eA25DD540B974');
// Make a new secret once: php -r "echo bin2hex(random_bytes(32));"   Never commit it, never reuse it.
define('GATE_SECRET', 'replace-with-64-random-hex-characters');
define('GATE_LINK_TTL', 300);          // a download link works for 5 minutes...
define('GATE_LINK_MAX_USES', 3);       // ...and can be opened at most 3 times (resume / retry)
define('GATE_CODE_MAX_USES', 1);
define('GATE_PURPOSES', ['Download my licensed files']);
define('GATE_NONCE_DIR', '/home/USER/psyko_private/gate_nonces');
define('GATE_FILES_DIR', '/home/USER/psyko_private/downloads');   // files here are never reachable by URL
define('GATE_FILES', [
    1001 => 'debut-2005.zip',
    1002 => ['en' => 'album-en.zip', 'zh' => 'album-zh.zip'],
]);
// Large files can live in a private S3-compatible bucket (e.g. Cloudflare R2) instead of GATE_FILES_DIR.
// Use 's3:<object key>' in GATE_FILES; the gate answers with a presigned link that expires after link_ttl seconds.
// Give the gate a READ-ONLY key for that one bucket.
define('GATE_S3', [
    'endpoint'   => 'https://<account-id>.r2.cloudflarestorage.com',
    'region'     => 'auto',
    'bucket'     => 'my-private-bucket',
    'access_key' => 'read-only-access-key-id',
    'secret_key' => 'read-only-secret-access-key',
    'link_ttl'   => 120,
]);
// define('GATE_FILES', [ 1003 => 's3:My Album.zip' ]);
define('BOOKING_EMAIL', 'you@example.com');
define('BOOKING_FROM', 'bookings@example.com');
