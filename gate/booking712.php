<?php
header('Content-Type: application/json'); header('Cache-Control: no-store');
require_once __DIR__ . '/gate_config.php';
require_once __DIR__ . '/eip712_gate.php';
if (!defined('BOOKING_EMAIL')) define('BOOKING_EMAIL', '');
if (!defined('BOOKING_FROM'))  define('BOOKING_FROM',  '');
if (!defined('STORE_ADDRESS')) define('STORE_ADDRESS', '0x64f2cddd7fd2d8e2ffe8dfe99b30a95678d63c10');
if (!defined('STORE_PURCHASE_TOPIC')) define('STORE_PURCHASE_TOPIC', '0x25a570ce761a2543679d9f736465aec7816f43f2abd6e35d61dbd3dd9186d957');
const BOOKING_PRODUCTS = ['stream-booking' => 2, 'kmxi-ticket' => 11];

function bk_rpc(string $method, array $params) {
    return gate_rpc($method, $params);
}

function bk_verify(string $tx, string $orderRef, int $productId, string $wallet, int $qty): string {
    $rcpt = null;
    for ($i = 0; $i < 6 && !$rcpt; $i++) { $rcpt = bk_rpc('eth_getTransactionReceipt', [$tx]); if (!$rcpt) sleep(3); }
    if (!$rcpt) return 'pending';
    if (($rcpt['status'] ?? '') !== '0x1') return 'failed';
    if ($wallet !== '' && strtolower($rcpt['from'] ?? '') !== strtolower($wallet)) return 'mismatch';
    foreach ($rcpt['logs'] ?? [] as $l) {
        if (strtolower($l['address'] ?? '') !== STORE_ADDRESS) continue;
        $t = $l['topics'] ?? [];
        if (count($t) < 4 || strtolower($t[0]) !== STORE_PURCHASE_TOPIC) continue;
        if (hexdec(substr($t[3], -16)) !== $productId) continue;
        $d = substr((string)$l['data'], 2);
        if (strlen($d) < 256) continue;
        $logQty = hexdec(substr($d, 48, 16));
        $logRef = '0x' . substr($d, 192, 64);
        if ($orderRef !== '' && strtolower($logRef) !== strtolower($orderRef)) continue;
        if ($qty > 0 && $logQty !== $qty) continue;
        return 'paid';
    }
    return 'mismatch';
}

try {
    if (!is_dir(GATE_NONCE_DIR)) mkdir(GATE_NONCE_DIR, 0700, true);
    if (!gate_rate_ok(10)) throw new InvalidArgumentException('Too many requests.');
    $in = json_decode((string)file_get_contents('php://input'), true) ?: [];
    $clean = fn($v, $n = 120) => mb_substr(trim(preg_replace('/[\x00-\x1f\x7f]/u', '', (string)$v)), 0, $n);
    $kind = $clean($in['kind'] ?? '', 30);
    $b = ['received' => gmdate('c'),
          'kind' => isset(BOOKING_PRODUCTS[$kind]) ? $kind : 'stream-booking',
          'event' => $clean($in['event'] ?? '', 60),
          'tx' => $clean($in['tx'] ?? '', 80), 'orderRef' => $clean($in['orderRef'] ?? '', 80),
          'wallet' => $clean($in['wallet'] ?? '', 50), 'email' => $clean($in['email'] ?? ''), 'date' => $clean($in['date'] ?? '', 20),
          'time' => $clean($in['time'] ?? '', 20), 'hours' => max(0, min(24, (int)($in['hours'] ?? 0)))];
    if (!preg_match('/^0x[0-9a-fA-F]{64}$/', $b['tx'])) throw new InvalidArgumentException('Missing payment.');
    if ($b['orderRef'] !== '' && !preg_match('/^0x[0-9a-fA-F]{64}$/', $b['orderRef'])) throw new InvalidArgumentException('Bad order reference.');
    if (!filter_var($b['email'], FILTER_VALIDATE_EMAIL)) throw new InvalidArgumentException('Bad email.');
    if ($b['wallet'] !== '' && !preg_match('/^0x[0-9a-fA-F]{40}$/', $b['wallet'])) throw new InvalidArgumentException('Bad wallet.');

    $file = GATE_NONCE_DIR . '/bookings.jsonl';
    if (is_file($file) && stripos((string)file_get_contents($file), $b['tx']) !== false) {
        echo json_encode(['ok' => true, 'dup' => true]); exit;
    }

    $qty = $b['kind'] === 'kmxi-ticket' ? 1 : $b['hours'];
    try { $b['payment'] = bk_verify($b['tx'], $b['orderRef'], BOOKING_PRODUCTS[$b['kind']], $b['wallet'], $qty); }
    catch (RuntimeException $e) { $b['payment'] = 'pending'; }
    if ($b['payment'] === 'failed' || $b['payment'] === 'mismatch') throw new InvalidArgumentException('Payment not found for this order.');

    file_put_contents($file, json_encode($b, JSON_UNESCAPED_SLASHES) . "\n", FILE_APPEND | LOCK_EX);

    if (BOOKING_EMAIL) {
        $flag = $b['payment'] === 'paid' ? '' : '[UNVERIFIED - check tx] ';
        if ($b['kind'] === 'kmxi-ticket') {
            $subject = $flag . 'KM XI ticket sold - ' . $b['email'];
            $body = "New Karacus Marakus XI ticket (29 Jan - 2 Feb 2027, Thailand)\n\n"
                  . "Buyer email:  {$b['email']}\nBuyer wallet: {$b['wallet']}\n"
                  . "Payment:      https://bscscan.com/tx/{$b['tx']} ({$b['payment']})\nOrder ref:    {$b['orderRef']}\n\n"
                  . "After the 5th ticket, call setActive(11, false) on the PSYKO Store.\n";
        } else {
            $subject = $flag . 'New stream booking: ' . $b['hours'] . 'h on ' . $b['date'];
            $body = "Email: {$b['email']}\nDate: {$b['date']} {$b['time']}\nHours: {$b['hours']}\n"
                  . "Wallet: {$b['wallet']}\nPayment: https://bscscan.com/tx/{$b['tx']} ({$b['payment']})\n";
        }
        $headers = "From: PSYKO Bookings <" . BOOKING_FROM . ">\r\nReply-To: {$b['email']}\r\nContent-Type: text/plain; charset=UTF-8\r\n";
        @mail(BOOKING_EMAIL, $subject, $body, $headers, '-f' . BOOKING_FROM);
    }
    echo json_encode(['ok' => true, 'payment' => $b['payment']]);
} catch (InvalidArgumentException $e) {
    http_response_code(400); echo json_encode(['ok' => false, 'error' => $e->getMessage()]);
} catch (Throwable $e) {
    http_response_code(500); echo json_encode(['ok' => false, 'error' => 'Server error. Please try again.']);
}
