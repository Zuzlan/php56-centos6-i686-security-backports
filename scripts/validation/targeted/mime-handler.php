<?php
header('Content-Type: text/plain');
ksort($_POST);
foreach ($_POST as $key => $value) {
    echo 'POST:', $key, '=', $value, "\n";
}
ksort($_FILES);
foreach ($_FILES as $key => $file) {
    echo 'FILE:', $key, ':name=', $file['name'], ':type=', $file['type'],
        ':error=', $file['error'], ':size=', $file['size'], "\n";
}
echo "DONE\n";
