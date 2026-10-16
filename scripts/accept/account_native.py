# /// script
# requires-python = ">=3.12"
# dependencies = ["alibabacloud-dypnsapi20170525==2.0.0", "alibabacloud-dysmsapi20170525==4.6.0", "alibabacloud-credentials==1.0.12"]
# ///
"""Isolated production server + real, authorized transports; original XCTest lane.

No production account is read or changed. Credentials and received OTPs remain
in memory. The coordinator observes actual server state; it never grants auth.
"""
from pathlib import Path
import contextlib, email, email.header, hashlib, imaplib, importlib, json, os, re, secrets
import shlex, shutil, subprocess, sys, threading, time, urllib.request, urllib.error
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from http.cookiejar import CookieJar

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(os.environ["POINTS_ACCOUNT_RUN_ROOT"]).resolve()
OUT.relative_to(ROOT / "perf/account/native-current")
LEGACY = Path.home() / "mac-pair/tasks/points-account-release-20261008/output/round5"
SERVER = Path('/Users/tianli/Apps/edu/web/points')
ENV = {k: os.environ[k] for k in ('PATH', 'HOME', 'USER', 'LOGNAME', 'LANG', 'LC_ALL', 'LC_CTYPE', 'SHELL') if k in os.environ}
ENV.update(PATH='/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin', PYTHONDONTWRITEBYTECODE='1')

def redact(path):
    data = path.read_bytes()
    for key, value in os.environ.items():
        if len(value) > 8 and re.search(r'TOKEN|PASSWORD|SECRET|API_KEY|^PW_|_PW$|^AUTH_|BARK_KEY', key, re.I):
            data = data.replace(value.encode(), ('<redacted:' + key + '>').encode())
    data = re.sub(rb'gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{30,}', b'<redacted:GitHub-access-token>', data)
    path.write_bytes(data)
    path.chmod(0o600)
# Reuse the original native transport coordinator; only current orchestration
# lives here. Historical stopped contracts and evidence remain untouched.
# Ported from account_native.py (2026-10-08 round5); all authentication, scoring,
# SMS provider verification and persistence still execute the original service.
PY = '/Users/tianli/Dev/.venv/bin/python'
sys.dont_write_bytecode = True

def ensure_task_active(real_transport=False):
    contract = json.loads((OUT / 'contract.json').read_text())
    if contract.get('execution_state') != 'authorized_20261016_continuation':
        raise RuntimeError('Real-message acceptance stopped after owner SMS feedback; renewed authorization required')
    if time.time() > contract.get('resumption_deadline_epoch', float('inf')):
        raise RuntimeError('Original task resumption deadline reached')
    if real_transport and not contract.get('allow_real_transports', False):
        raise RuntimeError('Offline native acceptance must pass before any real transport')

def remote_configuration():
    code = '''from pathlib import Path
import json,shlex
out={}
for n in ['/etc/edu-points-mail.env','/etc/edu-points-sms.env']:
 p=Path(n)
 if not p.exists(): continue
 if p.stat().st_mode & 0o077: raise SystemExit(2)
 for l in p.read_text().splitlines():
  if '=' in l and not l.startswith('#'):
   k,v=l.split('=',1);out[k]=shlex.split(v)[0] if v else ''
print(json.dumps(out))
'''
    reply = subprocess.run(['ssh','-o','BatchMode=yes','vps','python3 -'],input=code,text=True,capture_output=True,timeout=40)
    if reply.returncode: raise RuntimeError('existing remote transport configuration unavailable')
    return json.loads(reply.stdout)

def main():
    ensure_task_active()
    case = sys.argv[1]
    no_transport = case == 'PasswordLogin'
    offline = '--offline' in sys.argv[2:] or no_transport
    platform = sys.argv[sys.argv.index('--platform')+1] if '--platform' in sys.argv else 'ipad'
    if platform not in ('ipad','iphone'): raise ValueError('platform')
    if case not in ('PasswordLogin','EmailLifecycle','EmailTransport','EmailBinding','PhoneLifecycle','PhoneBinding','PasswordlessDeletion'): raise ValueError('case')
    test_sha=hashlib.sha256((ROOT/'Tests/AccountUITests.swift').read_bytes()).hexdigest()
    if case == 'PasswordLogin' and sum(json.loads(p.read_text()).get('exit_code') == 1 and json.loads(p.read_text()).get('source_sha256',{}).get('AccountUITests.swift')==test_sha for p in OUT.glob('account-PasswordLogin-*/evidence.json')) >= 2:
        raise RuntimeError('PasswordLogin second-round attempts already completed; no third run')
    # One assertion shared by different account pages is one failure budget.
    # Switching a page must not allow another attempt at the same blocked step.
    blocked = ('native SMS send receipt',) if case.startswith('Phone') or case=='PasswordlessDeletion' else ('missing result 验证码不正确',) if case.startswith('Email') else ('native field accepted complete input 登录密码',) if case=='PasswordLogin' else ()
    for failure in blocked:
        hits=sum(failure in p.read_text(errors='replace') and (p.parents[1]/'evidence.json').exists() and json.loads((p.parents[1]/'evidence.json').read_text()).get('source_sha256',{}).get('AccountUITests.swift')==test_sha for p in OUT.glob('account-*/native/ui.log'))
        if hits>=2:raise RuntimeError('current round failure budget exhausted: '+failure)
    run = OUT / (('offline-' if offline and not no_transport else 'account-') + case + '-' + str(int(time.time())))
    run.mkdir(exist_ok=True);run.chmod(0o700)
    # Test-runner build products stay out of the synced task folder; logs and proofs are copied back.
    native=Path.home()/'Library/Caches/points-account-native'/run.name;native.mkdir(parents=True,exist_ok=True);native.chmod(0o700)
    shared_runners=Path.home()/'Library/Caches/points-account-native/runners';shared_runners.mkdir(exist_ok=True)
    (native/'runners').symlink_to(shared_runners)
    # Account homes and xcresult may contain authorized recipient data or typed
    # input. Keep them in the original private cache, outside public source.
    fixture = native/'fixture';resumed_from=None
    if '--resume-fixture' in sys.argv:
        previous=Path(sys.argv[sys.argv.index('--resume-fixture')+1]).resolve()
        if previous.parent.parent != OUT.resolve() or not previous.parent.name.startswith('account-PhoneLifecycle-'):
            raise ValueError('resume must use the original isolated phone fixture')
        evidence_path=previous.parent/'evidence.json';old=json.loads(evidence_path.read_text())
        if not any(s['step']=='phone-registration' and s['checks'].get('new_account_zero_balance') for s in old['steps']):
            raise ValueError('original native registration checkpoint missing')
        for name in ('server.py','account_security.py','account_phone.py'):
            if old['source_sha256'][name] != hashlib.sha256((SERVER/name).read_bytes()).hexdigest():raise ValueError('resume service input changed')
        shutil.copytree(previous,fixture)
        connection={'url':'http://127.0.0.1:0','port':0,'user':'xiaoman','pw':'unused-'+secrets.token_hex(16)}
        resumed_from={'evidence':str(evidence_path.relative_to(OUT)),'sha256':hashlib.sha256(evidence_path.read_bytes()).hexdigest()}
    else:
        with (run/'demo-start.log').open('w') as log:
            r=subprocess.run([PY,'scripts/demo/ledger.py','start','--dir',str(fixture),'--json'],cwd=ROOT,env=ENV,stdout=log,stderr=subprocess.STDOUT,timeout=90)
        (run/'demo-start.log').chmod(0o600)
        if r.returncode: raise RuntimeError('original demo fixture failed')
        connection=json.loads((fixture/'ledger.json').read_text())
        subprocess.run([PY,'scripts/demo/ledger.py','stop','--dir',str(fixture)],cwd=ROOT,env=ENV,stdout=subprocess.DEVNULL,check=True)
    cfg={'EDU_SMS_ENABLED':'1','EDU_SMTP_USER':'hi@example.test','EDU_SMTP_HOST':'example.test',
         'ALIYUN_SMS_SIGN_NAME':'隔离验收'} if offline else remote_configuration()
    os.environ.update(cfg)
    os.environ.update(EDU_POINTS_HOME=str(fixture/'home'),EDU_POINTS_STATIC=str(fixture/'static'),EDU_POINTS_PORT=str(connection['port']))
    sys.path.insert(0,str(SERVER))
    import server, account_security, account_phone
    if case=='EmailBinding':
        users=server.load_users();rec=users['users'][connection['user']]
        rec.update(email='',email_verified=False)
        server.save_users(users)
    # The historical authorized recipient pattern is hi+treasury-* on this Mailu.
    domain=cfg['EDU_SMTP_USER'].split('@')[1]
    if cfg['EDU_SMTP_USER'].split('@')[0]!='hi': raise RuntimeError('unexpected historical mailbox')
    suffix=secrets.token_hex(4)
    addresses=['hi+treasury-native-'+suffix+'@'+domain,'hi+treasury-native-'+suffix+'-new@'+domain]
    def owner_phone():
        # The registered owner number lives in the private environment file; read only that value, never log it.
        for line in (Path.home()/'.personal_env').read_text().splitlines():
            hit=re.match(r'\s*(?:export\s+)?(PERSONAL_PHONE_CN|USER_PHONE)=(.*)',line)
            if hit and hit.group(2).strip():return shlex.split(hit.group(2))[0]
    phone='13800000000' if offline else os.environ.get('PERSONAL_PHONE_CN') or os.environ.get('USER_PHONE') or owner_phone()
    if not phone: raise RuntimeError('no registered owner phone')
    phone=account_phone.phone(phone)
    phone_new=account_phone.phone('13900000000') if offline else account_phone.phone(re.search(r'第二个本人授权号码：[\s*]*(1[3-9]\d{9})',(LEGACY.parent.parent/'round6.md').read_text()).group(1))
    # Both recipients were authorized in the original private task material.
    # A current missing receipt is a failed/deferred flow, never a waiver.
    bind_only='--bind-only' in sys.argv
    allowed_phones={phone,phone_new}
    allowed_addresses=set(addresses)
    secret_values=[];events=[];steps=[];sent={'sms':0,'mail':0};attempted={'sms':0,'mail':0};mail_pending=[];notice_pending=[]
    prior={'sms':0,'mail':0}
    for old_run in OUT.glob('account-*'):
        evidence=old_run/'attempts.json' if (old_run/'attempts.json').exists() else old_run/'evidence.json'
        if not evidence.exists():continue
        record=json.loads(evidence.read_text());previous=record.get('messages_attempted',record.get('messages_sent',{}))
        for kind in prior:prior[kind]+=previous.get(kind,0)
    def checkpoint():
        data={'case':case,'offline_diagnostic_only':offline,'messages_sent':sent,'messages_attempted':attempted,'steps':steps,'events':events,'source_sha256':{'AccountUITests.swift':test_sha},'resumed_from':resumed_from}
        temp=run/'attempts.tmp';temp.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n');temp.chmod(0o600);temp.replace(run/'attempts.json')
    original_send=account_security.send_mail
    last_sms=0;baseline=0;offline_mail={};offline_sms={};last_phone_request={}
    otp_helper='/Users/tianli/Dev/tools/dev/lib/tools/cc/sms_otp.py'
    # The canonical local Messages helper is now readable on this Mac. Only a
    # fresh signature-matched code is returned, in memory; never print it.
    def otp(*words,timeout=10):
        return subprocess.run([PY,otp_helper,*words],text=True,capture_output=True,timeout=timeout)
    def mailbox():
        m=imaplib.IMAP4_SSL(cfg['EDU_SMTP_HOST'],993,timeout=20)
        m.login(cfg['EDU_SMTP_USER'],cfg['EDU_SMTP_PASSWORD']);m.select('INBOX',readonly=True);return m
    mail_uid=0
    if not offline:
        with contextlib.closing(mailbox()) as m:
            _, rows=m.uid('search',None,'ALL');mail_uid=max(map(int,rows[0].split()),default=0)
    def send_mail(address,subject,text):
        ensure_task_active(real_transport=not offline)
        if address not in allowed_addresses or attempted['mail']+prior['mail']>=20: raise account_security.Fault('test recipient/budget guard',503)
        if offline:
            hit=re.search(r'验证码：(\d{6})',text)
            if hit:offline_mail[address]=hit.group(1)
        else:
            attempted['mail']+=1
            checkpoint();original_send(address,subject,text);sent['mail']+=1
        if '验证码' in subject:mail_pending.append(address)
        else:notice_pending.append((address,subject,time.time()))
        events.append({'transport':'mock-mail' if offline else 'real-mail','smtp_accepted':not offline,'kind':'code' if '验证码' in subject else 'security-notification','recipient_sha256':hashlib.sha256(address.encode()).hexdigest()})
        checkpoint()
    account_security.send_mail=send_mail
    class OfflineGateway:
        config={'sign_name':'隔离验收'}
        def send(self,number,purpose,out_id):
            offline_sms[out_id]=(number,purpose)
            return {'status':'provider_accepted','request_id':'mock','biz_id':out_id}
        def check(self,number,purpose,out_id,code):
            return offline_sms.get(out_id)==(number,purpose) and code=='246810'
    real_gateway=OfflineGateway() if offline else account_phone.adapter().AliyunSmsAuth()
    if offline:account_phone.RESEND_SECONDS=1
    class ObservedGateway:
        config=real_gateway.config
        def send(self,number,purpose,out_id):
            nonlocal last_sms,baseline
            ensure_task_active(real_transport=not offline)
            if number not in allowed_phones or attempted['sms']+prior['sms']>=12:raise account_security.Fault('test recipient/budget guard',503)
            if not offline:
                b=otp('baseline',timeout=20)
                if b.returncode:raise account_security.Fault('SMS forwarding unavailable',503)
                baseline=int(b.stdout.strip());attempted['sms']+=1;checkpoint()
            reply=real_gateway.send(number,purpose,out_id)
            last_phone_request.update(number=number, purpose=purpose, request_id=out_id)
            last_sms=time.time()
            if not offline:sent['sms']+=1
            events.append({'transport':'mock-sms' if offline else 'real-sms','provider_accepted':not offline and reply.get('status')=='provider_accepted','purpose':purpose,'request_id_sha256':hashlib.sha256(out_id.encode()).hexdigest()})
            checkpoint()
            return reply
        def check(self,*args):return real_gateway.check(*args)
    account_phone.gateway=lambda:ObservedGateway()
    class ProductHandler(server.H):
        def log_message(self,*args):pass
        def _json(self,status,obj,cookie=None):
            events.append({'path':self.path,'status':status,'ok':obj.get('ok'),'provider_accepted':obj.get('provider_accepted'),'notification_sent':obj.get('notification_sent')})
            return super()._json(status,obj,cookie)
    product=server.ThreadingHTTPServer(('127.0.0.1',connection['port']),ProductHandler)
    connection.update(port=product.server_port,url='http://127.0.0.1:'+str(product.server_port))
    thread=threading.Thread(target=product.serve_forever,daemon=True);thread.start()
    passphrase='Native account '+secrets.token_hex(12)
    original_user=None;original_entries=None;peer=None
    def current_user():
        users=server.load_users()
        if case=='EmailBinding':return connection['user']
        if case.startswith('Email'):return server.find_by_email(users,addresses[1]) or server.find_by_email(users,addresses[0])
        if case in ('PhoneBinding','PasswordLogin'):return connection['user']
        return account_phone.find(users,phone)
    def ledger_signature(user):
        return [(e['id'],e['pts'],e['label']) for e in server.load_ledger(user)['entries']]
    if resumed_from:
        original_user=current_user()
        if not original_user:raise RuntimeError('registered owner phone checkpoint missing')
        original_entries=ledger_signature(original_user)
    def receive_notices():
        if offline:
            received=len(notice_pending);notice_pending.clear();return received
        received=0
        for address,subject,sent_at in list(notice_pending):
            deadline=time.monotonic()+60;found=False
            while time.monotonic()<deadline and not found:
                with contextlib.closing(mailbox()) as m:
                    _,ids=m.uid('search',None,'UID',str(mail_uid+1)+':*')
                    for uid in ids[0].split():
                        if int(uid)<=mail_uid:continue
                        _,content=m.uid('fetch',uid,'(RFC822)')
                        raw=next(row[1] for row in content if isinstance(row,tuple))
                        msg=email.message_from_bytes(raw)
                        decoded=str(email.header.make_header(email.header.decode_header(msg.get('Subject',''))))
                        if address.lower() in str(msg.get('To','')).lower() and decoded==subject:
                            found=True;break
                if not found:time.sleep(2)
            if not found:raise RuntimeError('authorized security notice not received')
            events.append({'transport':'real-mail','imap_received':True,'kind':'security-notification','recipient_sha256':hashlib.sha256(address.encode()).hexdigest()})
            notice_pending.remove((address,subject,sent_at))
            received+=1
        return received
    def native_peer(mode):
        peer_connection=dict(connection)
        peer_connection['user']=addresses[0] if case=='EmailBinding' else addresses[1] if case.startswith('Email') else phone if case=='PhoneLifecycle' else connection['user']
        peer_connection['pw']=passphrase if case=='PhoneLifecycle' or (case.startswith('Email') and case!='EmailBinding') else connection['pw']
        p=run/'peer-private.json';p.write_text(json.dumps(peer_connection));p.chmod(0o600)
        runner=max((native/'runners').glob(platform+'-ui-*/runner.json'),key=lambda q:q.stat().st_mtime)
        peer_out=run/(mode+'-'+str(time.time_ns()))
        try:
            for attempt in range(2):
                r=subprocess.run([PY,str(ROOT/'scripts/accept/account_peer.py'),mode,str(p),receipt,str(peer_out),str(runner)],env=ENV,capture_output=True,timeout=210)
                # Retry only a failure before any UI ran (e.g. the shared app registry read while another
                # project's file was being replaced); a UI result is never retried.
                if not r.returncode or (peer_out/'ui.log').exists():break
                time.sleep(4)
            data=r.stdout+r.stderr
            for value in secret_values+[passphrase,passphrase+' changed',token,phone,*addresses,connection['pw']]:data=data.replace(value.encode(),b'<redacted>')
            (run/(mode+'.log')).write_bytes(data)
            if r.returncode:raise RuntimeError('native peer '+mode+' failed')
            events.append({'native_peer':mode,'actual_native_ui':True,'cookie_injected':False,
                           'proof':str((peer_out/'proof.json').relative_to(OUT)),
                           'proof_sha256':hashlib.sha256((peer_out/'proof.json').read_bytes()).hexdigest()})
        finally:p.unlink(missing_ok=True)
    def mark(step):
        nonlocal original_user,original_entries,peer
        user=current_user();checks={}
        if step in ('email-change','password-change','email-recovery-and-data','email-binding-preserved'):
            checks['security_notices_received']=receive_notices()
            if step in ('email-change','password-change','email-recovery-and-data'):assert checks['security_notices_received']>=1
        if step in ('native-password-login','native-session-restore','native-logout-reopen'):
            assert user==connection['user'] and server.balance_of(server.load_ledger(user)['entries'])==1133
            if step=='native-password-login':
                assert any(e.get('path')=='/api/login' and e.get('status')==401 for e in events)
                assert any(e.get('path')=='/api/login' and e.get('status')==200 for e in events)
                checks['native_bad_password_then_success_original_account']=True
            elif step=='native-session-restore':
                assert events[-1].get('path')=='/api/state' and events[-1].get('status')==200
                checks['actual_native_session_survived_relaunch']=True
            else:
                assert any(e.get('path')=='/api/logout' and e.get('status')==200 for e in events)
                assert events[-1].get('path')=='/api/state' and events[-1].get('status')==401
                checks['native_logout_not_restored_after_relaunch']=True
        elif step in ('email-registration','phone-registration'):
            assert user and user!=connection['user']
            assert server.balance_of(server.load_ledger(user)['entries'])==0
            original_user=user;checks['new_account_zero_balance']=True
        elif step=='business-use':
            assert user==original_user and server.balance_of(server.load_ledger(user)['entries'])>0
            original_entries=ledger_signature(user);checks['native_earn_persisted']=True
        elif step=='email-change':
            assert user==original_user and ledger_signature(user)==original_entries
            assert server.load_users()['users'][user]['email']==addresses[1]
            peer=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(CookieJar()))
            peer.open(urllib.request.Request(connection['url']+'/api/login',data=json.dumps({'u':addresses[1],'p':passphrase}).encode(),headers={'Content-Type':'application/json'}),timeout=10).read()
            checks['original_id_and_ledger_preserved']=True
            native_peer('PeerStart');checks['second_native_device_signed_in']=True
        elif step=='password-change':
            assert user==original_user and ledger_signature(user)==original_entries
            try:peer.open(connection['url']+'/api/state',timeout=10);raise AssertionError('old peer cookie accepted')
            except urllib.error.HTTPError as e:assert e.code==401
            checks['independent_http_session_invalidated']=True
            if case.startswith('Email'):
                native_peer('PeerCheck');checks['second_native_device_session_invalidated']=True
        elif step=='phone-password-set':
            assert user==original_user and server.load_users()['users'][user].get('password_set')
            assert any(e.get('path')=='/api/password_set' and e.get('status')==200 for e in events)
            native_peer('PeerStart');checks['native_password_set_and_second_device_signed_in']=True
        elif step.endswith('recovery-and-data'):
            assert user==original_user
            if original_entries is not None:assert ledger_signature(user)==original_entries
            checks['original_id_and_business_preserved']=True
            if case=='PhoneLifecycle':
                native_peer('PeerCheck');checks['second_native_device_session_invalidated']=True
        elif step in ('email-account-deletion','phone-account-deletion','passwordless-account-deletion'):
            assert current_user() is None and original_user not in server.load_users()['users']
            checks['actual_account_removed']=True
        elif step in ('email-binding-preserved','email-binding-login'):
            assert server.find_by_email(server.load_users(),addresses[0])==connection['user']
            assert server.balance_of(server.load_ledger(connection['user'])['entries'])==1133
            assert server.load_users()['users'][connection['user']]['email_verified']
            checks['old_account_email_bound_original_ledger_preserved']=True
            original_user=user;original_entries=ledger_signature(user)
            if step=='email-binding-login':
                peer=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(CookieJar()))
                peer.open(urllib.request.Request(connection['url']+'/api/login',data=json.dumps({'u':addresses[0],'p':connection['pw']}).encode(),headers={'Content-Type':'application/json'}),timeout=10).read()
                native_peer('PeerStart');checks['second_native_device_signed_in']=True
        elif step in ('phone-binding-peer-start','phone-change-peer-start'):
            native_peer('PeerStart');checks['second_native_device_signed_in']=True
        elif step=='phone-binding-preserved':
            assert account_phone.find(server.load_users(),phone)==connection['user']
            assert server.balance_of(server.load_ledger(connection['user'])['entries'])==1133
            checks['old_account_phone_bound_ledger_preserved']=True
            native_peer('PeerCheck');checks['second_native_device_session_invalidated']=True
        elif step=='phone-change-preserved':
            assert account_phone.find(server.load_users(),phone_new)==connection['user']
            assert account_phone.find(server.load_users(),phone) is None
            assert server.balance_of(server.load_ledger(connection['user'])['entries'])==1133
            native_peer('PeerCheck');checks['both_numbers_verified_original_id_and_ledger_preserved']=True;checks['second_native_device_session_invalidated']=True
        elif step=='phone-change-missing-second-number':
            checks['complete']=False;checks['reason']='Only one distinct registered owner number; gate has no waiver.'
        elif step in ('phone-wrong-code-then-correct','email-wrong-code-then-correct'):
            path='/api/phone_verify' if step.startswith('phone') else '/api/email_verify'
            seen=[e.get('status') for e in events if e.get('path')==path]
            assert 400 in seen and seen[-1]==200 and seen.index(400)<len(seen)-1
            checks['wrong_code_refused_then_same_challenge_accepted']=True
        else:checks['native_step_reached']=True
        record={'step':step,'checks':checks,'source':'actual production server readback after native UI action'}
        steps.append(record);checkpoint();return {'ok':True}
    token=secrets.token_hex(32)
    class Coordinator(BaseHTTPRequestHandler):
        def log_message(self,*args):pass
        def do_GET(self):
            nonlocal mail_uid
            try:
                if self.headers.get('X-Points-QA')!=token:raise ValueError('unauthorized')
                action=self.path.strip('/')
                if action=='sms-ready':
                    time.sleep(max(0,last_sms+(2 if offline else 61)-time.time()));reply={'ok':True}
                elif action=='otp/phone':
                    if case=='PhoneLifecycle' and not steps:
                        # Exercise original HTTP resend/idempotency guards on
                        # the same challenge the native form just requested.
                        # Both calls must leave actual provider-send count fixed.
                        before_send=attempted['sms']
                        def replay(request_id):
                            request=urllib.request.Request(connection['url']+'/api/phone_send',
                                data=json.dumps({'phone':last_phone_request['number'], 'purpose':'register',
                                                 'request_id':request_id}).encode(),
                                headers={'Content-Type':'application/json'})
                            try:
                                with urllib.request.urlopen(request,timeout=15) as response:
                                    response.read(); return response.status
                            except urllib.error.HTTPError as error:
                                error.read();return error.code
                        assert replay(last_phone_request['request_id'])==200
                        assert replay(secrets.token_hex(16))==429
                        assert attempted['sms']==before_send
                        events.append({'actual_http_abuse_guards':True,'same_request_replayed_without_send':True,
                                       'resend_refused_status':429,'provider_send_count_unchanged':True})
                    if offline:code='246810'
                    else:
                        result=otp('wait','--baseline',str(baseline),'--match',cfg['ALIYUN_SMS_SIGN_NAME'],'--timeout','85',timeout=100)
                        if result.returncode:raise RuntimeError('fresh signed SMS not received')
                        code=result.stdout.strip()
                    if not re.fullmatch(r'\d{6}',code):raise ValueError('invalid received code')
                    secret_values.append(code);events.append({'transport':'mock-sms' if offline else 'real-sms','actual_device_forward_received':not offline,'signature_filter':not offline})
                    reply={'ok':True,'code':code}
                elif action=='otp/email':
                    address=mail_pending[-1];deadline=time.monotonic()+80;code=offline_mail.get(address) if offline else None
                    while time.monotonic()<deadline and not code:
                        with contextlib.closing(mailbox()) as m:
                            _, ids=m.uid('search',None,'UID',str(mail_uid+1)+':*')
                            for uid in ids[0].split():
                                if int(uid)<=mail_uid:continue
                                _, content=m.uid('fetch',uid,'(RFC822)')
                                raw=next(row[1] for row in content if isinstance(row,tuple))
                                message=email.message_from_bytes(raw)
                                if address.lower() not in str(message.get('To','')).lower():continue
                                body=''.join(part.get_payload(decode=True).decode(part.get_content_charset() or 'utf-8','replace') for part in message.walk() if part.get_content_type()=='text/plain')
                                hit=re.search(r'验证码：(\d{6})',body)
                                if hit:code=hit.group(1);mail_uid=int(uid);break
                        if not code:time.sleep(2)
                    if not code:raise RuntimeError('fresh authorized email not received')
                    secret_values.append(code);events.append({'transport':'mock-mail' if offline else 'real-mail','imap_received':not offline,'authorized_recipient_sha256':hashlib.sha256(address.encode()).hexdigest()})
                    reply={'ok':True,'code':code}
                elif action.startswith('mark/'):reply=mark(action[5:])
                else:raise ValueError('unknown action')
            except Exception as e:
                reply={'ok':False,'error_class':type(e).__name__}
                events.append({'coordinator_failure':action,'error_class':type(e).__name__})
            data=json.dumps(reply).encode();self.send_response(200);self.send_header('Content-Length',str(len(data)));self.send_header('Content-Type','application/json');self.end_headers();self.wfile.write(data)
    control=ThreadingHTTPServer(('127.0.0.1',0),Coordinator)
    control_thread=threading.Thread(target=control.serve_forever,daemon=True);control_thread.start()
    rule=next(r for r in server.rules()['rules'] if r['kind']=='fixed' and r.get('pts',0)>0)
    connection['qa']={'COORDINATOR':'http://127.0.0.1:'+str(control.server_port),'COORDINATOR_TOKEN':token,
        'PHONE':phone,'PHONE_NEW':phone_new,'EMAIL':addresses[0],'EMAIL_NEW':addresses[1],'ACCOUNT_PASSWORD':passphrase,
        'EARN_LABEL':rule['label']+'，'+str(rule['pts'])+'积分','MODE':'PhoneResume' if resumed_from else 'BindOnly' if bind_only else case}
    private=run/'private-connection.json';private.write_text(json.dumps(connection));private.chmod(0o600)
    product_log=Path(sys.argv[sys.argv.index('--product-log')+1]) if '--product-log' in sys.argv else OUT/'product-clean.log'
    receipt=next(json.loads(line)['receipt'] for line in product_log.read_text().splitlines() if line.startswith('{') and 'receipt' in line)
    try:
        args=[PY,str(LEGACY/'lane_dev.py') if offline else 'scripts/accept/platform_ui.py','--phase','ui','--platform',platform,'--case','testAccount'+('EmailTransport' if case=='EmailBinding' else case),'--receipt',receipt,'--connection',str(private),'--out',str(native),'--functional-only','--budget-min','8']
        with (run/'lane.log').open('w') as log:r=subprocess.run(args,cwd=ROOT,env=ENV,stdout=log,stderr=subprocess.STDOUT,timeout=1980)
        code=r.returncode
    finally:
        control.shutdown();product.shutdown();control.server_close();product.server_close();thread.join();control_thread.join()
        private.unlink(missing_ok=True)
        # XCTest activity strings can include typed secrets. Keep only redacted
        # logs as evidence; no received code is written into our records.
        for log in [*run.rglob('*.log'),*native.glob('*.log')]:
            raw=log.read_bytes();data=raw
            for value in secret_values+[passphrase,passphrase+' changed',passphrase+' recovered',token,phone,phone_new,*addresses,connection['pw']]:data=data.replace(value.encode(),b'<redacted>')
            if data!=raw:log.write_bytes(data)
            redact(log)
        evidence={'case':case,'exit_code':locals().get('code'),'platform':platform,
            'native_proof_sha256':hashlib.sha256((native/'proof.json').read_bytes()).hexdigest() if (native/'proof.json').exists() else None,
            'account_input_sha256':os.environ['POINTS_ACCOUNT_INPUT_SHA256'],'producer_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'receipt_sha256':hashlib.sha256(Path(receipt).read_bytes()).hexdigest(),'client_environment':'source-verified actual Release '+('iPhone' if platform=='iphone' else 'iPad')+' simulator App through original XCTest lane',
            'service_environment':'isolated current production server.py/account_security.py/account_phone.py; no production users',
            'mail_transport':'not_tested' if no_transport else 'mock' if offline else 'real' if sent['mail'] else 'not_tested','sms_transport':'not_tested' if no_transport else 'mock' if offline else 'real' if sent['sms'] else 'not_tested','offline_diagnostic_only':offline and not no_transport,'messages_sent':sent,'messages_attempted':attempted,'steps':steps,'events':events,
            'resumed_from':resumed_from,'limitations':['Only complete, current-input actual flows may populate the formal account index.','Offline runs are diagnostics and never real-transport evidence.'],
            'source_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in [SERVER/'server.py',SERVER/'account_security.py',SERVER/'account_phone.py',ROOT/'Tests/AccountUITests.swift', ROOT/'scripts/accept/platform_ui.py', ROOT/'scripts/accept/account_peer.py']}}
        (run/'native').mkdir(exist_ok=True)
        for name in ('ui.log','proof.json'):
            if (native/name).exists():shutil.copy2(native/name,run/'native'/name)
        (run/'evidence.json').write_text(json.dumps(evidence,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'case':case,'exit_code':code,'messages_sent':sent,'completed_native_steps':[s['step'] for s in steps],'evidence':str(run/'evidence.json')}))
    return code

if __name__=='__main__':sys.exit(main())

