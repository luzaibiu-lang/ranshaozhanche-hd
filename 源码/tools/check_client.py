"""Run Godot's real parser/import checks without opening a desktop window."""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
executable = next((ROOT/'.tools/godot').glob('*console.exe'))
result = subprocess.run([str(executable), '--headless', '--audio-driver', 'Dummy',
                         '--path', str(ROOT/'源码/client'), '--editor', '--quit'],
                        capture_output=True, text=True, encoding='utf8', errors='replace',
                        creationflags=subprocess.CREATE_NO_WINDOW, timeout=240)
log = result.stdout + result.stderr
# Editor import does not parse every runtime preload. Check the actual entry
# script as well, so a malformed native page cannot pass this command.
runtime = subprocess.run([str(executable), '--headless', '--audio-driver', 'Dummy',
                          '--path', str(ROOT/'源码/client'), '--check-only',
                          '--script', 'res://main.gd'],
                         capture_output=True, text=True, encoding='utf8', errors='replace',
                         creationflags=subprocess.CREATE_NO_WINDOW, timeout=90)
log += runtime.stdout + runtime.stderr
(ROOT/'.tools/client-import.log').write_text(log, encoding='utf8')
errors = [line for line in log.splitlines() if any(word in line for word in ('SCRIPT ERROR', 'Parse Error', 'Compile Error', 'ERROR:', '   at:'))]
print('\n'.join(errors) if errors else 'Godot project and all scripts imported successfully.')
sys.exit(1 if errors or result.returncode or runtime.returncode else 0)
