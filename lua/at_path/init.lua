local M = {}
local uv = vim.uv or vim.loop
local session, last, blocked
local generation = 0
local opening = false

local function snapshot()
  local cursor = vim.api.nvim_win_get_cursor(0)
  return {
    buf = vim.api.nvim_get_current_buf(),
    row = cursor[1],
    col = cursor[2],
    line = vim.api.nvim_get_current_line(),
  }
end

local function same(a, b)
  return a and b and a.buf == b.buf and a.row == b.row
    and a.col == b.col and a.line == b.line
end

local function matches(query, base, marker)
  local head, tail = query:match("^(.*[/])(.*)$")
  head, tail = head or "", tail or query
  local directory = base .. "/" .. head
  if head:sub(1, 2) == "~/" then
    directory = uv.os_homedir() .. head:sub(2)
  elseif head:sub(1, 1) == "/" then
    directory = head
  end
  local scan = uv.fs_scandir(directory)
  if not scan then
    return {}
  end
  local items = {}
  while true do
    local name, kind = uv.fs_scandir_next(scan)
    if not name then
      break
    end
    if name:sub(1, #tail) == tail and not name:find("[\r\n]") then
      if kind == "link" or kind == "unknown" then
        local stat = uv.fs_stat(directory .. "/" .. name)
        kind = stat and stat.type
      end
      if kind == "file" or kind == "directory" then
        local path = head .. name .. (kind == "directory" and "/" or "")
        items[#items + 1] = {
          word = marker .. path,
          abbr = path,
          menu = kind == "directory" and "[dir]" or "[file]",
          user_data = kind == "directory" and "at_path:directory" or "at_path:file",
        }
      end
    end
  end
  table.sort(items, function(a, b) return a.word < b.word end)
  return items
end

local function refresh(filetypes)
  if vim.api.nvim_get_mode().mode:sub(1, 1) ~= "i" then
    return
  end
  if #filetypes > 0 and not vim.tbl_contains(filetypes, vim.bo.filetype) then
    return
  end
  local now = snapshot()
  if same(now, last) or same(now, blocked) then
    return
  end
  if vim.fn.complete_info({ "selected" }).selected >= 0 then
    return
  end
  last, blocked = now, nil
  local before = now.line:sub(1, now.col)
  if session then
    local token = before:sub(#session.prefix + 1)
    if session.buf ~= now.buf or session.row ~= now.row
      or before:sub(1, #session.prefix) ~= session.prefix
      or token:sub(1, #session.marker) ~= session.marker
      or (session.directory and token:sub(1, #session.directory) ~= session.directory) then
      session = nil
    end
  end
  if not session then
    local start = before:match("()@[^%s]*$") or before:match("()@[^@]*$")
    if not start then return end
    local previous = vim.fn.matchstr(before:sub(1, start - 1), ".$")
    if previous == "@" or vim.fn.match(previous, [[\k]]) >= 0 then return end
    local name = vim.api.nvim_buf_get_name(0)
    session = {
      buf = now.buf, row = now.row,
      prefix = before:sub(1, start - 1), marker = "@",
      base = name == "" and vim.fn.getcwd() or vim.fn.fnamemodify(name, ":p:h"),
    }
  end
  local token = before:sub(#session.prefix + 1)
  local items = matches(token:sub(#session.marker + 1), session.base, session.marker)
  if #items == 0 then
    local start = before:match("()@[^%s]*$")
    if start and start > #session.prefix + 1 then
      local previous = vim.fn.matchstr(before:sub(1, start - 1), ".$")
      if previous ~= "@" and vim.fn.match(previous, [[\k]]) < 0 then
        session.prefix = before:sub(1, start - 1)
        session.marker, session.directory = "@", nil
        items = matches(before:sub(start + 1), session.base, "@")
      end
    end
  end
  if #items == 0 then
    return
  end
  -- Only this invocation uses a visible, unselected menu. Global options and keys stay untouched.
  local completeopt = vim.bo.completeopt
  vim.bo.completeopt = "menu,menuone,noselect"
  opening = true
  local ok, err = pcall(vim.fn.complete, #session.prefix + 1, items)
  opening = false
  vim.bo.completeopt = completeopt
  if not ok then
    error(err)
  end
end

function M.setup(opts)
  opts = opts or {}
  -- Enable in every buffer with require('at_path').setup({ filetypes = {} }).
  local filetypes = opts.filetypes or { "markdown" }
  session, last, blocked = nil, nil, nil
  generation = generation + 1
  local group = vim.api.nvim_create_augroup("AtPath", { clear = true })
  local function queue_refresh()
    local expected, version = snapshot(), generation
    vim.schedule(function()
      if version == generation and same(expected, snapshot()) then
        refresh(filetypes)
      end
    end)
  end
  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChangedP" }, {
    group = group, callback = queue_refresh,
  })
  vim.api.nvim_create_autocmd("CompleteDone", {
    group = group,
    callback = function()
      if opening then
        return
      end
      local item = vim.v.completed_item
      if item.user_data ~= "at_path:file" and item.user_data ~= "at_path:directory" then
        if vim.v.event.reason == "cancel" then
          blocked = snapshot()
          session = nil
        elseif next(item) ~= nil then
          session = nil
        end
        return
      end
      if not session then return end
      local now = snapshot()
      local start = #session.prefix
      if now.buf ~= session.buf or now.row ~= session.row
        or now.line:sub(1, start) ~= session.prefix
        or now.line:sub(start + 1, start + #item.word) ~= item.word then
        session = nil
        return
      end
      if session.marker == "@" then
        vim.api.nvim_buf_set_text(0, now.row - 1, start, now.row - 1, start + 1, {})
        if now.col > start then
          vim.api.nvim_win_set_cursor(0, { now.row, now.col - 1 })
        end
      end
      if item.user_data == "at_path:directory" then
        session.directory = item.word:sub(#session.marker + 1)
        session.marker = ""
        last = nil
        queue_refresh()
      else
        session = nil
        last = snapshot()
      end
    end,
  })
  vim.api.nvim_create_autocmd("CursorMovedI", {
    group = group,
    callback = function()
      local now = snapshot()
      if last and now.buf == last.buf and now.line == last.line
        and (now.row ~= last.row or now.col ~= last.col) then
        generation = generation + 1
        session, last = nil, nil
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "InsertLeave", "BufLeave" }, {
    group = group,
    callback = function()
      generation = generation + 1
      session, last, blocked = nil, nil, nil
    end,
  })
end

return M
