<?php

header('Content-Type: application/json'); header('Cache-Control: no-store');
require_once __DIR__ . '/gate_config.php';
require_once __DIR__ . '/eip712_gate.php';
try {
    $in = json_decode((string)file_get_contents('php://input'), true) ?: [];
    $wallet = (string)($in['wallet'] ?? ''); $licence = (int)($in['licence'] ?? 0); $purpose = (string)($in['purpose'] ?? '');
    if (!gate_is_address($wallet)) throw new InvalidArgumentException('Connect a wallet first.');
    if (!isset(GATE_FILES[$licence])) throw new InvalidArgumentException('Unknown product.');
    if (!in_array($purpose, GATE_PURPOSES, true)) $purpose = GATE_PURPOSES[0];
    echo json_encode(['ok' => true, 'typedData' => gate_typed_data(gate_new_challenge($wallet, $licence, $purpose))]);
} catch (Throwable $e) {
    http_response_code(400); echo json_encode(['ok' => false, 'error' => $e->getMessage()]);
}
