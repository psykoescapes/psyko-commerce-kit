<?php

header('Content-Type: application/json'); header('Cache-Control: no-store');
require_once __DIR__ . '/gate_config.php';
require_once __DIR__ . '/eip712_gate.php';
try {
    $in = json_decode((string)file_get_contents('php://input'), true) ?: [];
    $r = gate_verify((string)($in['nonce'] ?? ''), (string)($in['signature'] ?? ''), GATE_LICENCE_CONTRACT);
    if (!$r['ok']) { http_response_code(403); echo json_encode($r); exit; }
    echo json_encode(['ok' => true] + gate_download_link($r['licence'], $r['wallet']));
} catch (Throwable $e) {
    http_response_code(500); echo json_encode(['ok' => false, 'error' => 'Server error. Please try again.']);
}
