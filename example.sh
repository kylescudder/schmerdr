# schmerdr layout template.
#
# `schmerdr new <name>` copies this file to layouts/<name>.sh for you to edit.
# `schmerdr load <name> [args...]` sources it; args arrive here as $1, $2, ...
#
# The DSL (project_root, new_workspace, new_tab, split_*, run_command,
# start_agent, prompt_agent, new_worktree, focus_tab, attach) is already in scope.
#
# Args from `schmerdr load` arrive as $1, $2, ... This template uses:
#   $1 = Claude session name (differs per worktree; defaults to the branch)
#   $2 = .NET launch profile   (defaults to Development)
# Example: `schmerdr load cool-project PROJ-123 Dev`

# project_root defaults to the dir you ran `schmerdr load` from (great for
# worktrees). Uncomment to pin a fixed location instead:
# project_root ~/projects/cool-project
workspace_name "Cool project"

new_workspace

# --- tab: api ---------------------------------------------------------------
# Reuse the workspace's default tab instead of leaving an empty "1".
rename_tab "api"
run_command "dotnet run --launch-profile ${2:-Development}"

# --- tab: web (editor left, dev server right) -------------------------------
new_tab "web"
run_command "nvim"
split_right 40%
run_command "npm run dev"

# --- tab: agents ------------------------------------------------------------
new_tab "agents"
# Session name = $1, or fall back to the current git branch, else the workspace name.
start_agent claude "${1:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "$NAME")}"
prompt_agent "Review the diff on the current branch"

# Land on the api tab and attach.
focus_tab "api"
attach
