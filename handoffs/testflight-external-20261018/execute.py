"""2026-10-18 单次 ASC TestFlight 操作与回执；不构建、不上传、不操作正式审核。"""
import json
from pathlib import Path
import subprocess
import sys
from datetime import datetime, timezone

sys.path.insert(0, '/Users/tianli/Dev/tools/dev/lib/tools/macapp/ios')
import asc
from asc_release import all_pages as pages

OUT = Path(__file__).resolve().parent
subprocess.run([
    '/Users/tianli/Dev/.venv/bin/python',
    '/Users/tianli/Dev/tools/cc-home/tools/harness/claims.py',
    '--pid', '32970', '--session',
    'chapter-task:ea00a6ec028749e49e77b24bb8426d4b', 'check', str(OUT),
], check=True)
base = json.loads((OUT / 'preflight.json').read_text())
APP, BID, VID = base['app_id'], base['build']['id'], base['source_version_id']
EMAILS = ['zengtianli1@126.com', 'zengtianli2@126.com', 'zengtianli3@126.com']
receipt_path = OUT / 'steps.json'
receipt = json.loads(receipt_path.read_text()) if receipt_path.exists() else {
    'app_id': APP, 'build_id': BID, 'source_commit': base['source_commit'], 'events': [],
}


def slim(resource):
    return {k: resource[k] for k in ('type', 'id', 'attributes') if k in resource}


def save():
    receipt_path.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n')


def event(step, action, data):
    receipt['events'].append(dict(at=datetime.now(timezone.utc).isoformat(),
                                  step=step, action=action, data=data))
    save()
    print(json.dumps(dict(step=step, action=action), ensure_ascii=False), flush=True)


def post(path, body):
    assert path in {
        '/betaGroups', '/betaTesters', '/betaAppLocalizations',
        '/betaBuildLocalizations', '/betaAppReviewSubmissions',
    } or (path.startswith('/betaGroups/') and '/relationships/' in path)
    return asc.post(path, body)


def patch(kind, identifier, attributes):
    assert kind in {'betaAppReviewDetails', 'betaAppLocalizations',
                    'betaBuildLocalizations', 'buildBetaDetails'}
    return asc.patch(f'/{kind}/{identifier}', {
        'data': dict(type=kind, id=identifier, attributes=attributes),
    })


def upsert_locale(kind, relationship, owner_id, locale, attributes, existing):
    found = next((x for x in existing if x['attributes']['locale'] == locale), None)
    if found:
        identifier = found['id']
        if any(found['attributes'].get(k) != v for k, v in attributes.items()):
            patch(kind, identifier, attributes)
    else:
        owner_type = {'app': 'apps', 'build': 'builds'}[relationship]
        identifier = post('/' + kind, {'data': {
            'type': kind, 'attributes': dict(attributes, locale=locale),
            'relationships': {relationship: {'data': dict(type=owner_type, id=owner_id)}},
        }})['data']['id']
    result = asc.get(f'/{kind}/{identifier}')['data']
    assert all(result['attributes'].get(k) == v for k, v in attributes.items())
    return result


def formal_snapshot():
    versions = pages(f'/apps/{APP}/appStoreVersions', {'limit': '200'})
    return {
        'versions': sorted([slim(v) for v in versions], key=lambda v: v['id']),
        'submissions': sorted([slim(s) for s in pages('/reviewSubmissions', {
            'filter[app]': APP, 'limit': '200',
        })], key=lambda s: s['id']),
        'version_builds': {v['id']: asc.get(
            f"/appStoreVersions/{v['id']}/relationships/build")['data'] for v in versions},
    }


def run():
    builds = pages('/builds', {'filter[app]': APP,
        'filter[preReleaseVersion.platform]': 'IOS', 'sort': '-uploadedDate', 'limit': '200'})
    valid = [b for b in builds if b['attributes']['processingState'] == 'VALID'
             and b['attributes']['expired'] is False
             and datetime.fromisoformat(b['attributes']['expirationDate']) > datetime.now(timezone.utc)]
    assert valid and valid[0]['id'] == BID, 'Latest eligible build changed; inspect first'
    pre = asc.get(f'/builds/{BID}/preReleaseVersion')['data']
    assert pre['attributes']['platform'] == 'IOS'
    event(3, 'validate_existing_build', {'selected': slim(valid[0]),
          'prerelease': slim(pre), 'all_ios_builds': [slim(b) for b in builds]})

    groups = pages(f'/apps/{APP}/betaGroups', {'limit': '200'})
    matches = [g for g in groups if g['attributes']['name'] == 'Growth Treasury iOS Beta'
               and g['attributes']['isInternalGroup'] is False]
    assert len(matches) <= 1
    if matches:
        group, action = matches[0], 'reuse_external_group'
    else:
        group = post('/betaGroups', {'data': {
            'type': 'betaGroups', 'attributes': {'name': 'Growth Treasury iOS Beta',
                'isInternalGroup': False, 'publicLinkEnabled': False},
            'relationships': {'app': {'data': dict(type='apps', id=APP)}},
        }})['data']
        action = 'create_external_group'
    gid = group['id']
    receipt['group_id'] = gid
    group = asc.get(f'/betaGroups/{gid}')['data']
    assert group['attributes']['isInternalGroup'] is False
    event(3, action, slim(group))

    for email in EMAILS:
        members = pages(f'/betaGroups/{gid}/betaTesters', {'limit': '200'})
        response, action = {}, 'tester_already_member'
        if not any(t['attributes']['email'].lower() == email for t in members):
            existing = pages('/betaTesters', {
                'filter[apps]': APP, 'filter[email]': email, 'limit': '200'})
            assert len(existing) <= 1
            if existing:
                response = post(f'/betaGroups/{gid}/relationships/betaTesters', {
                    'data': [dict(type='betaTesters', id=existing[0]['id'])]})
                action = 'add_existing_app_tester'
            else:
                response = post('/betaTesters', {'data': {'type': 'betaTesters',
                    'attributes': {'email': email}, 'relationships': {'betaGroups': {
                        'data': [dict(type='betaGroups', id=gid)]}}}})
                action = 'create_tester_in_external_group'
        members = pages(f'/betaGroups/{gid}/betaTesters', {'limit': '200'})
        member = next(t for t in members if t['attributes']['email'].lower() == email)
        event(3, action, {'email': email, 'response_status': response.get('status'),
              'response_id': response.get('data', {}).get('id'), 'readback': slim(member)})

    formal_review = asc.get(f'/appStoreVersions/{VID}/appStoreReviewDetail')['data']
    source = formal_review['attributes']
    keys = ['contactFirstName', 'contactLastName', 'contactPhone', 'contactEmail',
            'demoAccountRequired', 'demoAccountName', 'demoAccountPassword', 'notes']
    assert all(source.get(k) for k in keys[:4]), 'Formal review contact incomplete'
    attributes = {k: source[k] for k in keys if source.get(k) is not None}
    beta = asc.get(f'/apps/{APP}/betaAppReviewDetail')['data']
    status = 'unchanged'
    if any(beta['attributes'].get(k) != v for k, v in attributes.items()):
        status = patch('betaAppReviewDetails', beta['id'], attributes)
    beta = asc.get(f'/apps/{APP}/betaAppReviewDetail')['data']
    field_matches = {k: beta['attributes'].get(k) == v for k, v in attributes.items()}
    assert all(field_matches.values())
    event(4, 'copy_formal_review_to_beta', {'source_version_id': VID,
        'source_detail_id': formal_review['id'], 'beta_detail_id': beta['id'],
        'patch_status': status, 'field_matches_source': field_matches,
        'demoAccountRequired': beta['attributes'].get('demoAccountRequired'),
        'credentials_saved_in_receipt': False})

    existing = pages(f'/apps/{APP}/betaAppLocalizations', {'limit': '200'})
    for loc in base['store_localizations']:
        a = loc['attributes']
        privacy = next(x['attributes']['privacyPolicyUrl'] for x in base['app_info_localizations']
                       if x['attributes']['locale'] == a['locale'] and x['attributes'].get('privacyPolicyUrl'))
        assert a.get('description')
        attributes = dict(description=a['description'], feedbackEmail=source['contactEmail'],
                          privacyPolicyUrl=privacy)
        if a.get('marketingUrl'):
            attributes['marketingUrl'] = a['marketingUrl']
        rb = upsert_locale('betaAppLocalizations', 'app', APP, a['locale'], attributes, existing)
        event(4, 'beta_description', {'id': rb['id'], 'locale': a['locale'],
            'description_matches_formal': True, 'feedback_email_matches_review_contact': True,
            'privacyPolicyUrl': privacy})

    what = {
        'zh-Hans': '请在 iPhone 或 iPad 上试用成长小金库的主要流程：手机号验证码或邮箱账号登录，查看账本与积分余额，记录固定项目和参数项目、临时加减分并撤销，查看积分走势，兑换奖励，管理项目与奖励，以及账户设置、退出和重新登录。请反馈无法完成的操作、余额或记录显示异常、看不懂的提示和不顺手之处；也请留意网络失败后的提示与输入保留。',
        'en-US': 'Please try the main workflows in Growth Treasury on iPhone or iPad: sign in with a phone verification code or email account, view the ledger and balance, record and undo fixed or parameter-based activities and manual adjustments, review trends, redeem rewards, manage activities and rewards, and use account settings, sign out and sign in again. Report tasks you cannot complete, unexpected balances or records, unclear messages, usability problems, and how failed network requests preserve your input.',
    }
    existing = pages(f'/builds/{BID}/betaBuildLocalizations', {'limit': '200'})
    for locale, text in what.items():
        rb = upsert_locale('betaBuildLocalizations', 'build', BID, locale, {'whatsNew': text}, existing)
        event(4, 'what_to_test', slim(rb))

    detail = asc.get(f'/builds/{BID}/buildBetaDetail')['data']
    if detail['attributes'].get('autoNotifyEnabled') is not True:
        patch('buildBetaDetails', detail['id'], {'autoNotifyEnabled': True})
    detail = asc.get(f'/builds/{BID}/buildBetaDetail')['data']
    assert detail['attributes']['autoNotifyEnabled'] is True
    event(5, 'automatic_notification', slim(detail))
    builds = pages(f'/betaGroups/{gid}/builds', {'limit': '200'})
    response = {'status': 'already_associated'}
    if BID not in {b['id'] for b in builds}:
        response = post(f'/betaGroups/{gid}/relationships/builds', {
            'data': [dict(type='builds', id=BID)]})
    builds = pages(f'/betaGroups/{gid}/builds', {'limit': '200'})
    assert BID in {b['id'] for b in builds}
    event(5, 'associate_external_build', {'response': response,
          'group_build_ids': [b['id'] for b in builds]})
    submissions = pages('/betaAppReviewSubmissions', {'filter[build]': BID, 'limit': '200'})
    assert len(submissions) <= 1
    if submissions:
        submission, action = submissions[0], 'reuse_beta_submission'
    else:
        submission = post('/betaAppReviewSubmissions', {'data': {
            'type': 'betaAppReviewSubmissions',
            'relationships': {'build': {'data': dict(type='builds', id=BID)}},
        }})['data']
        action = 'create_beta_submission'
    receipt['beta_submission_id'] = submission['id']
    event(5, action, slim(submission))

    final = {
        'at': datetime.now(timezone.utc).isoformat(),
        'build': slim(asc.get(f'/builds/{BID}')['data']),
        'prerelease': slim(asc.get(f'/builds/{BID}/preReleaseVersion')['data']),
        'group': slim(asc.get(f'/betaGroups/{gid}')['data']),
        'group_build_ids': [b['id'] for b in pages(f'/betaGroups/{gid}/builds', {'limit': '200'})],
        'testers': [slim(t) for t in pages(f'/betaGroups/{gid}/betaTesters', {'limit': '200'})],
        'build_beta_detail': slim(asc.get(f'/builds/{BID}/buildBetaDetail')['data']),
        'beta_submission': slim(asc.get(f"/betaAppReviewSubmissions/{submission['id']}")['data']),
        'beta_build_localizations': [slim(x) for x in pages(f'/builds/{BID}/betaBuildLocalizations', {'limit': '200'})],
        'formal_after': formal_snapshot(),
        'formal_review_detail_unchanged': asc.get(f'/appStoreVersions/{VID}/appStoreReviewDetail')['data']['attributes'] == source,
        'contact_and_demo_matches': field_matches,
    }
    for key in ('versions', 'submissions'):
        base['formal_before'][key].sort(key=lambda x: x['id'])
    final['formal_unchanged'] = final['formal_after'] == base['formal_before']
    assert final['formal_unchanged'] and final['formal_review_detail_unchanged']
    assert set(EMAILS).issubset({t['attributes']['email'].lower() for t in final['testers']})
    assert final['beta_submission']['attributes']['betaReviewState'] in {'WAITING_FOR_REVIEW', 'IN_REVIEW', 'APPROVED'}
    receipt.update(status='configured', final=final)
    event(7, 'final_readback', {'beta_state': final['beta_submission']['attributes']['betaReviewState'],
        'autoNotifyEnabled': final['build_beta_detail']['attributes']['autoNotifyEnabled'],
        'formal_unchanged': final['formal_unchanged'],
        'formal_review_detail_unchanged': final['formal_review_detail_unchanged'],
        'testers': [{k: t['attributes'].get(k) for k in ('email', 'state')} for t in final['testers']]})


if __name__ == '__main__':
    try:
        run()
    except BaseException as exc:
        receipt.update(status='interrupted', error=dict(type=type(exc).__name__, detail=str(exc)))
        save()
        raise
