<?php
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
header('Pragma: no-cache');

function out_json($ok, $message, $extra = array(), $status = 200) {
    http_response_code($status);
    echo json_encode(array_merge(array('ok' => $ok ? true : false, 'message' => $message), $extra), JSON_UNESCAPED_UNICODE);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') out_json(false, 'METHOD_NOT_ALLOWED', array(), 405);
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

$username = isset($input['username']) ? trim((string)$input['username']) : '';
$oldPassword = isset($input['old_password']) ? (string)$input['old_password'] : '';
$newPassword = isset($input['new_password']) ? (string)$input['new_password'] : '';
if ($username === '' || $oldPassword === '' || $newPassword === '') out_json(false, 'ACCOUNT_OR_PASSWORD_EMPTY');
if (strlen($username) > 64 || strlen($oldPassword) > 64 || strlen($newPassword) > 64) out_json(false, 'ACCOUNT_OR_PASSWORD_INVALID');
if ($oldPassword === $newPassword) out_json(false, 'NEW_PASSWORD_SAME_AS_OLD');

$DB_HOST = '127.0.0.1';
$DB_PORT = 3306;
$DB_NAME = 'db_adv_login';
$DB_USER = 'CHANGE_ME';
$DB_PASS = 'CHANGE_ME';
if ($DB_USER === 'CHANGE_ME' || $DB_PASS === 'CHANGE_ME') out_json(false, 'DB_CONFIG_REQUIRED', array(), 500);

$mysqli = @new mysqli($DB_HOST, $DB_USER, $DB_PASS, $DB_NAME, $DB_PORT);
if ($mysqli->connect_errno) out_json(false, 'DB_CONNECT_FAILED', array(), 500);
if (!$mysqli->set_charset('utf8mb4')) out_json(false, 'DB_CHARSET_FAILED', array(), 500);

$stmt = $mysqli->prepare('SELECT id, password, seal_end_time FROM t_tb_account WHERE account = ? LIMIT 1');
if (!$stmt) out_json(false, 'DB_PREPARE_FAILED', array(), 500);
$stmt->bind_param('s', $username);
if (!$stmt->execute()) out_json(false, 'DB_QUERY_FAILED', array(), 500);
$stmt->store_result();
if ($stmt->num_rows < 1) out_json(false, 'ACCOUNT_NOT_FOUND');
$stmt->bind_result($id, $storedPassword, $sealEndTime);
$stmt->fetch();
$stmt->close();
if ((string)$storedPassword !== $oldPassword) out_json(false, 'OLD_PASSWORD_INVALID');
$seal = (string)$sealEndTime;
if ($seal !== '' && $seal !== '0000-00-00 00:00:00') {
    $sealTs = strtotime($seal);
    if ($sealTs !== false && $sealTs > time()) out_json(false, 'ACCOUNT_DISABLED');
}

$update = $mysqli->prepare('UPDATE t_tb_account SET password = ? WHERE id = ? AND account = ? LIMIT 1');
if (!$update) out_json(false, 'DB_PREPARE_FAILED', array(), 500);
$update->bind_param('sis', $newPassword, $id, $username);
if (!$update->execute()) out_json(false, 'DB_UPDATE_FAILED', array(), 500);
if ($update->affected_rows !== 1) out_json(false, 'DB_UPDATE_FAILED', array(), 500);
out_json(true, 'CHANGE_PASSWORD_OK', array('account_id' => (int)$id, 'account' => $username));
