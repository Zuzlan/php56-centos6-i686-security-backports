<?php
/* PHP 5.6; only the disposable mysqld created by mysql_fixture.sh is accepted.
 * mysql_* is intentionally tested despite its expected PHP 5.6 deprecation. */
error_reporting(E_ALL & ~E_DEPRECATED);
ini_set('display_errors', '1');
date_default_timezone_set('UTC');
if (PHP_SAPI !== 'cli' || PHP_VERSION !== '5.6.40' || PHP_INT_SIZE !== 4 ||
    getenv('PHP56_ISOLATED_VALIDATION') !== '1' || !is_file('/.dockerenv') ||
    $argc !== 3 || !preg_match('~^/tmp/php56-mysql\.[A-Za-z0-9]+/mysql\.sock$~D', $argv[1]) ||
    realpath(dirname($argv[1])) !== dirname($argv[1]) ||
    !preg_match('/^php56_fixture_[0-9]+$/D', $argv[2])) {
    fwrite(STDERR, "Refusing: requires PHP 5.6.40/32-bit Docker and an owned fixture socket/database.\n");
    exit(2);
}
set_error_handler(function ($number, $message, $file, $line) {
    if (!(error_reporting() & $number)) { return false; }
    throw new ErrorException($message, 0, $number, $file, $line);
});
function fixture_check($ok, $description) {
    if (!$ok) { throw new RuntimeException($description); }
    echo 'PASS ' . $description . "\n";
}
function old_query($sql, $link) {
    $result = mysql_query($sql, $link);
    if ($result === false) { throw new RuntimeException('mysql query: ' . mysql_error($link)); }
    return $result;
}
function old_count($link) {
    $result = old_query('SELECT COUNT(*) FROM fixture_rows', $link);
    $count = (int) mysql_result($result, 0);
    mysql_free_result($result);
    return $count;
}
function fixture_row_matches($row, $api, $label, $payload, $amount) {
    return $row['api'] === $api && $row['label'] === $label &&
        $row['payload'] === $payload && $row['amount'] === $amount && $row['nullable_value'] === null;
}
$old = null;
$mysqli = null;
$pdo = null;
$databaseCreated = false;
$failed = false;
$socket = $argv[1];
$database = $argv[2];
$label = "Kyiv: \xd0\x9a\xd0\xb8\xd1\x97\xd0\xb2; quote' slash\\ snowman \xe2\x98\x83";
$payload = "\x00\xff\x27\\\n\x1a";
try {
    foreach (array('mysql', 'mysqli', 'PDO', 'pdo_mysql') as $extension) {
        fixture_check(extension_loaded($extension), 'extension=' . $extension);
    }
    fixture_check(filetype($socket) === 'socket', 'fixture transport is a Unix socket');
    $old = mysql_connect('localhost:' . $socket, 'root', '', true);
    fixture_check(is_resource($old), 'legacy mysql connection');
    echo 'INFO mysql_client=' . mysql_get_client_info() . "\n";
    echo 'INFO mysql_server=' . mysql_get_server_info($old) . "\n";
    $network = old_query("SHOW VARIABLES LIKE 'skip_networking'", $old);
    $networkRow = mysql_fetch_assoc($network);
    mysql_free_result($network);
    fixture_check(strtoupper($networkRow['Value']) === 'ON', 'server TCP networking disabled');
    old_query('CREATE DATABASE `' . $database . '` CHARACTER SET utf8 COLLATE utf8_unicode_ci', $old);
    $databaseCreated = true;
    fixture_check(mysql_select_db($database, $old), 'legacy mysql selects new fixture database');
    fixture_check(mysql_set_charset('utf8', $old), 'legacy mysql UTF-8 charset');
    old_query("SET SESSION sql_mode='STRICT_ALL_TABLES'", $old);
    old_query('CREATE TABLE fixture_rows (id INT NOT NULL AUTO_INCREMENT PRIMARY KEY, ' .
        'api VARCHAR(16) NOT NULL, label VARCHAR(255) NOT NULL, payload VARBINARY(255) NOT NULL, ' .
        'amount DECIMAL(12,2) NOT NULL, nullable_value VARCHAR(32) NULL) ENGINE=InnoDB DEFAULT CHARSET=utf8', $old);
    $engineResult = old_query("SHOW TABLE STATUS LIKE 'fixture_rows'", $old);
    $engineRow = mysql_fetch_assoc($engineResult);
    mysql_free_result($engineResult);
    fixture_check(strtoupper($engineRow['Engine']) === 'INNODB', 'transactional InnoDB table');
    $legacyInsert = "INSERT INTO fixture_rows (api,label,payload,amount,nullable_value) VALUES ('mysql','" .
        mysql_real_escape_string($label, $old) . "','" . mysql_real_escape_string($payload, $old) . "',12345.67,NULL)";
    old_query('START TRANSACTION', $old);
    old_query($legacyInsert, $old);
    old_query('COMMIT', $old);
    $result = old_query("SELECT api,label,payload,amount,nullable_value FROM fixture_rows WHERE api='mysql'", $old);
    fixture_check(fixture_row_matches(mysql_fetch_assoc($result), 'mysql', $label, $payload, '12345.67'),
        'legacy mysql escaped UTF-8/binary/decimal/NULL commit round trip');
    mysql_free_result($result);
    old_query('START TRANSACTION', $old);
    old_query($legacyInsert, $old);
    old_query('ROLLBACK', $old);
    fixture_check(old_count($old) === 1, 'legacy mysql rollback');

    mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);
    $mysqli = mysqli_init();
    fixture_check($mysqli->real_connect('localhost', 'root', '', $database, 0, $socket), 'mysqli socket connection');
    echo 'INFO mysqli_client=' . mysqli_get_client_info() . "\n";
    fixture_check($mysqli->set_charset('utf8'), 'mysqli UTF-8 charset');
    $mysqli->query("SET SESSION sql_mode='STRICT_ALL_TABLES'");
    $insert = $mysqli->prepare('INSERT INTO fixture_rows (api,label,payload,amount,nullable_value) VALUES (?,?,?,?,?)');
    $api = 'mysqli';
    $amount = '23456.78';
    $nullable = null;
    $insert->bind_param('sssss', $api, $label, $payload, $amount, $nullable);
    $mysqli->autocommit(false);
    $insert->execute();
    $mysqliId = $mysqli->insert_id;
    $mysqli->commit();
    $insert->execute();
    $mysqli->rollback();
    $mysqli->autocommit(true);
    $insert->close();
    fixture_check(old_count($old) === 2, 'mysqli commit/rollback visible through legacy mysql');
    $select = $mysqli->prepare('SELECT api,label,payload,amount,nullable_value FROM fixture_rows WHERE id=?');
    $select->bind_param('i', $mysqliId);
    $select->execute();
    $select->bind_result($readApi, $readLabel, $readPayload, $readAmount, $readNull);
    fixture_check($select->fetch() === true && $readApi === 'mysqli' && $readLabel === $label &&
        $readPayload === $payload && $readAmount === '23456.78' && $readNull === null,
        'mysqli native prepared UTF-8/binary/decimal/NULL round trip');
    $select->close();

    $pdo = new PDO('mysql:unix_socket=' . $socket . ';dbname=' . $database . ';charset=utf8', 'root', '',
        array(PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_EMULATE_PREPARES => false));
    echo 'INFO pdo_client=' . $pdo->getAttribute(PDO::ATTR_CLIENT_VERSION) . "\n";
    $pdo->exec("SET SESSION sql_mode='STRICT_ALL_TABLES'");
    fixture_check(!$pdo->getAttribute(PDO::ATTR_EMULATE_PREPARES), 'PDO native prepared mode');
    $insert = $pdo->prepare('INSERT INTO fixture_rows (api,label,payload,amount,nullable_value) VALUES (?,?,?,?,?)');
    $insert->bindValue(1, 'pdo', PDO::PARAM_STR);
    $insert->bindValue(2, $label, PDO::PARAM_STR);
    $insert->bindValue(3, $payload, PDO::PARAM_STR);
    $insert->bindValue(4, '34567.89', PDO::PARAM_STR);
    $insert->bindValue(5, null, PDO::PARAM_NULL);
    $pdo->beginTransaction();
    $insert->execute();
    $pdoId = (int) $pdo->lastInsertId();
    $pdo->commit();
    $pdo->beginTransaction();
    $insert->execute();
    $pdo->rollBack();
    fixture_check(old_count($old) === 3, 'PDO commit/rollback visible through legacy mysql');
    $select = $pdo->prepare('SELECT api,label,payload,amount,nullable_value FROM fixture_rows WHERE id=?');
    $select->bindValue(1, $pdoId, PDO::PARAM_INT);
    $select->execute();
    fixture_check(fixture_row_matches($select->fetch(PDO::FETCH_ASSOC), 'pdo', $label, $payload, '34567.89'),
        'PDO native prepared UTF-8/binary/decimal/NULL round trip');
    $select->closeCursor();
    $pdo->setAttribute(PDO::ATTR_EMULATE_PREPARES, true);
    $select = $pdo->prepare('SELECT COUNT(*) FROM fixture_rows WHERE label=? AND payload=?');
    $select->execute(array($label, $payload));
    fixture_check((int) $select->fetchColumn() === 3, 'PDO emulated prepared escaping across all three APIs');
    $select->closeCursor();
    $result = $mysqli->query('SELECT COUNT(*) AS n FROM fixture_rows');
    $countRow = $result->fetch_assoc();
    fixture_check((int) $countRow['n'] === 3, 'all three API commits visible through mysqli');
    $result->free();
} catch (Exception $exception) {
    $failed = true;
    echo 'FAIL ' . get_class($exception) . ': ' . $exception->getMessage() . "\n";
} finally {
    try {
        unset($select, $insert, $result);
        $pdo = null;
        if ($mysqli instanceof mysqli) { $mysqli->close(); }
        if (is_resource($old)) {
            if ($databaseCreated) { old_query('DROP DATABASE `' . $database . '`', $old); }
            mysql_close($old);
        }
        echo "PASS fixture cleanup completed\n";
    } catch (Exception $exception) {
        $failed = true;
        echo 'FAIL fixture database cleanup: ' . $exception->getMessage() . "\n";
    }
}
echo 'RESULT=' . ($failed ? 'FAIL' : 'PASS') . "\n";
exit($failed ? 1 : 0);
