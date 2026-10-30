<?php
/* Fixed loopback endpoint; this client cannot address a production server. */
if (PHP_SAPI !== 'cli' || PHP_INT_SIZE !== 4 || !is_file('/.dockerenv') ||
    getenv('PHP56_ISOLATED_VALIDATION') !== '1' || $argc !== 2 ||
    !preg_match('~^/tmp/php56-apache-lifecycle\.[A-Za-z0-9]+/state$~D', $argv[1])) {
    fwrite(STDERR, "Refusing: isolated Docker fixture and generated state directory required.\n"); exit(2);
}
function fixture_http($mode) {
    $socket = @fsockopen('127.0.0.1', 19057, $error, $message, 2);
    if ($socket === false) { throw new RuntimeException('Fixture HTTP connection: ' . $message); }
    stream_set_timeout($socket, 5);
    $request = "GET /check.php?mode=" . $mode . " HTTP/1.0\r\nHost: localhost\r\nConnection: close\r\n";
    if ($mode === 'prime' || $mode === 'fault') {
        $request .= 'Authorization: Basic ' . base64_encode('fixture-user:fixture-password') . "\r\n";
    }
    $request .= "\r\n";
    $sent = 0;
    while ($sent < strlen($request)) {
        $length = fwrite($socket, substr($request, $sent));
        if ($length === false || $length === 0) { fclose($socket); throw new RuntimeException('Fixture write failed'); }
        $sent += $length;
    }
    $response = stream_get_contents($socket);
    $metadata = stream_get_meta_data($socket);
    fclose($socket);
    if ($metadata['timed_out']) { throw new RuntimeException('Fixture response timed out'); }
    return $response;
}
function fixture_response_pid($response, $mode) {
    if (!preg_match('/^HTTP\/1\.[01] ([0-9]{3})/', $response, $status) ||
        ($mode !== 'fault' && $status[1] !== '200') ||
        ($mode === 'fault' && $status[1] !== '200' && $status[1] !== '500') ||
        !preg_match('/PID=([0-9]+)\nSAPI=apache2handler\n/', $response, $matches)) {
        throw new RuntimeException("Unexpected $mode response: " . $response);
    }
    if ($mode === 'clean' && (strpos($response, "AUTH=none\nCLEAN\n") === false ||
        strpos($response, 'STALE_ERROR_HANDLER') !== false || strpos($response, 'EXCEPTION_HANDLER') !== false)) {
        throw new RuntimeException('Stale authentication/handler state: ' . $response);
    }
    if ($mode !== 'clean' && strpos($response, "AUTH=fixture-user\n") === false) {
        throw new RuntimeException('Authentication priming did not execute: ' . $response);
    }
    return $matches[1];
}
$state = $argv[1];
try {
    $worker = null;
    $requests = 0;
    for ($round = 0; $round < 50; ++$round) {
        foreach (array('prime', 'clean', 'fault', 'clean') as $mode) {
            $pid = fixture_response_pid(fixture_http($mode), $mode);
            if ($worker === null) { $worker = $pid; }
            if ($pid !== $worker) { throw new RuntimeException('Worker replaced during normal/fatal lifecycle'); }
            ++$requests;
            echo "PASS round=$round mode=$mode worker=$pid\n";
        }
    }
    echo "PASS $requests sequential requests in one Apache worker=$worker\n";
    if (file_exists($state . '/oom-started') || file_exists($state . '/unexpected-oom-shutdown')) {
        throw new RuntimeException('OOM state directory was not fresh');
    }
    $oomResponse = fixture_http('oom');
    file_put_contents($state . '/oom-http-response.txt', $oomResponse);
    if (!is_file($state . '/oom-started') || trim(file_get_contents($state . '/oom-started')) !== $worker) {
        throw new RuntimeException('OOM request did not enter the same Apache worker');
    }
    $replacement = null;
    for ($attempt = 0; $attempt < 50; ++$attempt) {
        try { $replacement = fixture_response_pid(fixture_http('clean'), 'clean'); break; }
        catch (Exception $exception) { usleep(100000); }
    }
    if ($replacement === null || $replacement === $worker) {
        throw new RuntimeException('Apache did not replace the OOM worker and serve a clean request');
    }
    if (fixture_response_pid(fixture_http('clean'), 'clean') !== $replacement) {
        throw new RuntimeException('Replacement Apache worker did not remain healthy');
    }
    if (file_exists($state . '/unexpected-oom-shutdown')) {
        throw new RuntimeException('PHP shutdown callback ran after hard-OOM');
    }
    echo "PASS hard-OOM replaced worker=$worker with worker=$replacement; PHP shutdown callback bypassed\n";
    echo "RESULT=PASS\n";
} catch (Exception $exception) {
    fwrite(STDERR, 'FAIL ' . $exception->getMessage() . "\nRESULT=FAIL\n"); exit(1);
}
