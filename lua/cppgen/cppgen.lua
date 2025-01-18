local log = require('cppgen.log')
local ctx = require('cppgen.context')
local src = require('cppgen.source')

---------------------------------------------------------------------------------------------------
-- Code generation module. Forwards events to the dependent modules. Completion source proxy.
---------------------------------------------------------------------------------------------------
local M = {}

---------------------------------------------------------------------------------------------------
--- Initialization callback
---------------------------------------------------------------------------------------------------
function M.setup(opts)
    -- Pass the configuration to the snippet source
    src.setup(opts)
end

---------------------------------------------------------------------------------------------------
--- Callback invoked when the LSP client has been attache to the buffer
---------------------------------------------------------------------------------------------------
function M.attached(client, bufnr)
    log.trace("Attached client", client.id, "buffer", bufnr)
	ctx.attached(client, bufnr)
	src.attached(client, bufnr)
end

---------------------------------------------------------------------------------------------------
--- Callback invoked when we enter insert mode in the buffer attached to a LSP client
---------------------------------------------------------------------------------------------------
function M.insert_enter(client, bufnr)
    log.trace("Entered insert mode client", client.id, "buffer", bufnr)
	ctx.insert_enter(client, bufnr)
	src.insert_enter(client, bufnr)
end

---------------------------------------------------------------------------------------------------
--- Callback invoked when we leave insert mode in the buffer attached to a LSP client
---------------------------------------------------------------------------------------------------
function M.insert_leave(client, bufnr)
    log.trace("Exited insert mode client", client.id, "buffer", bufnr)
	ctx.insert_leave(client, bufnr)
	src.insert_leave(client, bufnr)
end

---------------------------------------------------------------------------------------------------
--- Code generator is a source for the completion engine
---------------------------------------------------------------------------------------------------
function M.source()
    log.trace("source")
    return src.new()
end

-- Calculate the longest length of the first two element in the records
local function max_lengths(records)
    local max_1st_len = 0
    local max_2nd_len = 0

    for _,r in ipairs(records) do
        max_1st_len = math.max(max_1st_len, string.len(r[1]))
        max_2nd_len = math.max(max_2nd_len, string.len(r[2]))
    end
    return max_1st_len, max_2nd_len
end

local function pad(s, len)
    return s .. string.rep(' ', len - string.len(s))
end

vim.api.nvim_create_user_command('CPPGenInfo', function()
    local info = src.info()

    if #info > 0 then
        local header = { 'Trigger', 'Generated code'}
        local maxlen, _ = max_lengths(info)
        maxlen = math.max(maxlen, string.len(header[1]))

        vim.api.nvim_echo({ { (' %s   %s\n'):format(pad(header[1], maxlen), header[2]), 'Special' } }, false, {})
        local prev = nil
        for _, record in ipairs(info) do
            if (prev == nil) or (prev ~= record[1]) then
                vim.api.nvim_echo({ { (' %s - %s\n'):format(pad(record[1], maxlen), record[2]), 'Normal' } }, false, {})
            else
                vim.api.nvim_echo({ { (' %s   %s\n'):format(pad("",        maxlen), record[2]), 'Normal' } }, false, {})
            end
            prev = record[1]
        end
    end
end, { desc = 'Brief information about cppgen sources' })

return M
