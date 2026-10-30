<?php
header('Content-Type: text/plain');
$mode = isset($_GET['mode']) ? $_GET['mode'] : 'clean';
$state = dirname(__DIR__) . '/state';
echo 'PID=', getmypid(), "\nSAPI=", PHP_SAPI, "\n";
get_current_user();
if ($mode === 'oom') {
    file_put_contents($state . '/oom-started', (string) getmypid());
    register_shutdown_function(function () use ($state) {
        file_put_contents($state . '/unexpected-oom-shutdown', 'shutdown callback ran');
    });
    $blocks = array();
    while (true) { $blocks[] = str_repeat('x', 1024 * 1024); }
} elseif ($mode === 'prime' || $mode === 'fault') {
    set_error_handler(function () { echo "STALE_ERROR_HANDLER\n"; return true; });
    set_exception_handler(function ($exception) { echo "EXCEPTION_HANDLER\n"; });
    $GLOBALS['held'] = array_fill(0, 128, str_repeat('fixture', 128));
    if ($mode === 'fault') {
        class ApacheShutdownFaultFixture {
            public function __destruct() { throw new RuntimeException('LOCAL_APACHE_LIFECYCLE_FIXTURE'); }
        }
        $GLOBALS['fault_fixture'] = new ApacheShutdownFaultFixture();
    }
    echo 'AUTH=', isset($_SERVER['PHP_AUTH_USER']) ? $_SERVER['PHP_AUTH_USER'] : 'missing', "\n";
    echo strtoupper($mode), "\n";
} else {
    trigger_error('LOCAL_APACHE_CLEAN_WARNING', E_USER_WARNING);
    echo 'AUTH=', isset($_SERVER['PHP_AUTH_USER']) ? $_SERVER['PHP_AUTH_USER'] : 'none', "\n";
    echo "CLEAN\n";
}
