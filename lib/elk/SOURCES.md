# elkjs (Eclipse Layout Kernel for JavaScript)

`Show-AACResourceMap` lays out its map with ELK's layered algorithm. The file
is embedded, unmodified, in the HTML report the command writes, and runs in
the browser.

| File | Source | SHA-256 |
|---|---|---|
| `elk.bundled.js` | npm package `elkjs` 0.12.0, `lib/elk.bundled.js` | `1222E44F953CE7746AF23801E723708F8E6F436B8B377A6A5FC7552F34A307B3` |
| `LICENSE.md` | the same package | |

- Package: https://www.npmjs.com/package/elkjs (source: https://github.com/kieler/elkjs)
- Tarball: https://registry.npmjs.org/elkjs/-/elkjs-0.12.0.tgz, verified against npm's
  integrity value `sha512-YZcKynxVxYoKIOEpywEPwCFdg+BTbxQRNf3pbwdDCvc8O3kQD8bmIwSxKU1eOTVc4Xo+VG9Te+575mlfvOrhEQ==`
- Licence: `EPL-2.0 OR GPL-3.0-or-later`. Azure.Admin.Console uses it under the
  Eclipse Public License 2.0 (`LICENSE.md`), unmodified, as a separate file.

The module checks the SHA-256 before embedding the file and refuses a file
that doesn't match. To update it, replace the file and the hash in
`Private\Get-AACResourceMapAsset.ps1` together.
