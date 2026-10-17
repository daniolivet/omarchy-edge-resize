// Snapshot tests for lib/EdgeGeometry.js: for each layout fixture, the edges
// found must match tests/fixtures/<name>.edges.json, ignoring order.
// UPDATE_SNAPSHOTS=1 rewrites the snapshots from the current output.
const assert = require("assert")
const fs = require("fs")
const path = require("path")
const vm = require("vm")

const projectDir = path.join(__dirname, "..")
const fixturesDir = path.join(__dirname, "fixtures")
const updateSnapshots = process.env.UPDATE_SNAPSHOTS === "1"

const source = fs.readFileSync(path.join(projectDir, "lib/EdgeGeometry.js"), "utf8")
  .replace(/^\.pragma library\s*/m, "")
const context = {}
vm.createContext(context)
vm.runInContext(source, context)

// The edge order depends on how pairs are walked, not on the layout.
// The JSON round trip also drops the vm context's own Array prototype.
const sorted = (edges) => JSON.parse(JSON.stringify(edges))
  .sort((a, b) => JSON.stringify(a).localeCompare(JSON.stringify(b)))

const layouts = fs.readdirSync(fixturesDir)
  .filter((file) => file.endsWith(".json") && !file.endsWith(".edges.json"))
  .map((file) => path.basename(file, ".json"))
assert.ok(layouts.length > 0, "no fixtures found")

for (const name of layouts) {
  const { clients, workspaceId } = JSON.parse(fs.readFileSync(path.join(fixturesDir, `${name}.json`), "utf8"))
  const edges = sorted(context.findEdges(clients, workspaceId))
  const snapshotPath = path.join(fixturesDir, `${name}.edges.json`)

  if (updateSnapshots) {
    fs.writeFileSync(snapshotPath, JSON.stringify(edges, null, 2) + "\n")
    console.log(`snapshot written: ${name} (${edges.length} edges)`)
    continue
  }

  assert.ok(fs.existsSync(snapshotPath), `missing snapshot for ${name}; run UPDATE_SNAPSHOTS=1 tests/run.sh`)
  const expected = JSON.parse(fs.readFileSync(snapshotPath, "utf8"))
  assert.deepStrictEqual(edges, expected, `edges changed for ${name}`)
  console.log(`ok: ${name} (${edges.length} edges)`)
}

const twoSideBySide = JSON.parse(fs.readFileSync(path.join(fixturesDir, "two-side-by-side.json"), "utf8"))
const edges = context.findEdges(twoSideBySide.clients, twoSideBySide.workspaceId)
assert.ok(context.edgesEqual(edges, context.findEdges(twoSideBySide.clients, twoSideBySide.workspaceId)))
assert.ok(!context.edgesEqual(edges, []))

console.log("EdgeGeometry tests passed")
