// Line-based frontmatter parse: avoids a YAML dependency (the package ships no
// node_modules). Split on the first ":" only, because the description itself
// contains ":" and "—"; strip one pair of surrounding quotes.
// Kept apart from index.ts so the test can run it under node without the SDK.
export function parse(text: string) {
  const lines = text.split(/\r?\n/)
  const data: Record<string, string | boolean> = {}
  if (lines[0]?.trim() !== "---") return { data, body: text }
  let end = 1
  for (; end < lines.length; end++) {
    const line = lines[end]
    if (line.trim() === "---") break
    const i = line.indexOf(":")
    if (i <= 0) continue
    let value = line.slice(i + 1).trim()
    const q = value[0]
    if ((q === '"' || q === "'") && value.length >= 2 && value.endsWith(q)) value = value.slice(1, -1)
    data[line.slice(0, i).trim()] = value === "true" ? true : value === "false" ? false : value
  }
  return { data, body: lines.slice(end + 1).join("\n").trim() }
}

// Throws instead of returning a half-filled skill: String(undefined) would
// otherwise register a skill literally named "undefined".
export function load(text: string) {
  const { data, body } = parse(text)
  for (const key of ["name", "description"]) {
    const v = data[key]
    if (typeof v !== "string" || v === "") throw new Error(`SKILL.md frontmatter missing "${key}"`)
  }
  return {
    name: data.name as string,
    description: data.description as string,
    autoinvoke: data["disable-model-invocation"] !== true,
    body,
  }
}
