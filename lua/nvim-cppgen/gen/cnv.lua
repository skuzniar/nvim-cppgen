local ast = require('nvim-cppgen.ast')
local log = require('nvim-cppgen.log')

local cmp = require('cmp')

---------------------------------------------------------------------------------------------------
-- Conversion function generator.
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Global parameters for code generation.
---------------------------------------------------------------------------------------------------
local G = {}

G.keepindent = true

---------------------------------------------------------------------------------------------------
-- Enum specific parameters
---------------------------------------------------------------------------------------------------
G.enum = {}

-- Create the value string for the member field. By default we use both, the value and mnemonic
G.enum.value = function(mnemonic, value)
    if (value) then
        return '"' .. value .. '(' .. mnemonic .. ')' .. '"'
    else
        return '"' .. mnemonic .. '"'
    end
end

---------------------------------------------------------------------------------------------------
-- Parameters
---------------------------------------------------------------------------------------------------
local P = {}

P.camelize = false
P.indt     = '   '
P.equalsgn = ': '
P.fieldsep = "' '"

-- Calculate the longest length of the childe's name
local function max_length(node)
    local max_nam_len = 0
    ast.visit_children(node,
        function(n)
            if n.kind == "EnumConstant" or n.kind == "Field" then
                max_nam_len = math.max(max_nam_len, string.len(ast.name(n)))
            end
        end
    )
    return max_nam_len
end

-- Apply parameters to the format string 
local function apply(format)
    local result  = format

    result = string.gsub(result, "<label>",      P.label      or '')
    result = string.gsub(result, "<labelpad>",   P.labelpad   or '')
    result = string.gsub(result, "<value>",      P.value      or '')
    result = string.gsub(result, "<valuepad>",   P.valuepad   or '')
    result = string.gsub(result, "<specifier>",  P.specifier  or '')
    result = string.gsub(result, "<attributes>", P.attributes or '')
    result = string.gsub(result, "<classname>",  P.classname  or '')
    result = string.gsub(result, "<fieldname>",  P.fieldname  or '')
    result = string.gsub(result, "<separator>",  P.separator  or '')
    result = string.gsub(result, "<indent>",     P.indent     or '')

    return result;
end

-- Attempt to find integral constant for the enum element
local function integral_literal(node)
    log.trace("integral_literal:", ast.details(node))

    local result = nil
    ast.visit_children(node,
        function(n)
            if n.kind == "IntegerLiteral" or n.kind == "CharacterLiteral" then
                result = n.detail
            else
                result = integral_literal(n)
            end
            if (result) then
                return result
            end
        end
    )
    return result
end

-- Collect names and values for an enum type node.
local function enum_labels_and_values(node)
    local records = {}
    ast.visit_children(node,
        function(n)
            if n.kind == "EnumConstant" then
                local record = {}
                record.label = ast.name(node) .. '::' .. ast.name(n)
                record.value = G.enum.value(ast.name(n), integral_literal(n))
                table.insert(records, record)
            end
        end
    )
    return records
end

-- Calculate the longest length of labels and values
local function max_lengths(records)
    local max_lab_len = 0
    local max_val_len = 0

    for _,r in ipairs(records) do
        max_lab_len = math.max(max_lab_len, string.len(r.label))
        max_val_len = math.max(max_val_len, string.len(r.value))
    end
    return max_lab_len, max_val_len
end

-- Generate from string function for an enum type node - implementation.
local function from_string_enum_snippet(node, specifier)
    log.trace("from_string_enum_snippet:", ast.details(node))

    P.specifier  = specifier
    P.attributes = G.attributes and ' ' .. G.attributes or ''
    P.classname  = ast.name(node)
    P.indent     = string.rep(' ', vim.lsp.util.get_effective_tabstop())

    local maxflen = max_length(node)

    local lines = {}

    table.insert(lines, apply('<specifier><attributes> <classname> from_string(std::string_view v)'))
    table.insert(lines, apply('{'))
    table.insert(lines, apply('<indent>int  i = 0;'))
    table.insert(lines, apply('<indent>auto r = std::from_chars(v.begin(), v.end(), i);'))
    table.insert(lines, apply('<indent>if (r.ec != std::errc()) {'))
    table.insert(lines, apply('<indent><indent>throw std::runtime_error("Unable to convert " + std::string(v) + " into an integer.");'))
    table.insert(lines, apply('<indent>}'))

    if G.keepindent then
        table.insert(lines, apply('<indent>// clang-format off'))
    end

    local cnt = ast.count_children(node,
        function(n)
            return n.kind == "EnumConstant"
        end
    )

    table.insert(lines, apply('<indent>bool b ='))

    local idx = 1
    ast.visit_children(node,
        function(n)
            if n.kind == "EnumConstant" then
                P.fieldname = ast.name(n)
                P.valuepad  = string.rep(' ', maxflen - string.len(P.fieldname))
                if idx == cnt then
                    table.insert(lines, apply('<indent><indent>i == static_cast<std::underlying_type_t<<classname>>>(<classname>::<fieldname>)<valuepad>;'))
                else
                    table.insert(lines, apply('<indent><indent>i == static_cast<std::underlying_type_t<<classname>>>(<classname>::<fieldname>)<valuepad> ||'))
                end
                idx = idx + 1
            end
        end
    )

    if G.keepindent then
        table.insert(lines, apply('<indent>// clang-format on'))
    end

    table.insert(lines, apply('<indent>if (!b) {'))
    table.insert(lines, apply('<indent><indent>throw std::runtime_error("Value " + std::to_string(i) + " is outside of <classname> enumeration range.");'))
    table.insert(lines, apply('<indent>}'))

    table.insert(lines, apply('<indent>return static_cast<<classname>>(i);'))
    table.insert(lines, apply('}'))

    for _,l in ipairs(lines) do log.debug(l) end
    return lines
end

-- Generate to underlying function for an enum type node - implementation.
local function to_underlying_enum_snippet(node, specifier)
    log.trace("to_underlying_enum_snippet:", ast.details(node))

    P.specifier = specifier
    P.classname = ast.name(node)
    P.indent    = string.rep(' ', vim.lsp.util.get_effective_tabstop())

    local lines = {}

    table.insert(lines, apply('<specifier><attributes> std::underlying_type_t<<classname>> to_underlying(<classname> e)'))
    table.insert(lines, apply('{'))
    table.insert(lines, apply('<indent>return std::underlying_type_t<<classname>>(e);'))
    table.insert(lines, apply('}'))

    for _,l in ipairs(lines) do log.debug(l) end
    return lines
end

-- Generate from string (member) function snippet item for an enum type node.
local function from_string_member_enum_item(node)
    log.trace("from_string_member_enum_item:", ast.details(node))
    local lines = from_string_enum_snippet(node, 'static')
    return
    {
        label            = 'conv',
        kind             = cmp.lsp.CompletionItemKind.Snippet,
        insertTextMode   = 2,
        insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
        insertText       = table.concat(lines, '\n'),
        documentation    = table.concat(lines, '\n')
    }
end

-- Generate from string template function snippet item for an enum type node.
local function from_string_template_enum_item(node)
    log.trace("from_string_template_enum_item:", ast.details(node))
    local lines = from_string_enum_snippet(node, 'template <> inline')
    return
    {
        label            = 'conv',
        kind             = cmp.lsp.CompletionItemKind.Snippet,
        insertTextMode   = 2,
        insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
        insertText       = table.concat(lines, '\n'),
        documentation    = table.concat(lines, '\n')
    }
end

-- Generate to underlying type conversion function snippet item for an enum type node.
local function to_underlying_enum_item(node)
    log.trace("to_underlying_enum_item:", ast.details(node))
    local lines = to_underlying_enum_snippet(node, 'inline')
    return
    {
        label            = 'conv',
        kind             = cmp.lsp.CompletionItemKind.Snippet,
        insertTextMode   = 2,
        insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
        insertText       = table.concat(lines, '\n'),
        documentation    = table.concat(lines, '\n')
    }
end

---------------------------------------------------------------------------------------------------
-- Generate to string converter for an enum type node.
---------------------------------------------------------------------------------------------------
local function to_string_enum_snippet(node, specifier)
    log.trace("to_string_enum_snippet:", ast.details(node))

    P.specifier = specifier
    P.classname = ast.name(node)
    P.indent    = string.rep(' ', vim.lsp.util.get_effective_tabstop())

    local records = enum_labels_and_values(node)
    local maxllen, maxvlen = max_lengths(records)

    local lines = {}

    table.insert(lines, apply('<specifier><attributes> std::string to_string(<classname> o)'))
    table.insert(lines, apply('{'))
    table.insert(lines, apply('<indent>std::string r;'))
    table.insert(lines, apply('<indent>switch(o)'))
    table.insert(lines, apply('<indent>{'))
    if G.keepindent then
        table.insert(lines, apply('<indent><indent>// clang-format off'))
    end

    for _,r in ipairs(records) do
        P.label     = r.label
        P.value     = r.value
        P.labelpad  = string.rep(' ', maxllen - string.len(r.label))
        P.valuepad  = string.rep(' ', maxvlen - string.len(r.value))
        table.insert(lines, apply('<indent><indent>case <label>:<labelpad> r = <value>;<valuepad> break;'))
    end

    if G.keepindent then
        table.insert(lines, apply('<indent><indent>// clang-format on'))
    end
    table.insert(lines, apply('<indent>};'))
    table.insert(lines, apply('<indent>return r;'))
    table.insert(lines, apply('}'))

    for _,l in ipairs(lines) do log.debug(l) end
    return lines
end

-- Generate to string friend converter completion item for an enum type node.
local function friend_to_string_enum_item(node)
    log.trace("friend_to_string_enum_item:", ast.details(node))
    local lines = to_string_enum_snippet(node, 'friend')
    return
    {
        label            = 'conv',
        kind             = cmp.lsp.CompletionItemKind.Snippet,
        insertTextMode   = 2,
        insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
        insertText       = table.concat(lines, '\n'),
        documentation    = table.concat(lines, '\n')
    }
end

-- Generate to string inline converter completion item for an enum type node.
local function inline_to_string_enum_item(node)
    log.trace("inline_to_string_enum_item:", ast.details(node))
    local lines = to_string_enum_snippet(node, 'inline')
    return
    {
        label            = 'conv',
        kind             = cmp.lsp.CompletionItemKind.Snippet,
        insertTextMode   = 2,
        insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
        insertText       = table.concat(lines, '\n'),
        documentation    = table.concat(lines, '\n')
    }
end

---------------------------------------------------------------------------------------------------
-- Generate enumerator string converter for an enum type node.
---------------------------------------------------------------------------------------------------
local function to_enumerator_string_enum_snippet(node, specifier)
    log.trace("to_enumerator_string_enum_snippet:", ast.details(node))

    P.specifier = specifier
    P.classname = ast.name(node)
    P.indent    = string.rep(' ', vim.lsp.util.get_effective_tabstop())

    local function labels_and_values()
        local records = {}
        ast.visit_children(node,
            function(n)
                if n.kind == "EnumConstant" then
                    local record = {}
                    record.label = ast.name(node) .. '::' .. ast.name(n)
                    record.value = '"' .. ast.name(n) .. '"'
                    table.insert(records, record)
                end
            end
        )
        return records
    end

    local records = labels_and_values()
    local maxllen, maxvlen = max_lengths(records)

    local lines = {}

    table.insert(lines, apply('<specifier><attributes> std::string enumerator(<classname> o)'))
    table.insert(lines, apply('{'))
    table.insert(lines, apply('<indent>std::string r;'))
    table.insert(lines, apply('<indent>switch(o)'))
    table.insert(lines, apply('<indent>{'))
    if G.keepindent then
        table.insert(lines, apply('<indent><indent>// clang-format off'))
    end

    for _,r in ipairs(records) do
        P.label     = r.label
        P.value     = r.value
        P.labelpad  = string.rep(' ', maxllen - string.len(r.label))
        P.valuepad  = string.rep(' ', maxvlen - string.len(r.value))
        table.insert(lines, apply('<indent><indent>case <label>:<labelpad> r = <value>;<valuepad> break;'))
    end

    if G.keepindent then
        table.insert(lines, apply('<indent><indent>// clang-format on'))
    end
    table.insert(lines, apply('<indent>};'))
    table.insert(lines, apply('<indent>return r;'))
    table.insert(lines, apply('}'))

    for _,l in ipairs(lines) do log.debug(l) end
    return lines
end

-- Generate to string friend converter completion item for an enum type node.
local function friend_to_enumerator_string_enum_item(node)
    log.trace("friend_to_enumerator_string_enum_item:", ast.details(node))
    local lines = to_enumerator_string_enum_snippet(node, 'friend')
    return
    {
        label            = 'conv',
        kind             = cmp.lsp.CompletionItemKind.Snippet,
        insertTextMode   = 2,
        insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
        insertText       = table.concat(lines, '\n'),
        documentation    = table.concat(lines, '\n')
    }
end

-- Generate to string inline converter completion item for an enum type node.
local function inline_to_enumerator_string_enum_item(node)
    log.trace("inline_to_enumerator_string_enum_item:", ast.details(node))
    local lines = to_enumerator_string_enum_snippet(node, 'inline')
    return
    {
        label            = 'conv',
        kind             = cmp.lsp.CompletionItemKind.Snippet,
        insertTextMode   = 2,
        insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
        insertText       = table.concat(lines, '\n'),
        documentation    = table.concat(lines, '\n')
    }
end

local M = {}

local function is_enum(node)
    return node and node.role == "declaration" and node.kind == "Enum" and not string.find(node.detail, "unnamed ")
end

local function is_class(node)
    return node and node.role == "declaration" and node.kind == "CXXRecord"
end

local enclosing_node = nil
local preceding_node = nil

--- Generator will call this method before presenting a set of new candidate nodes
function M.reset()
    enclosing_node = nil
    preceding_node = nil
end

--- Generator will call this method with new candidate node
function M.visit(node, line)
    -- We can generate conversion function for preceding enumeration node
    if ast.precedes(node, line) and is_enum(node) then
        log.debug("visit:", "Accepted preceding node", ast.details(node))
        preceding_node = node
    end
    -- We capture enclosing class node since the specifier for the enum conversion depends on it
    if ast.encloses(node, line) and is_class(node) then
        log.debug("visit:", "Accepted enclosing node", ast.details(node))
        enclosing_node = node
    end
end

--- Generator will call this method to check if the module can generate code
function M.available()
    return enclosing_node ~= nil or preceding_node ~= nil
end

-- Generate from string functions for an enum nodes.
function M.completion_items()
    log.trace("completion_items:", ast.details(preceding_node), ast.details(enclosing_node))

    local items = {}

    if is_enum(preceding_node) then
        if is_class(enclosing_node) then
            table.insert(items, from_string_member_enum_item(preceding_node))
            table.insert(items, friend_to_string_enum_item(preceding_node))
            table.insert(items, friend_to_enumerator_string_enum_item(preceding_node))
        else
            table.insert(items, from_string_template_enum_item(preceding_node))
            table.insert(items, inline_to_string_enum_item(preceding_node))
            table.insert(items, inline_to_enumerator_string_enum_item(preceding_node))
        end
        table.insert(items, to_underlying_enum_item(preceding_node))
    end

    return items
end

---------------------------------------------------------------------------------------------------
--- Initialization callback
---------------------------------------------------------------------------------------------------
function M.setup(opts)
    if opts then
        if opts.keepindent ~= nil then
            G.keepindent = opts.keepindent
        end
        if opts.attributes ~= nil then
            G.attributes = opts.attributes
        end
        if opts.cnv then
            if opts.cnv.keepindent ~= nil then
                G.keepindent = opts.cnv.keepindent
            end
            if opts.cnv.attributes ~= nil then
                G.attributes = opts.cnv.attributes
            end
            if opts.cnv.enum then
                if opts.cnv.enum.value then
                    G.enum.value = opts.cnv.enum.value
                end
            end
        end
    end
end

return M
