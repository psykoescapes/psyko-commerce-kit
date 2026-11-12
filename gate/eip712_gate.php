<?php

if (!defined('GATE_RPC_URLS'))  define('GATE_RPC_URLS', ['https://bsc-dataseed.bnbchain.org', 'https://bsc-dataseed1.defibit.io', 'https://bsc-rpc.publicnode.com']);
if (!defined('GATE_CHAIN_ID'))  define('GATE_CHAIN_ID', 56);
if (!defined('GATE_DOMAIN'))    define('GATE_DOMAIN', 'psykovsky.com Downloads');
if (!defined('GATE_VERSION'))   define('GATE_VERSION', '1');
if (!defined('GATE_TTL'))       define('GATE_TTL', 300);
if (!defined('GATE_NONCE_DIR')) define('GATE_NONCE_DIR', dirname(__DIR__, 2) . '/psyko_private/gate_nonces');
if (!defined('GATE_LINK_TTL'))  define('GATE_LINK_TTL', 300);
if (!defined('GATE_LINK_MAX_USES')) define('GATE_LINK_MAX_USES', 3);

function keccak256(string $data): string
{
    static $rc = null, $rot = [1,3,6,10,15,21,28,36,45,55,2,14,27,41,56,8,25,43,62,18,39,61,20,44];
    static $pi = [10,7,11,17,18,3,5,16,8,21,24,4,15,23,19,13,12,2,20,14,22,9,6,1];
    if ($rc === null) {
        $rc = [];
        foreach (['0000000000000001','0000000000008082','800000000000808A','8000000080008000','000000000000808B',
                  '0000000080000001','8000000080008081','8000000000008009','000000000000008A','0000000000000088',
                  '0000000080008009','000000008000000A','000000008000808B','800000000000008B','8000000000008089',
                  '8000000000008003','8000000000008002','8000000000000080','000000000000800A','800000008000000A',
                  '8000000080008081','8000000000008080','0000000080000001','8000000080008008'] as $h) {
            $rc[] = unpack('J', hex2bin($h))[1];
        }
    }
    $rotl = static function (int $x, int $n): int {
        if ($n === 0) return $x;

        $right = ($x >> (64 - $n)) & ((1 << $n) - 1);
        return ($x << $n) | $right;
    };
    $rate = 136;
    $data .= "\x01";
    $data .= str_repeat("\x00", ($rate - strlen($data) % $rate) % $rate);
    $data[strlen($data) - 1] = chr(ord($data[strlen($data) - 1]) | 0x80);
    $s = array_fill(0, 25, 0);
    for ($off = 0, $len = strlen($data); $off < $len; $off += $rate) {
        for ($i = 0; $i < 17; ++$i) $s[$i] ^= unpack('P', substr($data, $off + 8 * $i, 8))[1];
        for ($round = 0; $round < 24; ++$round) {
            $c = [];
            for ($x = 0; $x < 5; ++$x) $c[$x] = $s[$x] ^ $s[$x + 5] ^ $s[$x + 10] ^ $s[$x + 15] ^ $s[$x + 20];
            for ($x = 0; $x < 5; ++$x) {
                $d = $c[($x + 4) % 5] ^ $rotl($c[($x + 1) % 5], 1);
                for ($y = 0; $y < 25; $y += 5) $s[$y + $x] ^= $d;
            }
            $t = $s[1];
            for ($i = 0; $i < 24; ++$i) { $j = $pi[$i]; $tmp = $s[$j]; $s[$j] = $rotl($t, $rot[$i]); $t = $tmp; }
            for ($y = 0; $y < 25; $y += 5) {
                $r = [$s[$y], $s[$y + 1], $s[$y + 2], $s[$y + 3], $s[$y + 4]];
                for ($x = 0; $x < 5; ++$x) $s[$y + $x] = $r[$x] ^ ((~$r[($x + 1) % 5]) & $r[($x + 2) % 5]);
            }
            $s[0] ^= $rc[$round];
        }
    }
    $out = '';
    for ($i = 0; $i < 4; ++$i) $out .= pack('P', $s[$i]);
    return $out;
}

function gate_u256(int $v): string { return str_pad(pack('J', $v), 32, "\x00", STR_PAD_LEFT); }
function gate_addr(string $a): string { return str_pad(hex2bin(substr(strtolower($a), 2)), 32, "\x00", STR_PAD_LEFT); }
function gate_is_address(string $a): bool { return (bool)preg_match('/^0x[0-9a-fA-F]{40}$/', $a); }

const GATE_TYPE_DOWNLOAD = 'Download(string purpose,address wallet,uint256 licence,string nonce,uint256 expires)';
const GATE_TYPE_DOMAIN   = 'EIP712Domain(string name,string version,uint256 chainId)';

function gate_domain_separator(): string {
    return keccak256(keccak256(GATE_TYPE_DOMAIN) . keccak256(GATE_DOMAIN) . keccak256(GATE_VERSION) . gate_u256(GATE_CHAIN_ID));
}

function gate_digest(array $m): string {
    $struct = keccak256(keccak256(GATE_TYPE_DOWNLOAD) . keccak256($m['purpose']) . gate_addr($m['wallet'])
            . gate_u256((int)$m['licence']) . keccak256($m['nonce']) . gate_u256((int)$m['expires']));
    return keccak256("\x19\x01" . gate_domain_separator() . $struct);
}

function gate_typed_data(array $m): array {
    return [
        'types' => [
            'EIP712Domain' => [['name'=>'name','type'=>'string'],['name'=>'version','type'=>'string'],['name'=>'chainId','type'=>'uint256']],
            'Download' => [['name'=>'purpose','type'=>'string'],['name'=>'wallet','type'=>'address'],['name'=>'licence','type'=>'uint256'],
                           ['name'=>'nonce','type'=>'string'],['name'=>'expires','type'=>'uint256']],
        ],
        'primaryType' => 'Download',
        'domain'  => ['name'=>GATE_DOMAIN, 'version'=>GATE_VERSION, 'chainId'=>GATE_CHAIN_ID],
        'message' => ['purpose'=>$m['purpose'], 'wallet'=>$m['wallet'], 'licence'=>(string)$m['licence'],
                      'nonce'=>$m['nonce'], 'expires'=>(string)$m['expires']],
    ];
}

function gate_rpc(string $method, array $params) {
    $body = json_encode(['jsonrpc'=>'2.0','id'=>1,'method'=>$method,'params'=>$params]);
    foreach (GATE_RPC_URLS as $url) {
        $ch = curl_init($url);
        curl_setopt_array($ch, [CURLOPT_POST=>true, CURLOPT_POSTFIELDS=>$body, CURLOPT_RETURNTRANSFER=>true,
            CURLOPT_TIMEOUT=>8, CURLOPT_HTTPHEADER=>['Content-Type: application/json']]);
        $raw = curl_exec($ch); curl_close($ch);
        $res = $raw ? json_decode($raw, true) : null;
        if (is_array($res) && array_key_exists('result', $res)) return $res['result'];
    }
    throw new RuntimeException('All BSC RPC endpoints failed');
}

function gate_call_agreed(array $tx) {
    $answers = [];
    foreach (GATE_RPC_URLS as $url) {
        $body = json_encode(['jsonrpc'=>'2.0','id'=>1,'method'=>'eth_call','params'=>[$tx, 'latest']]);
        $ch = curl_init($url);
        curl_setopt_array($ch, [CURLOPT_POST=>true, CURLOPT_POSTFIELDS=>$body, CURLOPT_RETURNTRANSFER=>true,
            CURLOPT_TIMEOUT=>8, CURLOPT_HTTPHEADER=>['Content-Type: application/json']]);
        $raw = curl_exec($ch); curl_close($ch);
        $res = $raw ? json_decode($raw, true) : null;
        if (is_array($res) && isset($res['result']) && is_string($res['result'])) $answers[] = strtolower($res['result']);
        if (count($answers) >= min(2, count(GATE_RPC_URLS))) break;
    }
    if (count($answers) < min(2, count(GATE_RPC_URLS))) throw new RuntimeException('BSC RPC endpoints unavailable');
    if (count(array_unique($answers)) !== 1) throw new RuntimeException('BSC RPC endpoints disagree');
    return $answers[0];
}

function gate_recover(string $digest, string $sigHex): ?string {
    $sig = hex2bin(preg_replace('/^0x/', '', $sigHex));
    if ($sig === false || strlen($sig) !== 65) return null;
    $r = substr($sig, 0, 32); $s = substr($sig, 32, 32); $v = ord($sig[64]);
    if ($v < 27) $v += 27;
    if ($v !== 27 && $v !== 28) return null;

    if (strcmp(bin2hex($s), '7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0') > 0) return null;
    $input = '0x' . bin2hex($digest . gate_u256($v) . $r . $s);
    $out = gate_call_agreed(['to'=>'0x0000000000000000000000000000000000000001', 'data'=>$input]);
    if (!is_string($out) || strlen($out) < 66) return null;
    $addr = '0x' . substr($out, -40);
    return $addr === '0x' . str_repeat('0', 40) ? null : strtolower($addr);
}

function gate_licence_balance(string $licenceContract, string $wallet, int $id): int {
    $data = '0x00fdd58e' . bin2hex(gate_addr($wallet) . gate_u256($id));
    $out = gate_call_agreed(['to'=>$licenceContract, 'data'=>$data]);
    return (int)hexdec(substr($out, -16));
}

function gate_sweep(): void {
    if (random_int(1, 20) !== 1 || !is_dir(GATE_NONCE_DIR)) return;
    $limit = time() - 2 * GATE_TTL;
    foreach (glob(GATE_NONCE_DIR . '/*.json') ?: [] as $f) if (@filemtime($f) < $limit) @unlink($f);
    foreach (glob(GATE_NONCE_DIR . '/rate_*') ?: [] as $f) if (@filemtime($f) < time() - 120) @unlink($f);
    foreach (glob(GATE_NONCE_DIR . '/dl_*') ?: [] as $f) if (@filemtime($f) < time() - 2 * GATE_LINK_TTL) @unlink($f);
}

function gate_rate_ok(int $max = 20): bool {
    $ip = $_SERVER['REMOTE_ADDR'] ?? 'cli';
    $f = GATE_NONCE_DIR . '/rate_' . hash('sha256', $ip . date('YmdHi'));
    $n = (int)@file_get_contents($f) + 1;
    file_put_contents($f, (string)$n, LOCK_EX);
    return $n <= $max;
}

function gate_new_challenge(string $wallet, int $licence, string $purpose): array {
    if (!gate_is_address($wallet)) throw new InvalidArgumentException('bad wallet');
    gate_private_dir(GATE_NONCE_DIR);
    gate_sweep();
    if (!gate_rate_ok()) throw new InvalidArgumentException('Too many attempts. Wait a minute and try again.');
    $nonce = bin2hex(random_bytes(16));
    $m = ['purpose'=>$purpose, 'wallet'=>strtolower($wallet), 'licence'=>$licence, 'nonce'=>$nonce, 'expires'=>time() + GATE_TTL];
    file_put_contents(GATE_NONCE_DIR . "/$nonce.json", json_encode($m), LOCK_EX);
    return $m;
}

function gate_take_challenge(string $nonce): ?array {
    if (!preg_match('/^[0-9a-f]{32}$/', $nonce)) return null;
    $f = GATE_NONCE_DIR . "/$nonce.json";
    if (!is_file($f)) return null;
    $tmp = $f . '.' . bin2hex(random_bytes(4));
    if (!@rename($f, $tmp)) return null;
    $m = json_decode((string)file_get_contents($tmp), true); @unlink($tmp);
    if (!is_array($m) || time() > (int)$m['expires']) return null;
    return $m;
}

function gate_verify(string $nonce, string $signature, string $licenceContract): array {
    $m = gate_take_challenge($nonce);
    if ($m === null) return ['ok'=>false, 'error'=>'Challenge expired or already used. Please try again.'];
    $signer = gate_recover(gate_digest($m), $signature);
    if ($signer === null || $signer !== strtolower($m['wallet'])) return ['ok'=>false, 'error'=>'Signature does not match this wallet.'];
    if (gate_licence_balance($licenceContract, $m['wallet'], (int)$m['licence']) < 1)
        return ['ok'=>false, 'error'=>'This wallet does not hold the licence.'];
    return ['ok'=>true, 'wallet'=>$m['wallet'], 'licence'=>(int)$m['licence']];
}

function gate_private_dir(string $dir): void {
    if (!is_dir($dir)) mkdir($dir, 0700, true);
    if (!is_file($dir . '/.htaccess')) @file_put_contents($dir . '/.htaccess', "Require all denied\nOptions -Indexes\n");
}

/// A download link is signed, tied to one wallet and one product, valid for GATE_LINK_TTL seconds,
/// and can be opened at most GATE_LINK_MAX_USES times (so an interrupted download can resume, but
/// a shared link stops working almost at once).
function gate_download_link(int $licence, string $who): array {
    $exp = time() + GATE_LINK_TTL;
    $jti = bin2hex(random_bytes(12));
    $payload = $licence . '.' . str_replace('.', '', $who) . '.' . $exp . '.' . $jti;
    $sig = hash_hmac('sha256', $payload, GATE_SECRET);
    return ['url' => 'download712.php?t=' . rawurlencode(base64_encode($payload . '.' . $sig)), 'expires' => $exp];
}

function gate_take_download(string $token): array {
    $t = base64_decode($token, true);
    $p = $t === false ? [] : explode('.', $t);
    if (count($p) !== 5) return ['ok' => false, 'code' => 400, 'error' => 'Bad link.'];
    [$licence, $who, $exp, $jti, $sig] = $p;
    if (!preg_match('/^[0-9a-f]{24}$/', $jti) || !preg_match('/^\d+$/', $licence . $exp)) return ['ok' => false, 'code' => 400, 'error' => 'Bad link.'];
    if (!hash_equals(hash_hmac('sha256', "$licence.$who.$exp.$jti", GATE_SECRET), $sig)) return ['ok' => false, 'code' => 403, 'error' => 'Bad link.'];
    if (time() > (int)$exp) return ['ok' => false, 'code' => 410, 'error' => 'This link expired. Please sign in again on the album page.'];
    gate_private_dir(GATE_NONCE_DIR);
    $f = fopen(GATE_NONCE_DIR . "/dl_$jti", 'c+');
    flock($f, LOCK_EX);
    $n = (int)stream_get_contents($f) + 1;
    ftruncate($f, 0); rewind($f); fwrite($f, (string)$n); fflush($f);
    flock($f, LOCK_UN); fclose($f);
    if ($n > GATE_LINK_MAX_USES) return ['ok' => false, 'code' => 410, 'error' => 'This link was already used. Please sign in again on the album page.'];
    return ['ok' => true, 'licence' => (int)$licence, 'who' => $who];
}

/// Presigned GET link for a private S3-compatible bucket (Cloudflare R2, IBM COS, Backblaze B2, AWS S3...).
/// AWS Signature V4, query-string form. The link stops working after $ttl seconds.
function gate_s3_uri(string $s): string { return str_replace('%7E', '~', rawurlencode($s)); }
function gate_s3_presign(array $c, string $key, int $ttl, ?string $filename = null, ?int $now = null): string {
    $now = $now ?? time();
    $amzDate = gmdate('Ymd\THis\Z', $now); $day = gmdate('Ymd', $now);
    $region = $c['region'] ?? 'auto';
    $ep = parse_url($c['endpoint']);
    $virtual = !empty($c['virtual_host']);
    $host = $virtual ? $c['bucket'] . '.' . $ep['host'] : $ep['host'];
    $path = ($virtual ? '' : '/' . gate_s3_uri($c['bucket'])) . '/' . implode('/', array_map('gate_s3_uri', explode('/', $key)));
    $scope = "$day/$region/s3/aws4_request";
    $q = ['X-Amz-Algorithm' => 'AWS4-HMAC-SHA256', 'X-Amz-Credential' => $c['access_key'] . '/' . $scope,
          'X-Amz-Date' => $amzDate, 'X-Amz-Expires' => (string)$ttl, 'X-Amz-SignedHeaders' => 'host'];
    if ($filename !== null) $q['response-content-disposition'] = 'attachment; filename="' . str_replace('"', '', $filename) . '"; filename*=UTF-8\'\'' . rawurlencode($filename);
    ksort($q, SORT_STRING);
    $qs = implode('&', array_map(fn($k, $v) => gate_s3_uri($k) . '=' . gate_s3_uri($v), array_keys($q), $q));
    $canon = "GET\n$path\n$qs\nhost:$host\n\nhost\nUNSIGNED-PAYLOAD";
    $sts = "AWS4-HMAC-SHA256\n$amzDate\n$scope\n" . hash('sha256', $canon);
    $k = hash_hmac('sha256', 'aws4_request', hash_hmac('sha256', 's3', hash_hmac('sha256', $region, hash_hmac('sha256', $day, 'AWS4' . $c['secret_key'], true), true), true), true);
    return ($ep['scheme'] ?? 'https') . "://$host$path?$qs&X-Amz-Signature=" . hash_hmac('sha256', $sts, $k);
}
