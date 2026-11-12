<?php

require_once __DIR__ . '/gate_config.php';
$t = base64_decode((string)($_GET['t'] ?? ''), true);
$parts = $t === false ? [] : explode('.', $t);
if (count($parts) !== 4) { http_response_code(400); exit('Bad link.'); }
[$licence, $who, $exp, $sig] = $parts;
$payload = "$licence.$who.$exp";
if (!hash_equals(hash_hmac('sha256', $payload, GATE_SECRET), $sig)) { http_response_code(403); exit('Bad link.'); }
if (time() > (int)$exp) { http_response_code(410); exit('This link expired. Please sign in again on the product page.'); }
$entry = GATE_FILES[(int)$licence] ?? null;
if (is_array($entry)) {
    $lang = (string)($_GET['lang'] ?? 'en');
    $entry = $entry[$lang] ?? $entry['en'] ?? reset($entry);
}
if (!$entry) { http_response_code(404); exit('File not found.'); }
header('Cache-Control: no-store');
if (preg_match('#^https://#', $entry)) { header('Location: ' . $entry, true, 302); exit; }
$path = realpath(GATE_FILES_DIR . '/' . $entry);
$base = rtrim((string)realpath(GATE_FILES_DIR), '/') . '/';
if (!$path || $base === '/' || strpos($path, $base) !== 0 || !is_file($path)) { http_response_code(404); exit('File not found.'); }
header('Content-Type: application/octet-stream');
header('Content-Disposition: attachment; filename="' . basename($path) . '"');
header('Content-Length: ' . filesize($path));
readfile($path);
