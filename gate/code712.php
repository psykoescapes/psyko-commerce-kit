<?php

header('Content-Type: application/json'); header('Cache-Control: no-store');
require_once __DIR__ . '/gate_config.php';
require_once __DIR__ . '/gate_codes.php';
require_once __DIR__ . '/eip712_gate.php';
try {
    if (!is_dir(GATE_NONCE_DIR)) mkdir(GATE_NONCE_DIR, 0700, true);
    if (!gate_rate_ok(10)) throw new InvalidArgumentException('Too many attempts. Wait a minute and try again.');
    $in = json_decode((string)file_get_contents('php://input'), true) ?: [];
    $code = strtoupper(preg_replace('/\s+/', '', (string)($in['code'] ?? '')));
    if (!isset(GATE_CODES[$code])) throw new InvalidArgumentException('Invalid coupon code.');

    $f = fopen(GATE_NONCE_DIR . '/codes_used.json', 'c+');
    flock($f, LOCK_EX);
    $used = json_decode((string)stream_get_contents($f), true) ?: [];
    $n = (int)($used[$code] ?? 0);
    if ($n >= GATE_CODE_MAX_USES) { flock($f, LOCK_UN); fclose($f); throw new InvalidArgumentException('This code has already been used.'); }
    $used[$code] = $n + 1;
    ftruncate($f, 0); rewind($f); fwrite($f, json_encode($used)); fflush($f);
    flock($f, LOCK_UN); fclose($f);
    $lic = GATE_CODES[$code];
    echo json_encode(['ok' => true, 'licence' => $lic, 'usesLeft' => GATE_CODE_MAX_USES - $n - 1] + gate_download_link($lic, 'code-' . $code));
} catch (InvalidArgumentException $e) {
    http_response_code(400); echo json_encode(['ok' => false, 'error' => $e->getMessage()]);
} catch (Throwable $e) {
    http_response_code(500); echo json_encode(['ok' => false, 'error' => 'Server error. Please try again.']);
}
