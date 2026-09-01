// Folds the Vite build into one self-contained HTML file with no external
// requests other than the webfont stylesheet, for hosting anywhere that takes
// a single page.
import { readFileSync, writeFileSync, readdirSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const dist = join(root, 'dist')
const assets = join(dist, 'assets')

const files = readdirSync(assets)
const js = files.find(name => name.endsWith('.js'))
const css = files.find(name => name.endsWith('.css'))
if (!js || !css) throw new Error('Run `vite build` first — no built assets found.')

const script = readFileSync(join(assets, js), 'utf8').replaceAll('</script', '<\\/script')
const styles = readFileSync(join(assets, css), 'utf8')

const page = `<title>RAREFORM</title>
<meta name="description" content="RAREFORM — a clothing marketplace where every garment is rendered live in 3D." />
<style>
${styles}
</style>
<div id="root"></div>
<script type="module">
${script}
</script>
`

const out = join(dist, 'rareform.html')
writeFileSync(out, page)
console.log(`wrote ${out} — ${(page.length / 1024).toFixed(0)} kB`)
