local cgn = require("nvim-cppgen.cgn")
local log = require('nvim-cppgen.log')

local M = {}

local cppgen = 'cppgen'
local csrcid = nil

--- LSP attach callback
local function attach(client, bufnr)
    log.info("Client", log.squoted(client.name), "attached to", log.squoted(vim.api.nvim_buf_get_name(bufnr)))

    -- Inform code generator that LPS client has been attached to the buffer
	cgn.attached(client, bufnr)

	local group = vim.api.nvim_create_augroup(cppgen, { clear = false })

	vim.api.nvim_clear_autocmds({
		group  = group,
		buffer = bufnr
	})

	vim.api.nvim_create_autocmd({ "InsertEnter" }, {
		callback = function(args)
			cgn.insert_enter(client, bufnr)
		end,
		group  = group,
		buffer = bufnr
	})
	vim.api.nvim_create_autocmd({ "InsertLeave" }, {
		callback = function(args)
			cgn.insert_leave(client, bufnr)
		end,
		group  = group,
		buffer = bufnr
	})

    -- Add our source to cmp
    if not csrcid then
        log.info("Adding completion source", log.squoted(cppgen))
        csrcid = require('cmp').register_source(cppgen, cgn.source())
    end
end

--- Setup
function M.setup(opts)
    -- We configure log module ourselves
	if opts and opts.log then
        log.new(opts.log, true)
	end

    log.trace("setup:", opts)

    -- Setup code generator
    cgn.setup(opts)

	vim.api.nvim_create_autocmd("LspAttach", {
		callback = function(args)
            if vim.bo.filetype == "cpp" then
			    local client = vim.lsp.get_client_by_id(args.data.client_id)
	            if client.server_capabilities.astProvider then
                    log.debug("LSP server is capable of delivering AST data.")
				    attach(client, args.buf)
                else
                    log.warn("LSP server is not capable of delivering AST data.")
			    end
			end
		end,
	})
end

return M
