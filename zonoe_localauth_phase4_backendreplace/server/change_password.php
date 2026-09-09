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

$oldPassword = '';
foreach (array('old_password','oldpassword','oldpwd','opwd','current_password') as $key) {
    if (isset($input[$key])) { $oldPassword = (string)$input[$key]; break; }
}
$newPassword = '';
foreach (array('new_password','newpassword','newpwd','npwd') as $key) {
    if (isset($input[$key])) { $newPassword = (string)$input[$key]; break; }
}

if ($username === '' || $oldPassword === '' || $newPassword === '') reply_json(false, 'ACCOUNT_OR_PASSWORD_EMPTY');
if (strlen($username) > 64 || strlen($oldPassword) > 64 || strlen($newPassword) > 64) reply_json(false, 'ACCOUNT_OR_PASSWORD_INVALID');
if ($oldPassword === $newPassword) reply_json(false, 'NEW_PASSWORD_SAME_AS_OLD');

$DB_HOST = '127.0.0.1';
$DB_PORT = 3306;
$DB_NAME = 'db_adv_login';
$DB_USER = 'CHANGE_ME';
$DB_PASS = 'CHANGE_ME';
if ($DB_USER === 'CHANGE_ME' || $DB_PASS === 'CHANGE_ME') reply_json(false, 'DB_CONFIG_REQUIRED', array(), 500);

$mysqli = @new mysqli($DB_HOST, $DB_USER, $DB_PASS, $DB_NAME, $DB_PORT);
if ($mysqli->connect_errno) reply_json(false, 'DB_CONNECT_FAILED', array(), 500);
if (!$mysqli->set_charset('utf8mb4')) reply_json(false, 'DB_CHARSET_FAILED', array(), 500);

$stmt = $mysqli->prepare('SELECT id, password, seal_end_time FROM t_tb_account WHERE account = ? LIMIT 1');
if (!$stmt) reply_json(false, 'DB_PREPARE_FAILED', array(), 500);
$stmt->bind_param('s', $username);
if (!$stmt->execute()) reply_json(false, 'DB_QUERY_FAILED', array(), 500);
$stmt->store_result();
if ($stmt->num_rows < 1) reply_json(false, 'ACCOUNT_NOT_FOUND');
$stmt->bind_result($id, $storedPassword, $sealEndTime);
$stmt->fetch();
$stmt->close();

if ((string)$storedPassword !== $oldPassword) reply_json(false, 'OLD_PASSWORD_INVALID');
$seal = (string)$sealEndTime;
if ($seal !== '' && $seal !== '0000-00-00 00:00:00') {
    $sealTs = strtotime($seal);
    if ($sealTs !== false && $sealTs > time()) reply_json(false, 'ACCOUNT_DISABLED');
}

$update = $mysqli->prepare('UPDATE t_tb_account SET password = ? WHERE id = ? AND account = ? LIMIT 1');
if (!$update) reply_json(false, 'DB_PREPARE_FAILED', array(), 500);
$update->bind_param('sis', $newPassword, $id, $username);
if (!$update->execute()) reply_json(false, 'DB_UPDATE_FAILED', array(), 500);
if ($update->affected_rows !== 1) reply_json(false, 'DB_UPDATE_FAILED', array(), 500);
$update->close();

reply_json(true, 'CHANGE_PASSWORD_OK', array('account_id' => (int)$id, 'account' => $username, 'uid' => (string)$id, 'uname' => $username));
