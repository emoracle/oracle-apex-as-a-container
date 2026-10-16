"""Exercise installer networking with a fake Docker CLI and dummy credentials."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
MOCK = '''#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
with open(os.environ['TRACE'], 'a') as trace:
    trace.write(json.dumps(args) + '\\n')
if args[0] == 'ps':
    if os.environ['STATE'] == 'running' or (os.environ['STATE'] == 'stopped' and '-a' in args):
        print('fixture')
elif args[0] == 'inspect':
    if os.environ['BINDINGS'] == 'FAIL':
        sys.exit(1)
    if not os.environ['BINDINGS'].startswith('network:'):
        print('network:bridge\\npublish-all:false')
    print(os.environ['BINDINGS'], end='')
elif args[0] == 'login':
    sys.stdin.read()
'''


class LoopbackPorts(unittest.TestCase):
    def run_case(self, state, bindings=''):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            for name in ('maak_container_free', 'load_env.sh'):
                shutil.copy2(ROOT / name, directory / name)
            binary = directory / 'bin'
            binary.mkdir()
            docker = binary / 'docker'
            docker.write_text(MOCK)
            docker.chmod(0o755)
            environment = dict(os.environ, PATH=f'{binary}:{os.environ["PATH"]}',
                               TRACE=str(directory / 'trace'), STATE=state,
                               BINDINGS=bindings, CONTAINER_NAME='fixture',
                               REGISTRY_USER='fixture', REGISTRY_TOKEN='dummy_token',
                               SYS_PWD='Dummy_password_1', INSTALL_APEX='FALSE',
                               INSTALL_ORDS='FALSE')
            result = subprocess.run(['bash', str(directory / 'maak_container_free')],
                                    cwd=directory, env=environment, capture_output=True)
            calls = [json.loads(line) for line in (directory / 'trace').read_text().splitlines()]
            return result.returncode, calls

    def test_new_container_uses_loopback(self):
        status, calls = self.run_case('new')
        self.assertEqual(status, 0)
        run = next(call for call in calls if call[0] == 'run')
        publications = [run[index + 1] for index, value in enumerate(run) if value == '-p']
        self.assertEqual(publications, ['127.0.0.1:1521:1521', '127.0.0.1:8080:8080',
                                        '127.0.0.1:8443:8443'])

    def test_safe_existing_containers(self):
        for state in ('running', 'stopped'):
            for bindings in ('', 'binding:127.0.0.1\nbinding:::1\n'):
                with self.subTest(state=state, bindings=bindings):
                    status, calls = self.run_case(state, bindings)
                    self.assertEqual(status, 0)
                    self.assertEqual(any(call[0] == 'start' for call in calls), state == 'stopped')

    def test_unsafe_bindings_and_inspect_errors_fail_closed(self):
        for state in ('running', 'stopped'):
            for bindings in ('binding:\n', 'binding:0.0.0.0\n', 'binding:::\n',
                             'binding:192.0.2.1\n',
                             'binding:127.0.0.1\nbinding:0.0.0.0\n',
                             'network:host\npublish-all:false\n',
                             'network:container:other\npublish-all:false\n',
                             'network:bridge\npublish-all:true\n', 'FAIL'):
                with self.subTest(state=state, bindings=bindings):
                    status, calls = self.run_case(state, bindings)
                    self.assertNotEqual(status, 0)
                    self.assertFalse(any(call[0] in ('start', 'run', 'exec') for call in calls))


if __name__ == '__main__':
    unittest.main()
