#!/usr/bin/env python
"""Isolated CGI multipart regression tests; Python 2.6/3 compatible.
Usage: PHP56_ISOLATED_VALIDATION=1 python run_mime_cgi.py PHP_CGI NEW_RESULTS_DIR
"""
from __future__ import print_function
import hashlib
import json
import os
import subprocess
import sys


def main():
    if len(sys.argv) != 3: print(__doc__); return 2
    if os.environ.get('PHP56_ISOLATED_VALIDATION') != '1' or not os.path.isfile('/.dockerenv'):
        raise RuntimeError('Run only inside explicit isolated validation container')
    cgi, output = [os.path.abspath(arg) for arg in sys.argv[1:]]
    os.makedirs(output)
    handler = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'mime-handler.php')
    delim = 'php56-local-mime-regression-boundary'
    disposition = 'Content-Disposition: form-data; name="good"\r\n'
    expected = 'POST:good=value\nDONE\n'
    cases = [
        ('ordinary-field', disposition, 'value', expected),
        ('ignored-header-before-field', 'X-Ignored: poison\r\n' + disposition, 'value', expected),
        ('ignored-header-fold-before-field', 'X-Ignored: poison\r\n ignored-continuation\r\n' + disposition, 'value', expected),
        ('recognized-folded-header', 'Content-Disposition: form-data;\r\n name="good"\r\n', 'value', expected),
        ('duplicate-disposition-first-wins', disposition + 'Content-Disposition: form-data; name="wrong"\r\n', 'value', expected),
        ('ignored-header-before-file-type', 'Content-Disposition: form-data; name="upload"; filename="sample.txt"\r\nX-Ignored: poison\r\nContent-Type: text/plain\r\n', 'data', 'FILE:upload:name=sample.txt:type=text/plain:error=0:size=4\nDONE\n'),
        ('duplicate-header-memory-limit', disposition + ('Content-Disposition: form-data; name="unused' + 'x' * 96 + '"\r\n') * 50000, 'value', expected)]
    results = []
    for name, headers, payload, want in cases:
        body = ('--' + delim + '\r\n' + headers + '\r\n' + payload + '\r\n--' + delim + '--\r\n').encode('ascii')
        env = {'PATH': '/usr/bin:/bin', 'REDIRECT_STATUS': '1', 'REQUEST_METHOD': 'POST',
               'CONTENT_TYPE': 'multipart/form-data; boundary=' + delim,
               'CONTENT_LENGTH': str(len(body)), 'SCRIPT_FILENAME': handler,
               'SCRIPT_NAME': '/mime-handler.php', 'SERVER_PROTOCOL': 'HTTP/1.1',
               'SERVER_NAME': 'localhost', 'SERVER_PORT': '80', 'GATEWAY_INTERFACE': 'CGI/1.1'}
        args = ['timeout', '20', cgi, '-n', '-d', 'cgi.force_redirect=0', '-d', 'memory_limit=8M',
                '-d', 'post_max_size=16M', '-d', 'upload_max_filesize=1M', '-d', 'max_input_vars=1000',
                '-d', 'display_errors=stderr', '-d', 'log_errors=0']
        proc = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
        stdout, stderr = proc.communicate(body)
        for suffix, data in [('stdout', stdout), ('stderr', stderr)]:
            with open(os.path.join(output, name + '.' + suffix), 'wb') as handle: handle.write(data)
        actual = stdout.decode('utf-8', 'replace').replace('\r\n', '\n').split('\n\n', 1)
        response = actual[1] if len(actual) == 2 else ''
        ok = proc.returncode == 0 and response == want and not stderr
        results.append({'test': name, 'status': 'PASS' if ok else 'FAIL', 'exit': proc.returncode,
                        'request_bytes': len(body), 'request_sha256': hashlib.sha256(body).hexdigest(),
                        'expected_response': want, 'actual_response': response})
        print('%s %s exit=%d' % (results[-1]['status'], name, proc.returncode))
    with open(os.path.join(output, 'results.json'), 'w') as handle: json.dump(results, handle, indent=2)
    with open(cgi, 'rb') as handle: digest = hashlib.sha256(handle.read()).hexdigest()
    with open(os.path.join(output, 'php-cgi.sha256'), 'w') as handle: handle.write(digest + '  ' + cgi + '\n')
    return 0 if all(item['status'] == 'PASS' for item in results) else 1


if __name__ == '__main__': sys.exit(main())
