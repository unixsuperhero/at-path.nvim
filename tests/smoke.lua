local root = vim.fn.getcwd()
local temp = vim.fn.tempname()
vim.fn.mkdir(temp .. "/project/space dir", "p")
vim.fn.mkdir(temp .. "/home", "p")
vim.fn.writefile({ "fixture" }, temp .. "/project/alpha.txt")
vim.fn.writefile({ "fixture" }, temp .. "/project/.hidden")
vim.fn.writefile({ "fixture" }, temp .. "/project/日本語.txt")
vim.fn.writefile({ "fixture" }, temp .. "/project/space dir/child file.txt")
vim.fn.writefile({ "fixture" }, temp .. "/parent.txt")
vim.fn.writefile({ "fixture" }, temp .. "/home/home.txt")
assert(vim.uv.fs_symlink(temp .. "/project/space dir", temp .. "/project/linked"))
vim.fn.mkdir(temp .. "/project/team-@docs/nested", "p")
vim.fn.writefile({ "fixture" }, temp .. "/project/team-@docs/child@file.txt")
vim.fn.writefile({ "fixture" }, temp .. "/project/team-@docs/nested/deep.txt")
vim.fn.mkdir(temp .. "/project/team @docs", "p")
vim.fn.writefile({ "fixture" }, temp .. "/project/team @docs/child.txt")

local child = vim.fn.jobstart({ vim.v.progpath, "--embed", "--headless", "-u", "NONE", "-n" }, {
  rpc = true, env = { HOME = temp .. "/home" },
})
assert(child > 0, "Neovim did not start")
local function rpc(method, ...)
  return vim.rpcrequest(child, method, ...)
end
local function lua(code, ...)
  return rpc("nvim_exec_lua", code, { ... })
end
local function wait_for(label, predicate)
  assert(vim.wait(2000, predicate, 10), "Timed out: " .. label)
end
local function input(keys)
  rpc("nvim_input", keys)
end
local function line()
  return rpc("nvim_get_current_line")
end
local function info()
  return lua("return vim.fn.complete_info()")
end
local function popup(word)
  wait_for("popup containing " .. word, function()
    if lua("return vim.fn.pumvisible()") ~= 1 then return false end
    for _, item in ipairs(info().items) do
      if item.word == word then return true end
    end
    return false
  end)
end
local function accept(word, expected)
  popup(word)
  local index
  for i, item in ipairs(info().items) do
    if item.word == word then index = i - 1 end
  end
  assert(index, "Missing candidate " .. word)
  while info().selected ~= index do
    local selected = info().selected
    input("<C-n>")
    wait_for("next selection", function() return info().selected ~= selected end)
  end
  input("<C-y>")
  wait_for("accepted " .. expected, function() return line() == expected end)
end
local function begin(text, ft, named)
  input("<Esc>")
  wait_for("normal mode", function() return lua("return vim.api.nvim_get_mode().mode") == "n" end)
  lua([[
    vim.bo.bufhidden = "wipe"
    vim.cmd("enew!")
    local name, ft = ...
    if name ~= '' then vim.api.nvim_buf_set_name(0, name) end
    vim.bo.filetype = ft
  ]], named == false and "" or temp .. "/project/note.md", ft or "markdown")
  input("i" .. text)
end

local ok, err = xpcall(function()
  rpc("nvim_ui_attach", 100, 30, { rgb = true, ext_popupmenu = true })
  lua([[
    local root, cwd = ...
    vim.opt.runtimepath:prepend(root)
    vim.cmd.cd(cwd)
    require('at_path').setup()
  ]], root, temp .. "/project")
  local global_options = lua("return {vim.go.completeopt, vim.fn.maparg('<C-n>', 'i'), vim.fn.maparg('<C-y>', 'i')}")

  begin("@")
  popup("@alpha.txt")
  popup("@.hidden")
  popup("@日本語.txt")
  popup("@linked/")
  accept("@alpha.txt", "alpha.txt")
  print("PASS bare @ popup, hidden/Unicode/symlink entries, accepted relative path")

  begin("(@./al")
  accept("@./alpha.txt", "(./alpha.txt")
  begin("@../par")
  accept("@../parent.txt", "../parent.txt")
  begin("@" .. temp .. "/project/al")
  accept("@" .. temp .. "/project/alpha.txt", temp .. "/project/alpha.txt")
  begin("@~/ho")
  accept("@~/home.txt", "~/home.txt")
  print("PASS punctuation, ./, ../, absolute and home paths")

  begin("@space")
  accept("@space dir/", "space dir/")
  popup("space dir/child file.txt")
  input("ch")
  accept("space dir/child file.txt", "space dir/child file.txt")
  begin("@linked")
  accept("@linked/", "linked/")
  input("ch")
  accept("linked/child file.txt", "linked/child file.txt")
  print("PASS accepted directory navigation with spaces and symlink directories")

  begin("@team")
  accept("@team-@docs/", "team-@docs/")
  popup("team-@docs/nested/")
  input("ch")
  accept("team-@docs/child@file.txt", "team-@docs/child@file.txt")
  begin("@team")
  accept("@team-@docs/", "team-@docs/")
  accept("team-@docs/nested/", "team-@docs/nested/")
  accept("team-@docs/nested/deep.txt", "team-@docs/nested/deep.txt")
  print("PASS literal @ names, nested directories and immediate child popup")
  begin("@al", "markdown", false)
  accept("@alpha.txt", "alpha.txt")
  begin("@al", "lua")
  vim.wait(100)
  assert(line() == "@al" and lua("return vim.fn.pumvisible()") == 0, "Default must exclude Lua")
  lua("require('at_path').setup({filetypes = {}})")
  begin("@al", "lua")
  accept("@alpha.txt", "alpha.txt")
  print("PASS unnamed cwd, Markdown-only default and all-buffer setup")

  begin("@nonexistent ")
  wait_for("unresolved token", function() return line() == "@nonexistent " end)
  input("@a")
  accept("@alpha.txt", "@nonexistent alpha.txt")
  begin("@al")
  popup("@alpha.txt")
  input("nonexistent ")
  wait_for("unresolved after popup", function() return line() == "@alnonexistent " end)
  input("@a")
  accept("@alpha.txt", "@alnonexistent alpha.txt")
  begin("@team ")
  popup("@team @docs/")
  input("@")
  popup("@team @docs/")
  input("docs")
  accept("@team @docs/", "team @docs/")
  accept("team @docs/child.txt", "team @docs/child.txt")
  begin("@team ")
  popup("@team @docs/")
  input("@docs/ch")
  accept("@team @docs/child.txt", "team @docs/child.txt")
  print("PASS fresh @ after unresolved query and literal space-@ directory names")

  begin("foo@al")
  vim.wait(100)
  assert(line() == "foo@al" and lua("return vim.fn.pumvisible()") == 0, "Email triggered completion")
  begin("@al")
  popup("@alpha.txt")
  input("<C-e>")
  wait_for("cancel", function() return lua("return vim.fn.pumvisible()") == 0 end)
  vim.wait(100)
  assert(line() == "@al" and lua("return vim.fn.pumvisible()") == 0, "Cancellation reopened popup")
  input("p")
  accept("@alpha.txt", "alpha.txt")
  begin("@al second @")
  popup("@alpha.txt")
  input("<C-e><Home><Right><Right><Right>")
  wait_for("cursor at first token", function() return lua("return vim.api.nvim_win_get_cursor(0)[2]") == 3 end)
  input("p")
  accept("@alpha.txt", "alpha.txt second @")
  print("PASS cancellation retrigger and cursor movement between @ tokens")
  assert(vim.deep_equal(global_options, lua("return {vim.go.completeopt, vim.fn.maparg('<C-n>', 'i'), vim.fn.maparg('<C-y>', 'i')}")), "Global options or keys changed")
  print("PASS email suppression, cancellation, unchanged global completion options and keys")
end, debug.traceback)
pcall(rpc, "nvim_command", "qa!")
vim.fn.jobstop(child)
vim.fn.delete(temp, "rf")
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit 1")
end
print("All at-path input-driven checks passed")
vim.cmd("qa!")
