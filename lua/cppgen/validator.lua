local log = require('cppgen.log')
local ast = require('cppgen.ast')
local gen = require('cppgen.generator')

---------------------------------------------------------------------------------------------------
-- Generated code validator.
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Local parameters
---------------------------------------------------------------------------------------------------
local L = {
    group     = "CPPGen",
    lspclient = nil,

    signs = {
        -- Ctl-V ue646
        CPPGenSignError = { text = "", texthl = "DiagnosticSignError"   },
        CPPGenSignWarn  = { text = "", texthl = "DiagnosticSignWarn"    },
        CPPGenSignInfo  = { text = "", texthl = "DiagnosticSignInfo"    },
        CPPGenSignOK    = { text = "", texthl = "DiagnosticUnnecessary" },
    },
    namespace = vim.api.nvim_create_namespace("CPPGen"),
    results   = {},
}

---------------------------------------------------------------------------------------------------
-- Global parameters for code generation.
-- TODO - get them from generator
---------------------------------------------------------------------------------------------------
local G = {
    require('cppgen.generators.class'),
    require('cppgen.generators.enum'),
    require('cppgen.generators.cereal'),
    require('cppgen.generators.switch')
}

--- Exported functions
local M = {}

--- Check if the lines of code have been generated
local function have_been_generated(lines)
    for _,l in ipairs(lines) do
        if string.match(l, L.attribute) then
            return true
        end
    end
    return false
end

--- Check if the code represented by a node in a given buffer has been generated
local function has_been_generated(node, bufnr)
    if node.kind == 'FunctionXProto' or node.kind == 'Function' then
        local span = ast.span(node)
        if span then
            return have_been_generated(vim.api.nvim_buf_get_lines(bufnr, span.first, span.last+1, false))
        end
    end
    return false
end

--- Calculate Levanshtein distance between two string
local function levenshtein(a, b)
	if a:len() == 0 then return b:len() end
	if b:len() == 0 then return a:len() end

	local matrix = {}
	local a_len = a:len()+1
	local b_len = b:len()+1

	-- increment along the first column of each row
	for i = 1, b_len do
		matrix[i] = {i-1}
	end

	-- increment each column in the first row
	for j = 1, a_len do
		matrix[1][j] = j-1
	end

	-- Fill in the rest of the matrix
	for i = 2, b_len do
		for j = 2, a_len do
			if b:byte(i-1) == a:byte(j-1) then
				matrix[i][j] = matrix[i-1][j-1]
			else
				matrix[i][j] = math.min(
					matrix[i-1][j-1] + 1,	-- substitution
					matrix[i  ][j-1] + 1,	-- insertion
					matrix[i-1][j  ] + 1) 	-- deletion
			end
		end
	end

	return matrix[b_len][a_len]
end

--- Compare lines of code
local function same(lhslines, rhslines)
    if #lhslines == #rhslines then
        for i=1,#lhslines do
            if lhslines[i] ~= rhslines[i] then
                return false
            end
        end
        return true
    end
    return false
end

--- Compare code lines against generated snippets and return the snippet that matches the code
local function match(code, snippets)
    for _,snip in ipairs(snippets) do
        local lhs = code[1]
        local rhs = snip.lines[1]
        if levenshtein(lhs, rhs) < 10 then
            return snip
        end
    end
    return nil
end


--- Scan current AST and invoke callback on nodes we think may be interesting
local function visit_relevant_nodes(symbols, bufnr, callback)
    log.trace("Looking for relevant nodes")
    ast.dfs(symbols,
        function(node)
            log.trace("Looking at node", ast.details(node))
            return true
        end,
        function(node)
            if has_been_generated(node, bufnr) then
                local span = ast.span(node)
                if span then
                    gen.visit(symbols, span.first)
                    local code = vim.api.nvim_buf_get_lines(bufnr, span.first, span.last+1, false)
                    local snip = match(code, gen.generate(true))
                    local name = snip and (same(code, snip.lines) and 'CPPGenSignOK' or 'CPPGenSignWarn') or 'CPPGenSignInfo'
                    vim.fn.sign_place(0, L.group, name, bufnr, { lnum = span.first + 1, priority = 10 })
                    if snip then
                        table.insert(L.results, {snip = snip, code = code, span = span, sign = L.signs[name]})
                    end
                end
                callback(node)
            end
        end
    )
end

--- Visit AST nodes
local function visit(symbols, bufnr)
    log.trace("visit:", "buffer", bufnr)

    L.results = {}
    visit_relevant_nodes(symbols, bufnr,
        function(node)
            for _,g in pairs(G) do
                -- TODO - is this needed?
                g.validate(node)
            end
        end
    )
end

---------------------------------------------------------------------------------------------------
--- Initialization and lifecycle callbacks
---------------------------------------------------------------------------------------------------

--- Initialization callback
function M.setup(opts)
    L.attribute = opts.attribute

    -- Configure diagnostics
    for name, sign in pairs(L.signs) do
        vim.fn.sign_define(name, { texthl = sign.texthl, text = sign.text, numhl = "" })
    end
end

--- Annotate generated code in the buffer
local function annotate(bufnr)
	local params = { textDocument = vim.lsp.util.make_text_document_params() }
    -- Should we clear first?
    if L.lspclient then
        vim.fn.sign_unplace(L.group, { buffer = bufnr })
	    L.lspclient.request("textDocument/ast", params, function(err, symbols, _)
            if err ~= nil then
                log.error(err)
            else
                log.info("Received AST data with", (symbols and symbols.children and #symbols.children or 0), "top level nodes")
                log.trace(symbols)
                visit(symbols, bufnr)
            end
	    end)
    end
end

local pickers = require "telescope.pickers"
local finders = require "telescope.finders"
local viewers = require "telescope.previewers"
local configs = require("telescope.config").values
local actions = require "telescope.actions"
local acstate = require "telescope.actions.state"
local display = require("telescope.pickers.entry_display")

---------------------------------------------------------------------------------------------------
-- Longest Common Subsequence implementation
---------------------------------------------------------------------------------------------------
local function matrix(r, c)
    local mt_2D = {
        __index =
            function(t, k)
            local inner = {}
            rawset(t, k, inner)
            return inner
        end
    }
    local m = {rows = r, cols = c}
    return setmetatable(m, mt_2D)
end

local function lcs(old, new)
    local rows = #old
    local cols = #new

    C = matrix(rows, cols)

    for r=0, C.rows do C[r][0] = 0 end
    for c=0, C.cols do C[0][c] = 0 end
    for r=1, rows do
        for c=1, cols do
            if old[r] == new[c] then
                C[r][c] = C[r-1][c-1] + 1;
            else
                C[r][c] = C[r-1][c] > C[r][c-1] and C[r-1][c] or C[r][c-1]
            end
        end
    end
    return C
end

local function diff(old, new)
    local C = lcs(old, new)

    local r = C.rows
    local c = C.cols
    local path = {}

    while r > 0 and c > 0 do
        if old[r] == new[c] then
            table.insert(path, 1, {r, c, '='})
            r, c = r - 1, c - 1
        else
            if C[r][c-1] >= C[r-1][c] then
                table.insert(path, 1, {r, c, '+'})
                c = c - 1
            else
                table.insert(path, 1, {r, c, '-'})
                r = r - 1
            end
        end
    end
    while r > 0 do
        table.insert(path, 1, {r, c, '-'})
        r = r - 1
    end
    while c > 0 do
        table.insert(path, 1, {r, c, '+'})
        c = c - 1
    end
    return path
end

-- Display diff. Collection of action annotated lines ready to be displayed.
local function ddiff(diffs, old, new)
    local lines = {}
    for _,e in ipairs(diffs) do
        if e[3] == '-' then
            table.insert(lines, '- '..old[e[1]])
        elseif e[3] == '+' then
            table.insert(lines, '+ '..new[e[2]])
        else
            table.insert(lines, '  '..old[e[1]])
        end
    end
    return lines
end

-- Block diff. Collection of zero-based start and end lines, and the action indicator.
local function bdiff(diffs)
    local linenr = 0
    local blocks = {}
    for _,e in ipairs(diffs) do
        if next(blocks) ~= nil and blocks[#blocks][3] == e[3] then
            blocks[#blocks][2] = linenr
        else
            table.insert(blocks, {linenr, linenr, e[3]})
        end
        linenr = linenr + 1
    end
    return blocks
end

-- Generated snippets picker
local function snippets(opts)
    opts = opts or {}
    pickers.new(opts, {
        prompt_title = 'Snippets',
        finder = finders.new_table {
            results = L.results,
            entry_maker = function(entry)
                return {
                    value = entry,
                    display = function(e)
                    local displayer = display.create({
                        separator = ' ',
                        items = {
                            { width = 1 },
                            { remaining = true },
                        },
                    })
                    return displayer({
                        { e.value.sign.text, e.value.sign.texthl },
                        { e.value.code[1] },
                    })
                    end,
                    ordinal = entry.code[1],
                }
            end
        },
        previewer = viewers.new_buffer_previewer {
            title = 'Current : Generated',
            define_preview = function (self, entry, status)
                local diffs = diff(entry.value.code, entry.value.snip.lines)
                vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, ddiff(diffs, entry.value.code, entry.value.snip.lines))
                for _,e in ipairs(bdiff(diffs)) do
                    if e[3] == '+' or e[3] == '-' then
                        local hlgroup = e[3] == '+' and 'diffAdded' or 'diffRemoved'
                        vim.api.nvim_buf_set_extmark(self.state.bufnr, L.namespace, e[1], 0, {end_row = e[1]+1, hl_group = hlgroup , hl_eol=true})
                    end
                end
            end
        },
        sorter = configs.generic_sorter(opts),
        attach_mappings = function(prompt_bufnr, map)
            actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                --local selection = acstate.get_selected_entry()
                --vim.api.nvim_put({ selection[1] }, "", false, true)
            end)
            return true
        end,
    }):find()
end

--- LSP client attached callback
function M.attached(client, bufnr)
    log.info("Attached client", client.id, "buffer", bufnr)
    L.lspclient = client
    annotate(bufnr)
end

--- Entering insert mode.
function M.insert_enter(bufnr)
    log.debug("Entered insert mode buffer:", bufnr)
end

--- Exiting insert mode.
function M.insert_leave(bufnr)
    log.debug("Exited insert mode buffer:", bufnr)
end

--- Wrote buffer
function M.after_write(bufnr)
    log.trace("Wrote buffer:", bufnr)
    annotate(bufnr)
end

--- Compare existing and newly generated code in the buffer
function M.validate()
    --snippets(require("telescope.themes").get_ivy{})
    --snippets(require("telescope.themes").get_cursor{})
    --snippets(require("telescope.themes").get_dropdown{})
    snippets()
end


--- Return the result records
function M.results()
    return L.results
end

return M

