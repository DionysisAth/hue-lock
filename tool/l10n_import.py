#!/usr/bin/env python3
"""Writes translations into the app.

    flutter test test/l10n_test.dart        # -> build/l10n/catalog.json
    python3 tool/l10n_import.py de.json ...  # -> lib/l10n/translations/de.dart

Each JSON file is {English text: translation} for one language, named by
its language code; catalog.json lists every English text (the keys) with
its English source (an ICU plural for countable texts). The test suite
checks that each language covers the whole catalog.
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def dart(s):
    s = s.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$')
    return "'" + s.replace('\n', '\\n') + "'"


def main(paths):
    for path in paths:
        lang = os.path.splitext(os.path.basename(path))[0]
        table = json.load(open(path, encoding='utf-8'))
        name = 'text' + lang[0].upper() + lang[1:]
        lines = [f'const {name} = <String, String>{{']
        for k in sorted(table):
            lines.append(f'  {dart(k)}: {dart(table[k])},')
        lines.append('};\n')
        out = os.path.join(ROOT, 'lib', 'l10n', 'translations', f'{lang}.dart')
        open(out, 'w', encoding='utf-8').write('\n'.join(lines))
        print('wrote', os.path.relpath(out, ROOT), len(table), 'texts')


if __name__ == '__main__':
    main(sys.argv[1:])
