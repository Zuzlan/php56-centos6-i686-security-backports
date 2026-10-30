<?php
require $argv[1];
$script = $argv[2];
$worker = null;
$requests = 0;
for ($round = 0; $round < 50; ++$round) {
    foreach (array('prime', 'clean', 'fault', 'clean') as $mode) {
        $client = new Adoy\FastCGI\Client('127.0.0.1', 19056);
        $params = array('GATEWAY_INTERFACE' => 'FastCGI/1.1',
            'REQUEST_METHOD' => 'GET', 'SCRIPT_FILENAME' => $script,
            'SCRIPT_NAME' => '/fpm-lifecycle-handler.php', 'QUERY_STRING' => 'mode=' . $mode,
            'REQUEST_URI' => '/fpm-lifecycle-handler.php?mode=' . $mode,
            'SERVER_PROTOCOL' => 'HTTP/1.1', 'SERVER_NAME' => 'localhost',
            'SERVER_PORT' => '80', 'REMOTE_ADDR' => '127.0.0.1', 'CONTENT_LENGTH' => '0');
        if ($mode !== 'clean') {
            $params['HTTP_AUTHORIZATION'] = 'Basic ' . base64_encode('fixture-user:fixture-password');
        }
        $response = $client->request($params, false);
        ++$requests;
        if (!preg_match('/PID=([0-9]+)/', $response, $matches)) {
            fwrite(STDERR, "FAIL missing worker PID round=$round mode=$mode\n$response\n"); exit(1);
        }
        if ($worker === null) { $worker = $matches[1]; }
        if ($matches[1] !== $worker) {
            fwrite(STDERR, "FAIL worker replaced after cleanup round=$round mode=$mode\n"); exit(1);
        }
        if ($mode === 'clean' && (strpos($response, "AUTH=none\nCLEAN\n") === false ||
            strpos($response, 'STALE_ERROR_HANDLER') !== false || strpos($response, 'EXCEPTION_HANDLER') !== false)) {
            fwrite(STDERR, "FAIL stale per-request state round=$round\n$response\n"); exit(1);
        }
        if ($mode !== 'clean' && strpos($response, "AUTH=fixture-user\n") === false) {
            fwrite(STDERR, "FAIL auth fixture not activated round=$round\n$response\n"); exit(1);
        }
    }
}
echo "PASS $requests requests in one worker pid=$worker; auth/error/exception/destructor state isolated\n";
