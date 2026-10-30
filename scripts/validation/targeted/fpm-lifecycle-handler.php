<?php
header('Content-Type: text/plain');
$mode = isset($_GET['mode']) ? $_GET['mode'] : 'clean';
echo 'PID=', getmypid(), "\n";
get_current_user();
if ($mode === 'prime' || $mode === 'fault') {
    set_error_handler(function () { echo "STALE_ERROR_HANDLER\n"; return true; });
    set_exception_handler(function ($exception) { echo "EXCEPTION_HANDLER\n"; });
    $GLOBALS['held'] = array_fill(0, 128, str_repeat('fixture', 128));
    if ($mode === 'fault') {
        class ShutdownFaultFixture {
            public function __destruct() { throw new RuntimeException('LOCAL_LIFECYCLE_FIXTURE'); }
        }
        $GLOBALS['fault_fixture'] = new ShutdownFaultFixture();
    }
    echo 'AUTH=', isset($_SERVER['PHP_AUTH_USER']) ? $_SERVER['PHP_AUTH_USER'] : 'missing', "\n";
    echo strtoupper($mode), "\n";
} else {
    trigger_error('LOCAL_CLEAN_WARNING', E_USER_WARNING);
    echo 'AUTH=', isset($_SERVER['PHP_AUTH_USER']) ? $_SERVER['PHP_AUTH_USER'] : 'none', "\n";
    echo "CLEAN\n";
}
