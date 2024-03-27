local ast = require('nvim-cppgen.ast')
local ctx = require('nvim-cppgen.ctx')
local log = require('nvim-cppgen.log')

---------------------------------------------------------------------------------------------------
-- 1. Collection of code generators. Gathers code completion items from specialized generators.
-- 2. Reacts to editor mode changes to cache results.
---------------------------------------------------------------------------------------------------

-- TODO - populate during configuration
local G = {
    require('nvim-cppgen.gen.oss'),
    require('nvim-cppgen.gen.cnv'),
    require('nvim-cppgen.gen.cereal')
}

--- Keep track of results
local R = {}

--- Exported functions
local M = {}

--- Return true if the code can be generated in the current context - buffer and cursor position
function M.available(bufnr)
    log.trace("available:", "buffer", bufnr)
    if R.visited then
        return R.available
    end

	local line = ctx.context(bufnr)[1] - 1

    R.visited = ast.visit_relevant_nodes(bufnr, line,
        function(n, l)
            for _,g in pairs(G) do
                g.visit(n, l)
            end
        end
    )

    R.available = false
    for _,g in pairs(G) do
        R.available = R.available or g.available()
    end

    log.debug("Can" .. (R.available and " " or " not ") .. "generate code in buffer", bufnr, "line", line)
    return R.available
end

--- Generate code completion items appropriate for the current context
function M.generate(bufnr)
	local cursor = ctx.context(bufnr)
    if cursor then
        log.info("Generating code in buffer", bufnr)
        local total = {}
        for _,g in pairs(G) do
            local items = g.completion_items();
            for _,i in ipairs(items) do
                table.insert(total, i)
            end
        end
        log.info("Collected", #total, "completion items")
        return total
    end
end

---------------------------------------------------------------------------------------------------
--- Initialization callback
---------------------------------------------------------------------------------------------------
function M.setup(opts)
    -- Pass the configuration to the snippet generators
    for _,g in pairs(G) do
        g.setup(opts)
    end
end

---------------------------------------------------------------------------------------------------
--- Code generation callbacks
---------------------------------------------------------------------------------------------------
function M.attached(client, bufnr)
    log.trace("Attached client", client.id, "buffer", bufnr)
end

function M.insert_enter(client, bufnr)
    log.trace("Entered insert mode client", client.id, "buffer", bufnr)
    R.visited = false
    for _,g in pairs(G) do
        g.reset()
    end
end

function M.insert_leave(client, bufnr)
    log.trace("Exited insert mode client", client.id, "buffer", bufnr)
end

return M
