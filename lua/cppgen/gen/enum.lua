local ast = require('cppgen.ast')
local log = require('cppgen.log')
local utl = require('cppgen.gen.util')

local cmp = require('cmp')

---------------------------------------------------------------------------------------------------
-- Enum function generators.
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
        return '"' .. value .. ' ' .. '(' .. mnemonic .. ')' .. '"'
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

-- Collect names and values for an enum type node.
local function labels_and_values(node)
    log.trace("labels_and_values:", ast.details(node))

    local lsandvs = {}
    for _,r in ipairs(utl.enum_records(node)) do
        local record = {}
        record.label = ast.name(node) .. '::' .. r.label
        record.value = G.enum.value(r.label, r.value)
        table.insert(lsandvs, record)
    end
    return lsandvs
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

---------------------------------------------------------------------------------------------------
-- Generate to string converter.
---------------------------------------------------------------------------------------------------
local function to_string_snippet(node, specifier)
    log.trace("to_string_snippet:", ast.details(node))

    P.specifier  = specifier
    P.attributes = G.attributes and ' ' .. G.attributes or ''
    P.classname  = ast.name(node)
    P.indent     = string.rep(' ', vim.lsp.util.get_effective_tabstop())

    local records = labels_and_values(node)
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
local function friend_to_string_item(node)
    log.trace("friend_to_string_item:", ast.details(node))
    local lines = to_string_snippet(node, 'friend')
    return
    {
        label            = 'to_string',
        kind             = cmp.lsp.CompletionItemKind.Snippet,
        insertTextMode   = 2,
        insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
        insertText       = table.concat(lines, '\n'),
        documentation    = table.concat(lines, '\n')
    }
end

-- Generate to string inline converter completion item for an enum type node.
local function inline_to_string_item(node)
    log.trace("inline_to_string_item:", ast.details(node))
    local lines = to_string_snippet(node, 'inline')
    return
    {
        label            = 'to_string',
        kind             = cmp.lsp.CompletionItemKind.Snippet,
        insertTextMode   = 2,
        insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
        insertText       = table.concat(lines, '\n'),
        documentation    = table.concat(lines, '\n')
    }
end

---------------------------------------------------------------------------------------------------
-- Generate from string converter
---------------------------------------------------------------------------------------------------
local function from_string_snippet(node, specifier)
    log.trace("from_string_snippet:", ast.details(node))

    P.specifier  = specifier
    P.attributes = G.attributes and ' ' .. G.attributes or ''
    P.classname  = ast.name(node)
    P.indent     = string.rep(' ', vim.lsp.util.get_effective_tabstop())

    local records = utl.enum_records(node)

    --- Only enumerators with the same literal type can be converted
    local intlit = false
    local chrlit = false
    for _,r in ipairs(records) do
        if r.kind == "IntegerLiteral" then
            intlit = true
        elseif r.kind == "CharacterLiteral" then
            chrlit = true
        end
    end

    local lines = {}

    if intlit == chrlit then
        return lines
    end

    local maxllen, _ = max_lengths(records)

    table.insert(lines, apply('<specifier><attributes> <classname> from_string(std::string_view v)'))
    table.insert(lines, apply('{'))
    if intlit then
        table.insert(lines, apply('<indent>int  i = 0;'))
        table.insert(lines, apply('<indent>auto r = std::from_chars(v.begin(), v.end(), i);'))
        table.insert(lines, apply('<indent>if (r.ec != std::errc()) {'))
        table.insert(lines, apply('<indent><indent>throw std::runtime_error("Unable to convert " + std::string(v) + " into an integer.");'))
        table.insert(lines, apply('<indent>}'))
    else
        table.insert(lines, apply('<indent>if (v.size() != 1) {'))
        table.insert(lines, apply('<indent><indent>throw std::runtime_error("Unable to convert " + std::string(v) + " into a character.");'))
        table.insert(lines, apply('<indent>}'))
        table.insert(lines, apply('<indent>char  i = v[0];'))
    end

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
                P.valuepad  = string.rep(' ', maxllen - string.len(P.fieldname))
                if idx == cnt then
                    table.insert(lines, apply('<indent><indent>i == static_cast<std::underlying_type_t<<classname>>>(<classname>::<fieldname>)<valuepad>;'))
                else
                    table.insert(lines, apply('<indent><indent>i == static_cast<std::underlying_type_t<<classname>>>(<classname>::<fieldname>)<valuepad> ||'))
                end
                idx = idx + 1
            end
            return true
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

-- Generate from string member function snippet item for an enum type node.
local function from_string_member_item(node)
    log.trace("from_string_member_item:", ast.details(node))
    local lines = from_string_snippet(node, 'static')
    return
    {
        label            = 'from_string',
        kind             = cmp.lsp.CompletionItemKind.Snippet,
        insertTextMode   = 2,
        insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
        insertText       = table.concat(lines, '\n'),
        documentation    = table.concat(lines, '\n')
    }
end

-- Generate from string template function snippet item for an enum type node.
local function from_string_template_item(node)
    log.trace("from_string_template_item:", ast.details(node))
    local lines = from_string_snippet(node, 'template <> inline')
    return
    {
        label            = 'from_string',
        kind             = cmp.lsp.CompletionItemKind.Snippet,
        insertTextMode   = 2,
        insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
        insertText       = table.concat(lines, '\n'),
        documentation    = table.concat(lines, '\n')
    }
end

---------------------------------------------------------------------------------------------------
-- Generate output stream shift operator
---------------------------------------------------------------------------------------------------
local function shift_snippet(node, specifier)
    log.trace("shift_snippet:", ast.details(node))

    P.specifier  = specifier
    P.attributes = G.attributes and ' ' .. G.attributes or ''
    P.classname  = ast.name(node)
    P.indent     = string.rep(' ', vim.lsp.util.get_effective_tabstop())

    local records = labels_and_values(node)
    local maxllen, maxvlen = max_lengths(records)

    local lines = {}

    table.insert(lines, apply('<specifier><attributes> std::ostream& operator<<(std::ostream& s, <classname> o)'))
    table.insert(lines, apply('{'))
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
        table.insert(lines, apply('<indent><indent>case <label>:<labelpad> s << <value>;<valuepad> break;'))
    end

    if G.keepindent then
        table.insert(lines, apply('<indent><indent>// clang-format on'))
    end
    table.insert(lines, apply('<indent>};'))

    table.insert(lines, apply('<indent>return s;'))
    table.insert(lines, apply('}'))

    for _,l in ipairs(lines) do log.debug(l) end
    return lines
end

-- Generate output stream friend shift operator completion item for an enum type node.
local function friend_shift_item(node)
    log.trace("friend_shift_item:", ast.details(node))
    local lines = shift_snippet(node, 'friend')
    return
    {
        label            = lines[1] or 'friend',
        kind             = cmp.lsp.CompletionItemKind.Snippet,
        insertTextMode   = 2,
        insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
        insertText       = table.concat(lines, '\n'),
        documentation    = table.concat(lines, '\n')
    }
end

-- Generate output stream inline shift operator completion item for an enum type node.
local function inline_shift_item(node)
    log.trace("inline_shift_item:", ast.details(node))
    local lines = shift_snippet(node, 'inline')
    return
    {
        label            = lines[1] or 'inline',
        kind             = cmp.lsp.CompletionItemKind.Snippet,
        insertTextMode   = 2,
        insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
        insertText       = table.concat(lines, '\n'),
        documentation    = table.concat(lines, '\n')
    }
end

--- Exported functions
---------------------------------------------------------------------------------------------------
local M = {}

local enclosing_node = nil
local preceding_node = nil

--- Generator will call this method before presenting a set of new candidate nodes
function M.reset()
    enclosing_node = nil
    preceding_node = nil
end

---------------------------------------------------------------------------------------------------
--- Generator will call this method with a node and a cursor line location.
---------------------------------------------------------------------------------------------------
function M.visit(node, line)
    -- We can generate conversion function for preceding enumeration node
    if ast.precedes(node, line) and ast.is_enum(node) then
        log.debug("visit:", "Accepted preceding node", ast.details(node))
        preceding_node = node
    end
    -- We capture enclosing class node since the specifier for the enum conversion depends on it
    if ast.encloses(node, line) and ast.is_class(node) then
        log.debug("visit:", "Accepted enclosing node", ast.details(node))
        enclosing_node = node
    end
end

---------------------------------------------------------------------------------------------------
--- Generator will call this method to check if the module can generate code
---------------------------------------------------------------------------------------------------
function M.available()
    return enclosing_node ~= nil or preceding_node ~= nil
end

---------------------------------------------------------------------------------------------------
-- Generate from string functions for an enum nodes.
---------------------------------------------------------------------------------------------------
function M.generate()
    log.trace("generate:", ast.details(preceding_node), ast.details(enclosing_node))

    local items = {}

    if ast.is_enum(preceding_node) then
        if ast.is_class(enclosing_node) then
            table.insert(items, from_string_member_item(preceding_node))
            table.insert(items, friend_to_string_item(preceding_node))
            table.insert(items, friend_shift_item(preceding_node))
        else
            table.insert(items, from_string_template_item(preceding_node))
            table.insert(items, inline_to_string_item(preceding_node))
            table.insert(items, inline_shift_item(preceding_node))
        end
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
        if opts.enum then
            if opts.enum.keepindent ~= nil then
                G.keepindent = opts.enum.keepindent
            end
            if opts.enum.attributes ~= nil then
                G.attributes = opts.enum.attributes
            end
            if opts.enum.value then
                G.enum.value = opts.enum.value
            end
        end
    end
end

return M
