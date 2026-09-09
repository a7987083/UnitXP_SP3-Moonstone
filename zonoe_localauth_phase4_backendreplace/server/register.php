<?php
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
header('Pragma: no-cache');

$COMPAT = isset($_GET['compat']) && $_GET['compat'] === 'pandora';
function reply_json($ok, $message, $data = array(), $status = 200) {
    global $COMPAT;
    http_response_code($status);
    $out = array('ok' => $ok ? true : false, 'message' => $message);
    if ($COMPAT) {
        $out['result'] = $ok ? 1 : 0;
        $out['msg'] = $message;
        $out['data'] = $data;
    } else {
        $out = array_merge($out, $data);
    }
    echo json_encode($out, JSON_UNESCAPED_UNICODE);
    exit;
}
function release_id_lock($mysqli) {
    if ($mysqli) @$mysqli->query("SELECT RELEASE_LOCK('zonoe_auth_register_id')");
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
$channel = isset($input['channel']) ? trim((string)$input['channel']) : '';
if ($username === '' || $password === '') reply_json(false, 'ACCOUNT_OR_PASSWORD_EMPTY');
if (strlen($username) > 64 || strlen($password) > 64 || strlen($channel) > 64) reply_json(false, 'ACCOUNT_OR_PASSWORD_INVALID');

$DB_HOST = '127.0.0.1';
$DB_PORT = 3306;
$DB_NAME = 'db_adv_login';
$DB_USER = 'CHANGE_ME';
$DB_PASS = 'CHANGE_ME';
if ($DB_USER === 'CHANGE_ME' || $DB_PASS === 'CHANGE_ME') reply_json(false, 'DB_CONFIG_REQUIRED', array(), 500);

$mysqli = @new mysqli($DB_HOST, $DB_USER, $DB_PASS, $DB_NAME, $DB_PORT);
if ($mysqli->connect_errno) reply_json(false, 'DB_CONNECT_FAILED', array(), 500);
if (!$mysqli->set_charset('utf8mb4')) reply_json(false, 'DB_CHARSET_FAILED', array(), 500);

$lockResult = $mysqli->query("SELECT GET_LOCK('zonoe_auth_register_id', 5) AS locked");
if (!$lockResult) reply_json(false, 'ID_LOCK_FAILED', array(), 500);
$lockRow = $lockResult->fetch_assoc();
if (!isset($lockRow['locked']) || (int)$lockRow['locked'] !== 1) reply_json(false, 'ID_LOCK_TIMEOUT', array(), 503);

$stmt = $mysqli->prepare('SELECT id FROM t_tb_account WHERE account = ? LIMIT 1');
if (!$stmt) { release_id_lock($mysqli); reply_json(false, 'DB_PREPARE_FAILED', array(), 500); }
$stmt->bind_param('s', $username);
if (!$stmt->execute()) { release_id_lock($mysqli); reply_json(false, 'DB_QUERY_FAILED', array(), 500); }
$stmt->store_result();
if ($stmt->num_rows > 0) { $stmt->close(); release_id_lock($mysqli); reply_json(false, 'ACCOUNT_EXISTS'); }
$stmt->close();

$idResult = $mysqli->query('SELECT MAX(id) AS max_id FROM t_tb_account');
if (!$idResult) { release_id_lock($mysqli); reply_json(false, 'ID_QUERY_FAILED', array(), 500); }
$idRow = $idResult->fetch_assoc();
$maxId = isset($idRow['max_id']) && $idRow['max_id'] !== null ? (int)$idRow['max_id'] : 1048576;
$nextId = $maxId + 1;
if ($nextId <= 0 || $nextId > 4294967295) { release_id_lock($mysqli); reply_json(false, 'ID_RANGE_EXHAUSTED', array(), 500); }

$channelValue = ($channel === '') ? null : $channel;
$insert = $mysqli->prepare("INSERT INTO t_tb_account (id, account, password, robot, last_server, channel, seal_end_time, referrerid, id_card, create_time) VALUES (?, ?, ?, b'0', NULL, ?, '0000-00-00 00:00:00', NULL, NULL, NOW())");
if (!$insert) { release_id_lock($mysqli); reply_json(false, 'DB_PREPARE_FAILED', array(), 500); }
$insert->bind_param('isss', $nextId, $username, $password, $channelValue);
if (!$insert->execute()) {
    $errno = $insert->errno;
    $insert->close();
    release_id_lock($mysqli);
    if ($errno == 1062) reply_json(false, 'ACCOUNT_EXISTS');
    reply_json(false, 'DB_INSERT_FAILED', array(), 500);
}
$insert->close();
release_id_lock($mysqli);

$data = array(
    'account_id' => (int)$nextId,
    'account' => $username,
    'channel' => $channelValue,
    'last_server' => null,
    'uid' => (string)$nextId,
    'uname' => $username,
    'username' => $username
);
reply_json(true, 'REGISTER_OK', $data);
