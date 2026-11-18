import { readFile } from "node:fs/promises"
import { fileURLToPath } from "node:url"
import { Plugin, Skill } from "@opencode/plugin"
import { load } from "./frontmatter.ts"

// Resolved relative to this module so it points inside the installed package,
// wherever OpenCode unpacked it.
const file = new URL("../skills/gitx-release/SKILL.md", import.meta.url)

export default Plugin.define({
  id: "tkxlabai.gitx",
  async setup(ctx) {
    // A packaging mistake in this plugin must not break the host's startup:
    // log and register nothing rather than letting setup() reject.
    let info: ReturnType<typeof load>
    try {
      info = load(await readFile(file, "utf8"))
    } catch (err) {
      console.error(`[tkxlabai.gitx] gitx-release skill not registered: ${err instanceof Error ? err.message : String(err)}`)
      return
    }
    const skill = Skill.Info.make({
      id: Skill.ID.make(info.name),
      name: Skill.Name.make(info.name),
      description: info.description,
      autoinvoke: info.autoinvoke,
      path: Skill.Info.fields.path.make(fileURLToPath(file)),
      content: info.body,
    })
    // Never override a same-id skill the user already has (e.g. a manual install).
    await ctx.skill.transform((editor) => {
      if (!editor.get(skill.id)) editor.add(skill)
    })
  },
})
