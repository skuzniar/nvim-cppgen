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
G.attributes = ''

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
        if r.label then
            max_lab_len = math.max(max_lab_len, string.len(r.label))
        end
        if r.value then
            max_val_len = math.max(max_val_len, string.len(r.value))
        end
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

-- Duplicate the lines and generate two completion items that can be triggered by different labels.
local function to_string_items(lines)
    return
    {
        {
            label            = "convert",
            kind             = cmp.lsp.CompletionItemKind.Snippet,
            insertTextMode   = 2,
            insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
            insertText       = table.concat(lines, '\n'),
            documentation    = table.concat(lines, '\n')
        },
        {
            label            = "to_string",
            kind             = cmp.lsp.CompletionItemKind.Snippet,
            insertTextMode   = 2,
            insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
            insertText       = table.concat(lines, '\n'),
            documentation    = table.concat(lines, '\n')
        }
    }
end

-- Generate to string member function converter completion item for an enum type node.
local function to_string_member_items(node)
    log.trace("to_string_member_items:", ast.details(node))
    return to_string_items(to_string_snippet(node, 'friend'))
end

-- Generate to string free function converter completion item for an enum type node.
local function to_string_free_items(node)
    log.trace("to_string_free_items:", ast.details(node))
    return to_string_items(to_string_snippet(node, 'inline'))
end

---------------------------------------------------------------------------------------------------
-- Generate from string converter
---------------------------------------------------------------------------------------------------
local function from_string_mnemonic_snippet(node, specifier)
    log.trace("from_string_mnemonic_snippet:", ast.details(node))

    P.specifier  = specifier
    P.attributes = G.attributes and ' ' .. G.attributes or ''
    P.classname  = ast.name(node)
    P.indent     = string.rep(' ', vim.lsp.util.get_effective_tabstop())

    local maxllen, _ = max_lengths(utl.enum_records(node))

    local lines = {}

    table.insert(lines, apply('<specifier><attributes> <classname> from_string(std::string_view v)'))
    table.insert(lines, apply('{'))

    if G.keepindent then
        table.insert(lines, apply('<indent>// clang-format off'))
    end
    ast.visit_children(node,
        function(n)
            if n.kind == "EnumConstant" then
                P.fieldname = ast.name(n)
                P.valuepad  = string.rep(' ', maxllen - string.len(P.fieldname))
                table.insert(lines, apply('<indent>if (v == "<fieldname>")<valuepad> return <classname>::<fieldname>;'))
            end
            return true
        end
    )
    if G.keepindent then
        table.insert(lines, apply('<indent>// clang-format on'))
    end

    table.insert(lines, apply('<indent>throw std::runtime_error("Value " + std::string(v) + " is outside of <classname> enumeration range.");'))

    table.insert(lines, apply('}'))

    for _,l in ipairs(lines) do log.debug(l) end
    return lines
end

-- Duplicate the lines and generate two completion items that can be triggered by different labels.
local function from_string_mnemonic_items(lines)
    return
    {
        {
            label            = "convert",
            kind             = cmp.lsp.CompletionItemKind.Snippet,
            insertTextMode   = 2,
            insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
            insertText       = table.concat(lines, '\n'),
            documentation    = table.concat(lines, '\n')
        },
        {
            label            = "from_string",
            kind             = cmp.lsp.CompletionItemKind.Snippet,
            insertTextMode   = 2,
            insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
            insertText       = table.concat(lines, '\n'),
            documentation    = table.concat(lines, '\n')
        }
    }
end

-- Generate from string mnemonic member function snippet item for an enum type node.
local function from_string_mnemonic_member_items(node)
    log.trace("from_string_mnemonic_member_items:", ast.details(node))
    return from_string_mnemonic_items(from_string_mnemonic_snippet(node, 'template <>'))
end

-- Generate from string mnemonic free function snippet item for an enum type node.
local function from_string_mnemonic_free_items(node)
    log.trace("from_string_mnemonic_free_items:", ast.details(node))
    return from_string_mnemonic_items(from_string_mnemonic_snippet(node, 'template <> inline'))
end

---------------------------------------------------------------------------------------------------
-- Generate from string converter
---------------------------------------------------------------------------------------------------
local function from_string_value_snippet(node, specifier)
    log.trace("from_string_value_snippet:", ast.details(node))

    P.specifier  = specifier
    P.attributes = G.attributes and ' ' .. G.attributes or ''
    P.classname  = ast.name(node)
    P.indent     = string.rep(' ', vim.lsp.util.get_effective_tabstop())

    local maxllen, _ = max_lengths(utl.enum_records(node))

    local lines = {}

    table.insert(lines, apply('<specifier><attributes> <classname> from_string(std::string_view v)'))
    table.insert(lines, apply('{'))

    table.insert(lines, apply('<indent>std::underlying_type_t<<classname>> i = 0;'))
    table.insert(lines, apply('<indent>auto r = std::from_chars(v.begin(), v.end(), i);'))
    table.insert(lines, apply('<indent>if (r.ec != std::errc()) {'))
    table.insert(lines, apply('<indent><indent>throw std::runtime_error("Unable to convert " + std::string(v) + " into an underlying type.");'))
    table.insert(lines, apply('<indent>}'))

    local cnt = ast.count_children(node,
        function(n)
            return n.kind == "EnumConstant"
        end
    )

    table.insert(lines, apply('<indent>if ('))

    if G.keepindent then
        table.insert(lines, apply('<indent><indent>// clang-format off'))
    end
    local idx = 1
    ast.visit_children(node,
        function(n)
            if n.kind == "EnumConstant" then
                P.fieldname = ast.name(n)
                P.valuepad  = string.rep(' ', maxllen - string.len(P.fieldname))
                if idx == cnt then
                    table.insert(lines, apply('<indent><indent>i == static_cast<std::underlying_type_t<<classname>>>(<classname>::<fieldname>)<valuepad>)'))
                else
                    table.insert(lines, apply('<indent><indent>i == static_cast<std::underlying_type_t<<classname>>>(<classname>::<fieldname>)<valuepad> ||'))
                end
                idx = idx + 1
            end
            return true
        end
    )
    if G.keepindent then
        table.insert(lines, apply('<indent><indent>// clang-format on'))
    end

    table.insert(lines, apply('<indent>{'))
    table.insert(lines, apply('<indent><indent>return static_cast<<classname>>(i);'))
    table.insert(lines, apply('<indent>}'))

    table.insert(lines, apply('<indent>throw std::runtime_error("Value " + std::to_string(i) + " is outside of <classname> enumeration range.");'))

    table.insert(lines, apply('}'))

    for _,l in ipairs(lines) do log.debug(l) end
    return lines
end

-- Duplicate the lines and generate two completion items that can be triggered by different labels.
local function from_string_value_items(lines)
    return
    {
        {
            label            = "convert",
            kind             = cmp.lsp.CompletionItemKind.Snippet,
            insertTextMode   = 2,
            insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
            insertText       = table.concat(lines, '\n'),
            documentation    = table.concat(lines, '\n')
        },
        {
            label            = "from_string",
            kind             = cmp.lsp.CompletionItemKind.Snippet,
            insertTextMode   = 2,
            insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
            insertText       = table.concat(lines, '\n'),
            documentation    = table.concat(lines, '\n')
        }
    }
end

-- Generate from string member function snippet item for an enum type node.
local function from_string_value_member_items(node)
    log.trace("from_string_value_member_items:", ast.details(node))
    return from_string_value_items(from_string_value_snippet(node, 'template <>'))
end

-- Generate from string free function snippet item for an enum type node.
local function from_string_value_free_items(node)
    log.trace("from_string_value_free_items:", ast.details(node))
    return from_string_value_items(from_string_value_snippet(node, 'template <> inline'))
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

-- Duplicate the lines and generate two completion items that can be triggered by different labels.
local function shift_items(lines)
    return
    {
        {
            label            = "shift",
            kind             = cmp.lsp.CompletionItemKind.Snippet,
            insertTextMode   = 2,
            insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
            insertText       = table.concat(lines, '\n'),
            documentation    = table.concat(lines, '\n')
        },
        {
            label            = string.match(lines[1], "^([%w]+)"),
            kind             = cmp.lsp.CompletionItemKind.Snippet,
            insertTextMode   = 2,
            insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
            insertText       = table.concat(lines, '\n'),
            documentation    = table.concat(lines, '\n')
        }
    }
end

-- Generate output stream shift member operator completion item for an enum type node.
local function shift_member_items(node)
    log.trace("shift_member_items:", ast.details(node))
    return shift_items(shift_snippet(node, 'friend'))
end

-- Generate output stream shift free operator completion item for an enum type node.
local function shift_free_items(node)
    log.trace("shift_free_items:", ast.details(node))
    return shift_items(shift_snippet(node, 'inline'))
end

--- Exported functions
---------------------------------------------------------------------------------------------------
local M = {}

local enclosing_node = nil
local preceding_node = nil

--- Generator will call this method before presenting a set of new candidate nodes
function M.reset()
    log.trace("reset:")
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
            for _,item in ipairs(from_string_mnemonic_member_items(preceding_node)) do
                table.insert(items, item)
            end
            for _,item in ipairs(from_string_value_member_items(preceding_node)) do
                table.insert(items, item)
            end
            for _,item in ipairs(to_string_member_items(preceding_node)) do
                table.insert(items, item)
            end
            for _,item in ipairs(shift_member_items(preceding_node)) do
                table.insert(items, item)
            end
        else
            for _,item in ipairs(from_string_mnemonic_free_items(preceding_node)) do
                table.insert(items, item)
            end
            for _,item in ipairs(from_string_value_free_items(preceding_node)) do
                table.insert(items, item)
            end
            for _,item in ipairs(to_string_free_items(preceding_node)) do
                table.insert(items, item)
            end
            for _,item in ipairs(shift_free_items(preceding_node)) do
                table.insert(items, item)
            end
        end
    end

    return items
end

---------------------------------------------------------------------------------------------------
--- Status callback
---------------------------------------------------------------------------------------------------
function M.status()
    return {
        { "to_string",    "Generate to string enum converter"   },
        { "convert",      "Generate to string enum converter"   },
        { "from_string",  "Generate from string enum converter" },
        { "convert",      "Generate from string enum converter" },
        { "shift",        "Generate enum output stream shift operator" }
    }
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
