<?php
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

function out_json($ok, $message, $extra = array(), $status = 200) {
    http_response_code($status);
    echo json_encode(array_merge(array(
        'ok' => $ok ? true : false,
        'message' => $message
    ), $extra), JSON_UNESCAPED_UNICODE);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    out_json(false, 'METHOD_NOT_ALLOWED', array(), 405);
}

$raw = file_get_contents('php://input');
$input = array();
$contentType = isset($_SERVER['CONTENT_TYPE']) ? $_SERVER['CONTENT_TYPE'] : '';

if (stripos($contentType, 'application/json') !== false) {
    $decoded = json_decode($raw, true);
    if (is_array($decoded)) {
        $input = $decoded;
    }
} else {
    $input = $_POST;
    if (!$input && $raw !== '') {
        parse_str($raw, $input);
    }
}

$username = isset($input['username']) ? trim((string)$input['username']) : '';
$password = isset($input['password']) ? (string)$input['password'] : '';

if ($username === '' || $password === '') {
    out_json(false, 'ACCOUNT_OR_PASSWORD_EMPTY');
}

/*
 * Phase2 T3 test endpoint.
 * Fill these two values locally on the server. Do not commit real credentials.
 * Prefer a localhost-only MySQL user with SELECT on db_adv_login.t_tb_account.
 */
$DB_HOST = '127.0.0.1';
$DB_PORT = 3306;
$DB_NAME = 'db_adv_login';
$DB_USER = 'CHANGE_ME';
$DB_PASS = 'CHANGE_ME';

if ($DB_USER === 'CHANGE_ME' || $DB_PASS === 'CHANGE_ME') {
    out_json(false, 'DB_CONFIG_REQUIRED', array(), 500);
}

$mysqli = @new mysqli($DB_HOST, $DB_USER, $DB_PASS, $DB_NAME, $DB_PORT);
if ($mysqli->connect_errno) {
    out_json(false, 'DB_CONNECT_FAILED', array(), 500);
}

$mysqli->set_charset('utf8mb4');

$stmt = $mysqli->prepare(
    'SELECT id, account, password, last_server, channel, seal_end_time '
  . 'FROM t_tb_account WHERE account = ? LIMIT 1'
);
if (!$stmt) {
    out_json(false, 'DB_PREPARE_FAILED', array(), 500);
}

$stmt->bind_param('s', $username);
if (!$stmt->execute()) {
    out_json(false, 'DB_QUERY_FAILED', array(), 500);
}

$stmt->store_result();
if ($stmt->num_rows < 1) {
    out_json(false, 'ACCOUNT_NOT_FOUND');
}

$stmt->bind_result($id, $account, $storedPassword, $lastServer, $channel, $sealEndTime);
$stmt->fetch();

/* Existing test DB stores these passwords as plaintext. */
if ((string)$storedPassword !== $password) {
    out_json(false, 'PASSWORD_INVALID');
}

$seal = (string)$sealEndTime;
if ($seal !== '' && $seal !== '0000-00-00 00:00:00') {
    $sealTs = strtotime($seal);
    if ($sealTs !== false && $sealTs > time()) {
        out_json(false, 'ACCOUNT_DISABLED');
    }
}

/* T3 only proves local DB authentication. The client intentionally does not enter the game yet. */
out_json(true, 'ZONOE_T3_AUTH_OK', array(
    'account_id' => (int)$id,
    'account' => (string)$account,
    'last_server' => $lastServer === null ? null : (int)$lastServer,
    'channel' => $channel === null ? null : (string)$channel
));
