#!/usr/bin/env python3
"""Local-only bilingual screenshots using the canonical build slots and headless simulator lane."""
from pathlib import Path
import argparse
import contextlib
import html
import json
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(Path.home() / 'Apps/chapter/engine'),
                 str(Path.home() / 'Dev/tools/dev/lib/tools/macapp/ios')]
import sim_lane

OUT = ROOT / 'perf/acceptance/l10n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=['build', 'capture'])
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    receipt = OUT / 'build.json'
    if args.phase == 'build':
        built = sim_lane.build(ROOT, 'PointsDeck', 'iphone', 'Release')
        receipt.write_text(json.dumps(built, ensure_ascii=False, indent=2) + '\n')
        print(json.dumps({'ok': True, 'receipt': str(receipt)}))
        return
    built = sim_lane.reuse_build(receipt, 'points-deck-ios', ROOT, 'iphone', 'PointsDeck', 'Release', False)
    # The real isolated ledger preserves Chinese user/server data. Its untranslated
    # server defaults are recorded separately from the client's catalog coverage.
    scratch = sim_lane.make_temp('points-l10n-ledger.')
    subprocess.run([sys.executable, str(ROOT / 'scripts/demo/ledger.py'), 'start', '--dir', str(scratch), '--json'],
                   check=True, stdout=subprocess.DEVNULL, timeout=120)
    ledger = json.loads((scratch / 'ledger.json').read_text())
    records = []
    before = sim_lane.simulator_app_pids()
    try:
        admission = sim_lane._chapter_sim_admission()
        if admission:
            admission.admit(sim_lane, reuse=False, label='Growth Treasury bilingual UI')
        hook = admission.hooked(sim_lane, label='Growth Treasury bilingual UI') if admission else contextlib.nullcontext()
        device = sim_lane.ensure_device('iphone', 'iPhone-17-Pro', 'Points Localization')
        with hook, sim_lane.Session('iphone', device['udid'], label='Growth Treasury bilingual UI',
                                    lock_wait=0, load_wait=0) as lane:
            lane.install(Path(built['app_path']))
            for language in ['en', 'zh-Hans']:
                for screen in ['0', '1', '2', '3', '4', 'login', 'register', 'security', 'settings']:
                    launch = ['-api_base', ledger['url'], '-dev_user', ledger['user'], '-dev_pw', ledger['pw'],
                              '-AppleLanguages', f'({language})', '-AppleLocale', 'en_US' if language == 'en' else 'zh_CN',
                              '-tab', screen if screen.isdigit() else '0', '-l10n_screen', 'main' if screen.isdigit() else screen]
                    if screen.isdigit():
                        result = lane.launch(built['bundle_id'], launch, 'log', 60, None,
                                             sim_lane.bundle_info(Path(built['app_path']))['executable'], functional_thin=True)
                        if result['errors']:
                            raise sim_lane.LaneError(str(result['errors']))
                    else:
                        sim_lane.simctl('launch', '--terminate-running-process', device['udid'], built['bundle_id'], *launch)
                        # Screens without an authenticated home have no lane-ready event.
                        # Wait for their actual framebuffer to settle, with a finite deadline.
                        time.sleep(2)
                        previous = lane.frame('previous')
                        for attempt in range(8):
                            time.sleep(.6)
                            current = lane.frame(f'stable-{attempt}')
                            if current.diff(previous) <= sim_lane.STABLE_MAX['iphone']:
                                break
                            previous = current
                    shot = lane.shot(OUT / language / f'{screen}.png')
                    records.append({'language': language, 'screen': screen, 'path': str(shot.relative_to(OUT))})
                    lane.terminate(built['bundle_id'])
            if sim_lane.simulator_app_pids() - before:
                raise sim_lane.LaneError('Unexpected Simulator.app window process')
        gallery = '<!doctype html><html lang="en"><meta charset="utf-8"><title>Growth Treasury · Bilingual UI</title><style>body{font:16px system-ui;background:#faf7f0;color:#26332c;margin:24px}section{display:flex;gap:24px;flex-wrap:wrap}figure{margin:0 0 24px}img{width:300px;max-width:100%;border-radius:24px}figcaption{padding:8px}h2{margin-top:36px}</style><h1>Growth Treasury · Bilingual UI</h1><p>Real windowless iPhone simulator. Local synthetic ledger. Chinese server defaults and user content are preserved; see the handoff for backend/shared-layer gaps.</p>'
        for language in ['en', 'zh-Hans']:
            gallery += f'<h2>{language}</h2><section>'
            for record in records:
                if record['language'] == language:
                    gallery += f'<figure><img src="{html.escape(record["path"])}"><figcaption>{html.escape(record["screen"])}</figcaption></figure>'
            gallery += '</section>'
        (OUT / 'index.html').write_text(gallery + '</html>')
        (OUT / 'capture.json').write_text(json.dumps({'ok': True, 'headless': True, 'simulator_app_opened': False,
            'receipt': str(receipt), 'captures': records, 'server_data_preserved': True}, indent=2) + '\n')
        print(json.dumps({'ok': True, 'captures': len(records), 'gallery': str(OUT / 'index.html')}))
    finally:
        subprocess.run([sys.executable, str(ROOT / 'scripts/demo/ledger.py'), 'stop', '--dir', str(scratch)],
                       stdout=subprocess.DEVNULL, timeout=30)


if __name__ == '__main__':
    try:
        main()
    except (sim_lane.Busy, BlockingIOError) as error:
        print(json.dumps({'ok': False, 'deferred': True, 'reason': str(error), 'auto': True}))
        sys.exit(75)
