<?php
define('GATE_LICENCE_CONTRACT', '0x2Bdf3cB9138F3Ef71DD6A83aB24eA25DD540B974');
define('GATE_SECRET', 'replace-with-a-long-random-string');
define('GATE_LINK_TTL', 600);
define('GATE_CODE_MAX_USES', 1);
define('GATE_PURPOSES', ['Download my licensed files']);
define('GATE_FILES_DIR', '/home/USER/private_downloads');
define('GATE_FILES', [
    1 => 'product-1.zip',
    2 => ['en' => 'album-en.zip', 'zh' => 'album-zh.zip'],
    3 => 'https://example.com/private-link-to-large-file',
]);
define('BOOKING_EMAIL', 'you@example.com');
define('BOOKING_FROM', 'bookings@example.com');
