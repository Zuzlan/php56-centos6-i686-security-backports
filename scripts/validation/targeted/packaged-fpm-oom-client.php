<?php
require $argv[1];
$script = $argv[2];
$marker = $argv[3];
$pidfile = $argv[4];
function request_fixture($script, $mode) {
    $client = new Adoy\FastCGI\Client('127.0.0.1', 19056);
    return $client->request(array('GATEWAY_INTERFACE' => 'FastCGI/1.1',
        'REQUEST_METHOD' => 'GET', 'SCRIPT_FILENAME' => $script,
        'SCRIPT_NAME' => '/packaged-fpm-handler.php', 'QUERY_STRING' => 'mode=' . $mode,
        'REQUEST_URI' => '/packaged-fpm-handler.php?mode=' . $mode,
        'SERVER_PROTOCOL' => 'HTTP/1.1', 'SERVER_NAME' => 'localhost',
        'SERVER_PORT' => '80', 'REMOTE_ADDR' => '127.0.0.1', 'CONTENT_LENGTH' => '0'), false);
}
$before = request_fixture($script, 'clean');
if (!preg_match('/PID=([0-9]+)/', $before, $matches)) { throw new RuntimeException('Missing initial PID'); }
$oldpid = $matches[1];
try {
    $oom = request_fixture($script, 'oom');
    if (strpos($oom, 'FAIL_OOM_DID_NOT_TERMINATE') !== false) {
        throw new LogicException('OOM fixture did not reach allocation failure');
    }
} catch (LogicException $error) {
    throw $error;
} catch (Exception $error) {
    // EOF/empty response is expected when the worker deliberately _exit(1)s.
    echo 'OOM transport result: ', $error->getMessage(), "\n";
}
if (!file_exists($pidfile) || trim(file_get_contents($pidfile)) !== $oldpid) {
    throw new RuntimeException('OOM request did not execute in the expected worker');
}
$newpid = null;
for ($attempt = 0; $attempt < 50; ++$attempt) {
    usleep(100000);
    try {
        $response = request_fixture($script, 'clean');
        if (preg_match('/PID=([0-9]+)/', $response, $matches) &&
            strpos($response, "AUTH=none\nCLEAN\n") !== false) {
            $newpid = $matches[1]; break;
        }
    } catch (Exception $error) { /* bounded wait for the local worker replacement */ }
}
clearstatcache();
if (file_exists($marker)) { throw new RuntimeException('Shutdown handler ran after hard OOM'); }
if ($newpid === null || $newpid === $oldpid) { throw new RuntimeException('No healthy replacement worker'); }
echo 'PASS hard-OOM worker ', $oldpid, ' replaced by ', $newpid,
    "; registered shutdown marker absent; replacement request clean\n";
