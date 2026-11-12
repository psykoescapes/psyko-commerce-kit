<?php

require_once __DIR__ . '/gate_config.php';
require_once __DIR__ . '/eip712_gate.php';
header('Cache-Control: no-store, private');
header('X-Robots-Tag: noindex, nofollow');
header('Referrer-Policy: no-referrer');

$r = gate_take_download((string)($_GET['t'] ?? ''));
if (!$r['ok']) { http_response_code($r['code']); exit($r['error']); }

$entry = GATE_FILES[$r['licence']] ?? null;
if (is_array($entry)) {
    $lang = (string)($_GET['lang'] ?? 'en');
    $entry = $entry[$lang] ?? $entry['en'] ?? reset($entry);
}
if (!is_string($entry) || $entry === '') { http_response_code(404); exit('File not found.'); }
if (preg_match('#^https?://#i', $entry)) {
    if (defined('GATE_ALLOW_REMOTE') && GATE_ALLOW_REMOTE) { header('Location: ' . $entry, true, 302); exit; }
    http_response_code(500); exit('This product is not configured for private delivery yet.');
}
if (strncmp($entry, 's3:', 3) === 0) {
    if (!defined('GATE_S3') || !is_array(GATE_S3)) { http_response_code(500); exit('Storage is not configured.'); }
    $key = ltrim(substr($entry, 3), '/');
    header('Location: ' . gate_s3_presign(GATE_S3, $key, (int)(GATE_S3['link_ttl'] ?? 120), basename($key)), true, 302);
    exit;
}

$base = realpath(GATE_FILES_DIR);
$path = realpath(GATE_FILES_DIR . '/' . $entry);
if (!$base || !$path || strpos($path, rtrim($base, '/') . '/') !== 0 || !is_file($path) || !is_readable($path)) {
    http_response_code(404); exit('File not found.');
}

$size = filesize($path);
$start = 0; $end = $size - 1;
if (isset($_SERVER['HTTP_RANGE']) && preg_match('/^bytes=(\d*)-(\d*)$/', $_SERVER['HTTP_RANGE'], $m)) {
    if ($m[1] === '' && $m[2] !== '') { $start = max(0, $size - (int)$m[2]); }
    else { $start = (int)$m[1]; if ($m[2] !== '') $end = min($end, (int)$m[2]); }
    if ($start > $end || $start >= $size) { http_response_code(416); header("Content-Range: bytes */$size"); exit; }
    http_response_code(206);
    header("Content-Range: bytes $start-$end/$size");
}
$name = basename($path);
header('Content-Type: application/octet-stream');
header('Content-Disposition: attachment; filename="' . str_replace('"', '', $name) . '"; filename*=UTF-8\'\'' . rawurlencode($name));
header('Accept-Ranges: bytes');
header('Content-Length: ' . ($end - $start + 1));
header('X-Content-Type-Options: nosniff');

@set_time_limit(0);
while (ob_get_level()) ob_end_clean();
$fh = fopen($path, 'rb');
fseek($fh, $start);
$left = $end - $start + 1;
while ($left > 0 && !feof($fh) && !connection_aborted()) {
    $chunk = fread($fh, (int)min(1048576, $left));
    if ($chunk === false) break;
    echo $chunk; flush();
    $left -= strlen($chunk);
}
fclose($fh);
