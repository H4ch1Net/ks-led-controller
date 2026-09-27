import json
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory
import unittest
from ks_light.service import load_config, InstanceLock

class ServiceTests(unittest.TestCase):
    def setUp(self):
        self.tmp=TemporaryDirectory();self.root=Path(self.tmp.name)
        self.config={'version':1,'mode':'simulation','port':8765,'lights_file':'lights.json','token_file':'token.txt','runtime_dir':'runtime'}
        self.path=self.root/'hub.json'
        (self.root/'token.txt').write_text('test-secret-token-with-at-least-32-characters')
        (self.root/'lights.json').write_text(json.dumps({'lights':[{'id':'desk','name':'Desk','prefix':'KS03~','address':'sim'}]}))
        self.save()
    def tearDown(self): self.tmp.cleanup()
    def save(self): self.path.write_text(json.dumps(self.config))
    def test_paths_resolve_relative_to_configuration(self):
        result=load_config(self.path)
        self.assertEqual(result['runtime'],self.root/'runtime')
        self.assertTrue(result['simulation'])
        self.assertEqual(result['lights'][0]['id'],'desk')
    def test_check_does_not_create_runtime_or_send_commands(self):
        result=subprocess.run([sys.executable,'-m','ks_light.service','--config',str(self.path),'--check'],capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertFalse((self.root/'runtime').exists())
        self.assertNotIn('test-secret',result.stdout+result.stderr)
    def test_persistent_preflight_is_read_only(self):
        self.config['persist_state']=True;self.save()
        config=load_config(self.path)
        self.assertEqual(config['state_file'],self.root/'runtime'/'last-sent.json')
        result=subprocess.run([sys.executable,'-m','ks_light.service','--config',str(self.path),'--check'],capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertFalse((self.root/'runtime').exists())

    def test_library_preflight_and_relative_path(self):
        library = {"version":1,"groups":[{"id":"room","name":"Room","members":["desk"]}],
                   "scenes":[{"id":"night","name":"Night","actions":[{"light":"desk","type":"state","body":{"power":False}}]}]}
        path=self.root/'library.json'
        path.write_text(json.dumps(library),encoding='utf-8')
        self.config['library_file']='library.json';self.save()
        self.assertEqual(load_config(self.path)['library'],library)
        result=subprocess.run([sys.executable,'-m','ks_light.service','--config',str(self.path),'--check'],capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertFalse((self.root/'runtime').exists())
        library['groups'][0]['members']=['missing']
        path.write_text(json.dumps(library),encoding='utf-8')
        result=subprocess.run([sys.executable,'-m','ks_light.service','--config',str(self.path),'--check'],capture_output=True,text=True)
        self.assertEqual(result.returncode,2)
        self.assertFalse((self.root/'runtime').exists())

    def test_invalid_settings_are_rejected(self):
        for key,value in [('version',True),('mode','BLE'),('port',True),('token_file',''),('unexpected',1),('persist_state','yes')]:
            original=dict(self.config);self.config[key]=value;self.save()
            with self.assertRaises(ValueError):load_config(self.path)
            self.config=original
    def test_remote_plaintext_is_rejected(self):
        for host in ['0.0.0.0', '192.168.1.5', '::']:
            self.config['listen_host']=host; self.save()
            with self.assertRaisesRegex(ValueError, 'require TLS'):load_config(self.path)
        self.config['listen_host']='127.0.0.1'; self.save()
        self.assertIsNone(load_config(self.path)['ssl_context'])

    def test_tls_files_are_checked_without_starting_server(self):
        self.config['listen_host']='0.0.0.0'
        self.config['tls']={'cert_file':'missing.crt','key_file':'missing.key'}; self.save()
        with self.assertRaises(OSError):load_config(self.path)
        self.config['tls']['verify']=False; self.save()
        with self.assertRaises(ValueError):load_config(self.path)

    def test_mqtt_credentials_and_manifest(self):
        (self.root/'mqtt.txt').write_text('private-password\n')
        self.config['mqtt']={'hostname':'broker','hub_id':'test','username':'controller','password_file':'mqtt.txt'};self.save()
        mqtt=load_config(self.path)['mqtt']
        self.assertEqual(mqtt['password'],'private-password')
        self.assertEqual(mqtt['manifest'],str(self.root/'runtime'/'discovery.json'))
        self.config['mqtt']['tls']='false';self.save()
        with self.assertRaises(ValueError):load_config(self.path)
    def test_corrupt_config_never_prints_secret_contents(self):
        self.path.write_text('{"private-secret-contents')
        result=subprocess.run([sys.executable,'-m','ks_light.service','--config',str(self.path),'--check'],capture_output=True,text=True)
        self.assertEqual(result.returncode,2)
        self.assertNotIn('private-secret',result.stdout+result.stderr)
    def test_lock_rejects_second_process_and_releases(self):
        path=self.root/'runtime'/'hub.lock'
        code='from ks_light.service import InstanceLock; import sys\nwith InstanceLock(sys.argv[1]): print("locked")'
        with InstanceLock(path):
            result=subprocess.run([sys.executable,'-c',code,str(path)],capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0)
            self.assertIn('Another hub owns',result.stderr)
        result=subprocess.run([sys.executable,'-c',code,str(path)],capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stderr)

if __name__=='__main__':unittest.main()
