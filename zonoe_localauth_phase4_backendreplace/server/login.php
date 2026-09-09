<?php
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
header('Pragma: no-cache');

$COMPAT = isset($_GET['compat']) && $_GET['compat'] === 'pandora';

function reply_json($ok, $message, $data = array(), $status = 200) {
    global $COMPAT;
    http_response_code($status);
    $base = array('ok' => $ok ? true : false, 'message' => $message);
    if ($COMPAT) {
        $base['result'] = $ok ? 1 : 0;
        $base['msg'] = $message;
        $base['data'] = $data;
    } else {
        $base = array_merge($base, $data);
    }
    echo json_encode($base, JSON_UNESCAPED_UNICODE);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') reply_json(false, 'METHOD_NOT_ALLOWED', array(), 405);
$raw = file_get_contents('php://input');
$input = array();
$contentType = isset($_SERVER['CONTENT_TYPE']) ? $_SERVER['CONTENT_TYPE'] : '';
if (stripos($contentType, 'application/json') !== false) {
    $decoded = json_decode($raw, true);
    if (is_array($decoded)) $input = $decoded;
} else {
    $input = $_POST;
    if (!$input && $raw !== '') parse_str($raw, $input);
}

$username = '';
if (isset($input['username'])) $username = trim((string)$input['username']);
elseif (isset($input['uname'])) $username = trim((string)$input['uname']);
elseif (isset($input['account'])) $username = trim((string)$input['account']);
$password = isset($input['password']) ? (string)$input['password'] : '';

if ($username === '' || $password === '') reply_json(false, 'ACCOUNT_OR_PASSWORD_EMPTY');
if (strlen($username) > 64 || strlen($password) > 64) reply_json(false, 'ACCOUNT_OR_PASSWORD_INVALID');

$DB_HOST = '127.0.0.1';
$DB_PORT = 3306;
$DB_NAME = 'db_adv_login';
$DB_USER = 'CHANGE_ME';
$DB_PASS = 'CHANGE_ME';
if ($DB_USER === 'CHANGE_ME' || $DB_PASS === 'CHANGE_ME') reply_json(false, 'DB_CONFIG_REQUIRED', array(), 500);

$mysqli = @new mysqli($DB_HOST, $DB_USER, $DB_PASS, $DB_NAME, $DB_PORT);
if ($mysqli->connect_errno) reply_json(false, 'DB_CONNECT_FAILED', array(), 500);
if (!$mysqli->set_charset('utf8mb4')) reply_json(false, 'DB_CHARSET_FAILED', array(), 500);

$stmt = $mysqli->prepare('SELECT id, account, password, robot, last_server, channel, seal_end_time, create_time FROM t_tb_account WHERE account = ? LIMIT 1');
if (!$stmt) reply_json(false, 'DB_PREPARE_FAILED', array(), 500);
$stmt->bind_param('s', $username);
if (!$stmt->execute()) reply_json(false, 'DB_QUERY_FAILED', array(), 500);
$stmt->store_result();
if ($stmt->num_rows < 1) reply_json(false, 'ACCOUNT_NOT_FOUND');
$stmt->bind_result($id, $account, $storedPassword, $robot, $lastServer, $channel, $sealEndTime, $createTime);
$stmt->fetch();
$stmt->close();

if ((string)$storedPassword !== $password) reply_json(false, 'PASSWORD_INVALID');
$seal = (string)$sealEndTime;
if ($seal !== '' && $seal !== '0000-00-00 00:00:00') {
    $sealTs = strtotime($seal);
    if ($sealTs !== false && $sealTs > time()) reply_json(false, 'ACCOUNT_DISABLED');
}

$seed = uniqid('', true) . mt_rand() . $id . microtime(true);
$gameToken = hash('sha256', 'gt:' . $seed);
$sessId = hash('sha256', 'sid:' . $seed);
$now = (string)time();

$data = array(
    'account_id' => (int)$id,
    'account' => (string)$account,
    'last_server' => $lastServer === null ? null : (int)$lastServer,
    'channel' => $channel === null ? null : (string)$channel,
    'robot' => (bool)$robot,
    'create_time' => (string)$createTime,
    /* Pandora-compatible fields. */
    'uid' => (string)$id,
    'uname' => (string)$account,
    'username' => (string)$account,
    'gametoken' => $gameToken,
    'sessid' => $sessId,
    'time' => $now
);
reply_json(true, 'AUTH_OK', $data);
