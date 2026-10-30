<?php
/* PHP 5.6 syntax. Runs without database servers or external network access.
 * This is functional coverage, not proof of the security backports. */
error_reporting(E_ALL);
ini_set('display_errors', '1');
date_default_timezone_set('UTC');
if (PHP_SAPI !== 'cli') {
    header('Content-Type: text/plain');
}
$failures = 0;
function check_result($ok, $description) {
    global $failures;
    if (!$ok) {
        ++$failures;
    }
    echo ($ok ? 'PASS ' : 'FAIL ') . $description . "\n";
}
set_error_handler(function ($number, $message, $file, $line) {
    throw new ErrorException($message, 0, $number, $file, $line);
});
check_result(PHP_VERSION === '5.6.40', 'PHP_VERSION=' . PHP_VERSION);
check_result(PHP_INT_SIZE === 4, 'PHP_INT_SIZE=' . PHP_INT_SIZE);
$required = array('bz2', 'calendar', 'ctype', 'curl', 'date', 'dom', 'exif',
    'fileinfo', 'filter', 'ftp', 'gd', 'gettext', 'gmp', 'hash', 'iconv',
    'intl', 'json', 'ldap', 'libxml', 'mbstring', 'mcrypt', 'mysql', 'mysqli',
    'openssl', 'pcre', 'PDO', 'pdo_mysql', 'pdo_sqlite', 'Phar', 'session',
    'SimpleXML', 'sockets', 'SPL', 'sqlite3', 'tokenizer', 'xml', 'xmlreader',
    'xmlwriter', 'xsl', 'zip', 'zlib', 'Zend OPcache');
foreach ($required as $extension) {
    check_result(extension_loaded($extension), 'extension=' . $extension);
}
if ($failures) {
    if (PHP_SAPI !== 'cli') { http_response_code(500); }
    exit(1);
}
$tests = array(
    'JSON round trip (external JSONC)' => function () {
        $value = array('number' => 42, 'unicode' => "\xd0\x9a\xd0\xb8\xd1\x97\xd0\xb2");
        return json_decode(json_encode($value), true) === $value;
    },
    'GD PNG encode' => function () {
        $im = imagecreatetruecolor(3, 3);
        ob_start(); imagepng($im); $png = ob_get_clean(); imagedestroy($im);
        return substr($png, 0, 8) === "\x89PNG\r\n\x1a\n";
    },
    'intl normalization' => function () {
        return Normalizer::normalize("e\xcc\x81", Normalizer::FORM_C) === "\xc3\xa9";
    },
    'mbstring UTF-8' => function () { return mb_strlen("\xd0\x9a\xd0\xb8\xd1\x97\xd0\xb2", 'UTF-8') === 4; },
    'GMP arithmetic' => function () { return gmp_strval(gmp_add('2147483648', '1')) === '2147483649'; },
    'PDO SQLite transaction' => function () {
        $db = new PDO('sqlite::memory:');
        $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        $db->exec('CREATE TABLE sample (n INTEGER)');
        $db->beginTransaction(); $db->exec('INSERT INTO sample VALUES (7)'); $db->commit();
        return (int) $db->query('SELECT n FROM sample')->fetchColumn() === 7;
    },
    'MySQL APIs available (no connection)' => function () {
        return function_exists('mysql_connect') && function_exists('mysqli_connect') &&
            in_array('mysql', PDO::getAvailableDrivers(), true);
    },
    'XML parsers' => function () {
        $dom = new DOMDocument();
        return $dom->loadXML('<root><n>42</n></root>') &&
            (string) simplexml_load_string($dom->saveXML())->n === '42';
    },
    'LDAP API (no connection)' => function () { return function_exists('ldap_bind'); },
    'mcrypt round trip' => function () {
        $key = str_repeat('k', 16); $iv = str_repeat('i', 16); $plain = str_repeat('p', 16);
        $cipher = mcrypt_encrypt(MCRYPT_RIJNDAEL_128, $key, $plain, MCRYPT_MODE_CBC, $iv);
        return mcrypt_decrypt(MCRYPT_RIJNDAEL_128, $key, $cipher, MCRYPT_MODE_CBC, $iv) === $plain;
    },
    'OpenSSL AES round trip' => function () {
        $key = str_repeat('k', 16); $iv = str_repeat('i', 16);
        $cipher = openssl_encrypt('sample', 'AES-128-CBC', $key, OPENSSL_RAW_DATA, $iv);
        return openssl_decrypt($cipher, 'AES-128-CBC', $key, OPENSSL_RAW_DATA, $iv) === 'sample';
    },
    'ZIP archive round trip (external PECL zip)' => function () {
        $path = tempnam(sys_get_temp_dir(), 'php56zip-');
        try {
            $zip = new ZipArchive();
            if ($zip->open($path, ZipArchive::OVERWRITE) !== true) { return false; }
            $zip->addFromString('sample.txt', 'sample'); $zip->close();
            if ($zip->open($path) !== true) { return false; }
            $ok = $zip->getFromName('sample.txt') === 'sample'; $zip->close();
            return $ok;
        } finally { if (file_exists($path)) { unlink($path); } }
    }
);
foreach ($tests as $description => $test) {
    try { check_result($test(), $description); }
    catch (Exception $exception) { check_result(false, $description . ': ' . $exception->getMessage()); }
}
check_result(true, 'SAPI=' . PHP_SAPI);
echo 'RESULT=' . ($failures ? 'FAIL' : 'PASS') . "\n";
if ($failures && PHP_SAPI !== 'cli') { http_response_code(500); }
exit($failures ? 1 : 0);
