"""Build an isolated playtest copy from the existing complete game; add this feature only."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[2]


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise RuntimeError('Expected one integration anchor: ' + old[:70])
    return text.replace(old, new, 1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', required=True)
    parser.add_argument('--destination', default=str(ROOT / 'work/playtest-project'))
    args = parser.parse_args()
    source, destination = Path(args.source).resolve(), Path(args.destination).resolve()
    if destination.exists():
        raise SystemExit('Destination already exists; refusing to overwrite a playtest copy')
    if not destination.is_relative_to(ROOT / 'work'):
        raise SystemExit('Playtest destination must stay inside this workspace/work')
    protected = [source / 'scripts' / name for name in ('companion_panel.gd', 'companion_task_client.gd', 'gameplay_interface.gd')]
    before = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in protected}
    destination.mkdir(parents=True)
    ignore = shutil.ignore_patterns('.git', '.godot', '.env', '.env.*', '__pycache__', '*.sqlite3*', '*.log', 'output', 'outputs', 'work')
    for name in ('scripts', 'scenes', 'assets', 'addons', 'data'):
        if (source / name).is_dir():
            shutil.copytree(source / name, destination / name, ignore=ignore)
    for name in ('project.godot', 'icon.svg'):
        shutil.copy2(source / name, destination / name)
    # These three files retain all changes in the existing game. Only exact feature
    # anchors are edited, rather than replacing the local game with a different PR.
    panel = destination / 'scripts/companion_panel.gd'
    text = panel.read_text(encoding='utf-8')
    anchor = '\tui.line(side)\n'
    text = replace_once(text, anchor, anchor + '\tif OS.get_environment("XIUXIAN_WECHAT_LINK_ENABLED") == "1":\n\t\tui.button(side, "连接微信 / 查看连接", ui.open_wechat_link)\n')
    panel.write_text(text, encoding='utf-8')
    client = destination / 'scripts/companion_task_client.gd'
    text = client.read_text(encoding='utf-8')
    text = replace_once(text, 'var poll_seconds = 15.0\n', 'var poll_seconds = 15.0\nvar live_account_service = false\n')
    anchor = '\tread_token = OS.get_environment("XIUXIAN_COMPANION_TASK_READ_TOKEN").strip_edges()\n'
    text = replace_once(text, anchor, anchor + '\tlive_account_service = OS.get_environment("XIUXIAN_WECHAT_LINK_ENABLED") == "1"\n\tif live_account_service:\n\t\tpoll_seconds = 2.0\n')
    anchor = '\tif not configured():\n\t\treturn\n\tif owner_scope != scope():'
    text = replace_once(text, anchor, '\tif live_account_service:\n\t\tif not game.account_api.is_authenticated():\n\t\t\treturn\n\t\tendpoint = game.account_api.authenticated_service_url + "/api/v1/companion/state"\n\t\tread_token = game.account_api.token\n' + anchor)
    client.write_text(text, encoding='utf-8')
    interface = destination / 'scripts/gameplay_interface.gd'
    text = interface.read_text(encoding='utf-8')
    text = replace_once(text, 'var wechat_task_label: Label\n', 'var wechat_task_label: Label\nvar wechat_link_panel: Control\n')
    anchor = '\tcompanion_panel = null\n\twechat_task_label = null\n'
    text = replace_once(text, anchor, anchor + '\tif is_instance_valid(wechat_link_panel):\n\t\twechat_link_panel.queue_free()\n\twechat_link_panel = null\n')
    current = (ROOT / 'scripts/gameplay_interface.gd').read_text(encoding='utf-8')
    function = current.split('func open_wechat_link() -> void:\n', 1)[1].split('\nfunc ', 1)[0]
    text += '\nfunc open_wechat_link() -> void:\n' + function + '\n'
    interface.write_text(text, encoding='utf-8')
    shutil.copy2(ROOT / 'scripts/wechat_link_panel.gd', destination / 'scripts/wechat_link_panel.gd')
    after = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in protected}
    assert after == before
    (ROOT / 'work/playtest-source-integrity.json').write_text(json.dumps({'source': str(source), 'playtest': str(destination), 'original_scripts_unchanged': before == after}, indent=2), encoding='utf-8')
    print(json.dumps({'playtest_project': str(destination), 'original_scripts_unchanged': True}))


if __name__ == '__main__':
    main()
