import json, hashlib, hmac
from pathlib import Path
import tinytuya as t
from Crypto.Cipher import AES
from Crypto.Util.Padding import pad
key=b'0123456789abcdef'; payload=b'{"dps":{"20":true,"22":500}}'
out={'generator':'TinyTuya 1.20.0 and PyCryptodome', 'key':key.decode(), 'payload':payload.decode()}
for version in ['3.3','3.4','3.5']:
 body=version.encode()+bytes(12)
 if version=='3.3': body += AES.new(key,AES.MODE_ECB).encrypt(pad(payload,16))
 elif version=='3.4': body = AES.new(key,AES.MODE_ECB).encrypt(pad(body+payload,16))
 else: body += payload
 if version!='3.5': body=bytes(4)+body # 55AA pack_message expects retcode already in payload
 msg=t.TuyaMessage(7,8,0,body,0,prefix=0x6699 if version=='3.5' else 0x55aa,iv=b'abcdefghijkl' if version=='3.5' else None)
 out[version]=t.pack_message(msg,hmac_key=key if version!='3.3' else None).hex()
local=bytes(range(16));remote=bytes(range(16,32));auth=hashlib.sha256(hashlib.sha1(b'test@example.com').digest()+hashlib.sha1(b'test-password').digest()).digest()
seed=local+remote+auth
k=hashlib.sha256(b'lsk'+seed).digest()[:16]; v=hashlib.sha256(b'iv'+seed).digest(); sig=hashlib.sha256(b'ldk'+seed).digest()[:28]
seq=(int.from_bytes(v[-4:],'big')+1)&0xffffffff;seqbytes=seq.to_bytes(4,'big')
clear=b'{"method":"get_device_info"}'
ct=AES.new(k,AES.MODE_CBC,v[:12]+seqbytes).encrypt(pad(clear,16))
out['klap']={'local':local.hex(),'remote':remote.hex(),'auth':auth.hex(),'sequence':seq if seq<2**31 else seq-2**32,'clear':clear.decode(),'packet':(hashlib.sha256(sig+seqbytes+ct).digest()+ct).hex()}
mixed=bytes(a^b for a,b in zip(local,remote));out['session34']=AES.new(key,AES.MODE_ECB).encrypt(mixed).hex();out['session35']=AES.new(key,AES.MODE_GCM,nonce=local[:12]).encrypt(mixed).hex()
Path('test/fixtures/protocol_vectors.json').write_text(json.dumps(out,indent=2)+'\n')
print('Independent packet vectors generated')
