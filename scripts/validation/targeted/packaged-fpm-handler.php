<?php
/* Local disposable fixture only. Never expose this endpoint outside the test. */
if (isset($_GET['mode']) && $_GET['mode'] === 'oom') {
    $marker = getenv('PHP56_OOM_MARKER');
    $pidfile = getenv('PHP56_OOM_PIDFILE');
    if (!$marker || !$pidfile) { http_response_code(500); exit('Missing test paths'); }
    file_put_contents($pidfile, (string) getmypid());
    register_shutdown_function(function () use ($marker) {
        file_put_contents($marker, "UNSAFE_SHUTDOWN_HANDLER_RAN\n");
    });
    $allocation = str_repeat('x', 32 * 1024 * 1024);
    echo "FAIL_OOM_DID_NOT_TERMINATE\n";
    exit(1);
}
require __DIR__ . '/fpm-lifecycle-handler.php';
