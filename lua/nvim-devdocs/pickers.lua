local M = {}

local log = require("nvim-devdocs.log")
local list = require("nvim-devdocs.list")
local operations = require("nvim-devdocs.operations")
local transpiler = require("nvim-devdocs.transpiler")
local plugin_state = require("nvim-devdocs.state")
local plugin_config = require("nvim-devdocs.config")

-- Common function to create a registry picker (for install/uninstall/update)
---@param prompt string
---@param entries RegisteryEntry[]
---@param on_confirm function
local function create_registry_picker(prompt, entries, on_confirm)
  if vim.tbl_isempty(entries) then
    log.info("No documentation available")
    return
  end

  local items = {}
  for _, entry in ipairs(entries) do
    local transpiled = transpiler.to_yaml(entry)
    table.insert(items, {
      value = entry,
      text = entry.slug:gsub("~", "-"),
      preview = {
        text = transpiled,
        ft = "yaml",
      },
    })
  end

  Snacks.picker.pick({
    title = prompt,
    items = items,
    preview = "preview",
    format = "text",
    confirm = function(picker, item)
      picker:close()
      if item then on_confirm(item.value) end
    end,
  })
end

M.installation_picker = function()
  local non_installed = list.get_non_installed_registery()
  if not non_installed then return end

  create_registry_picker(
    "Install documentation",
    non_installed,
    function(entry) operations.install(entry) end
  )
end

M.uninstallation_picker = function()
  local installed = list.get_installed_registery()
  if not installed then return end

  create_registry_picker("Uninstall documentation", installed, function(entry)
    local alias = entry.slug:gsub("~", "-")
    operations.uninstall(alias)
  end)
end

M.update_picker = function()
  local updatable = list.get_updatable_registery()
  if not updatable then return end

  create_registry_picker("Update documentation", updatable, function(entry)
    local alias = entry.slug:gsub("~", "-")
    operations.install(alias, true, true)
  end)
end

-- Function to prepare items with preview data
local function prepare_doc_items(entries)
  local items = {}
  for _, entry in ipairs(entries) do
    local lines = operations.read_entry(entry)
    local content = table.concat(lines, "\n")

    table.insert(items, {
      value = entry,
      text = string.format("[%s] %s", entry.alias, entry.name),
      preview = {
        text = content,
        ft = "markdown",
      },
    })
  end
  return items
end

-- Function to prepare a new buffer for the documentation
local function prepare_doc_buffer(entry)
  -- Create a new buffer
  local bufnr = vim.api.nvim_create_buf(false, true)

  -- Read the documentation content
  local lines = operations.read_entry(entry)

  -- Set the buffer content
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  -- Store the content in state for potential later use
  plugin_state.set("preview_lines", lines)

  -- Set the filetype if not using custom commands
  if not (plugin_config.options.previewer_cmd and plugin_config.options.picker_cmd) then
    vim.bo[bufnr].ft = "markdown"
  else
    -- Apply custom rendering to the buffer if needed
    operations.render_cmd(bufnr, false)
  end

  return bufnr
end

-- Create a doc picker
---@param entries DocEntry[]
---@param float? boolean
M.open_picker = function(entries, float)
  if vim.tbl_isempty(entries) then
    log.info("No documentation entries available")
    return
  end

  -- Prepare items with preview data
  local items = prepare_doc_items(entries)

  Snacks.picker.pick({
    title = "Select an entry",
    items = items,
    preview = "preview",
    format = function(item)
      return {
        { string.format("[%s]", item.value.alias), "markdownH1" },
        { " " },
        { item.value.name, "markdownH2" },
      }
    end,
    confirm = function(picker, item)
      picker:close()
      if item then
        plugin_state.set("current_doc", item.value.alias)

        -- Always create a fresh buffer for the documentation
        local bufnr = prepare_doc_buffer(item.value)

        -- Store the mode (float or normal)
        plugin_state.set("last_mode", float and "float" or "normal")

        -- Open the documentation in a new window/buffer
        vim.schedule(function() operations.open(item.value, bufnr, float) end)
      end
    end,
    -- Use a layout with a good preview area
    layout = "default",
  })
end

---@param alias string
---@param float? boolean
M.open_picker_alias = function(alias, float)
  local entries = list.get_doc_entries({ alias })

  if not entries then return end

  if vim.tbl_isempty(entries) then
    log.error(alias .. " documentation is not installed")
  else
    plugin_state.set("current_doc", alias)
    M.open_picker(entries, float)
  end
end

return M

