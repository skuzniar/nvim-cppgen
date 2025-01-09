local ast = require('cppgen.ast')
local log = require('cppgen.log')
local utl = require('cppgen.gen.util')

local cmp = require('cmp')

---------------------------------------------------------------------------------------------------
-- Enum function generators.
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Global parameters for code generation. Initialized in setup.
---------------------------------------------------------------------------------------------------
local G = {}

---------------------------------------------------------------------------------------------------
-- Local parameters for code generation.
---------------------------------------------------------------------------------------------------
local P = {}

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

-- Collect names and values for an enum type node. Labels are fixed, values are calculated.
local function labels_and_values(node, vf)
    log.trace("labels_and_values:", ast.details(node))

    local lsandvs = {}
    for _,r in ipairs(utl.enum_records(node)) do
        local record = {}
        record.label = ast.name(node) .. '::' .. r.label
        record.value = vf(r.label, r.value)
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

    local records = labels_and_values(node, G.enum.to_string.value)
    local maxllen, maxvlen = max_lengths(records)

    local lines = {}

    table.insert(lines, apply('<specifier><attributes> std::string ' .. G.enum.to_string.name .. '(<classname> o)'))
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
        table.insert(lines, apply('<indent><indent>case <label>:<labelpad> return <value>;<valuepad> break;'))
    end

    if G.keepindent then
        table.insert(lines, apply('<indent><indent>// clang-format on'))
    end
    table.insert(lines, apply('<indent>};'))
    table.insert(lines, apply('}'))

    for _,l in ipairs(lines) do log.debug(l) end
    return lines
end

-- Optionally replicate the lines and generate multiple completion items that can be triggered by different labels.
local function to_string_items(lines)
    return
    {
        {
            label            = G.enum.to_string.name,
            kind             = cmp.lsp.CompletionItemKind.Snippet,
            insertTextMode   = 2,
            insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
            insertText       = table.concat(lines, '\n'),
            documentation    = table.concat(lines, '\n')
        },
        G.enum.to_string.trigger ~= G.enum.to_string.name and
        {
            label            = G.enum.to_string.trigger,
            kind             = cmp.lsp.CompletionItemKind.Snippet,
            insertTextMode   = 2,
            insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
            insertText       = table.concat(lines, '\n'),
            documentation    = table.concat(lines, '\n')
        } or nil
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
-- Generate enumerator cast. Converts from string matching on enumerator name.
---------------------------------------------------------------------------------------------------
local function enum_cast_snippet(node, specifier)
    log.trace("enum_cast_snippet:", ast.details(node))

    P.specifier  = specifier
    P.attributes = G.attributes and ' ' .. G.attributes or ''
    P.classname  = ast.name(node)
    P.indent     = string.rep(' ', vim.lsp.util.get_effective_tabstop())

    local maxllen, _ = max_lengths(utl.enum_records(node))

    local lines = {}

    table.insert(lines, apply('<specifier><attributes> <classname> ' .. G.enum.cast.name .. '(std::string_view e)'))
    table.insert(lines, apply('{'))

    if G.keepindent then
        table.insert(lines, apply('<indent>// clang-format off'))
    end
    ast.visit_children(node,
        function(n)
            if n.kind == "EnumConstant" then
                P.fieldname = ast.name(n)
                P.valuepad  = string.rep(' ', maxllen - string.len(P.fieldname))
                table.insert(lines, apply('<indent>if (e == "<fieldname>")<valuepad> return <classname>::<fieldname>;'))
            end
            return true
        end
    )
    if G.keepindent then
        table.insert(lines, apply('<indent>// clang-format on'))
    end

    table.insert(lines, apply('<indent>throw ' .. G.enum.cast.enum_cast.exception(P.classname, 'e') .. ';'))
    table.insert(lines, apply('}'))

    -- Add a forwarding function that takes char pointer and forwards it as string view
    table.insert(lines, apply('<specifier><attributes> <classname> ' .. G.enum.cast.name .. '(const char* e)'))
    table.insert(lines, apply('{'))
    table.insert(lines, apply('<indent>return ' .. G.enum.cast.name .. '<<classname>>(std::string_view(e));'))
    table.insert(lines, apply('}'))

    for _,l in ipairs(lines) do log.debug(l) end
    return lines
end

---------------------------------------------------------------------------------------------------
-- Generate enumerator cast. Converts from integer matching on enumerator value.
---------------------------------------------------------------------------------------------------
local function value_cast_snippet(node, specifier)
    log.trace("value_cast_snippet:", ast.details(node))

    P.specifier  = specifier
    P.attributes = G.attributes and ' ' .. G.attributes or ''
    P.classname  = ast.name(node)
    P.indent     = string.rep(' ', vim.lsp.util.get_effective_tabstop())

    local maxllen, _ = max_lengths(utl.enum_records(node))

    local lines = {}

    table.insert(lines, apply('<specifier><attributes> <classname> ' .. G.enum.cast.name .. '(int v)'))
    table.insert(lines, apply('{'))

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
                    table.insert(lines, apply('<indent><indent>v == static_cast<std::underlying_type_t<<classname>>>(<classname>::<fieldname>)<valuepad>)'))
                else
                    table.insert(lines, apply('<indent><indent>v == static_cast<std::underlying_type_t<<classname>>>(<classname>::<fieldname>)<valuepad> ||'))
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
    table.insert(lines, apply('<indent><indent>return static_cast<<classname>>(v);'))
    table.insert(lines, apply('<indent>}'))
    table.insert(lines, apply('<indent>throw ' .. G.enum.cast.value_cast.exception(P.classname, 'v') .. ';'))
    table.insert(lines, apply('}'))

    -- Add a forwarding function that takes char and forwards it as integer
    table.insert(lines, apply('<specifier><attributes> <classname> ' .. G.enum.cast.name .. '(char v)'))
    table.insert(lines, apply('{'))
    table.insert(lines, apply('<indent>return ' .. G.enum.cast.name .. '<<classname>>(static_cast<int>(v));'))
    table.insert(lines, apply('}'))

    for _,l in ipairs(lines) do log.debug(l) end
    return lines
end

-- Combine multiple completion items.
local function cast_items(...)
    local lines = ''
    for _,t in ipairs({...}) do
        if next(t) ~= nil then
            lines = lines .. (lines == '' and '' or '\n') .. table.concat(t, '\n')
        end
    end

    return lines == '' and {} or
    {
        {
            label            = G.enum.cast.name,
            kind             = cmp.lsp.CompletionItemKind.Snippet,
            insertTextMode   = 2,
            insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
            insertText       = lines,
            documentation    = lines,
        },
        G.enum.cast.trigger ~= G.enum.cast.name and
        {
            label            = G.enum.cast.trigger,
            kind             = cmp.lsp.CompletionItemKind.Snippet,
            insertTextMode   = 2,
            insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
            insertText       = lines,
            documentation    = lines,
        } or nil
    }
end

-- Generate from string enumerator member function snippet item for an enum type node.
local function cast_member_items(node)
    log.trace("enum_cast_member_items:", ast.details(node))
    return cast_items(
        G.enum.cast.enum_cast.enabled  and enum_cast_snippet  (node, 'template <>') or {},
        G.enum.cast.value_cast.enabled and value_cast_snippet (node, 'template <>') or {})
end

-- Generate from string enumerator free function snippet item for an enum type node.
local function cast_free_items(node)
    log.trace("enum_cast_free_items:", ast.details(node))
    return cast_items(
        G.enum.cast.enum_cast.enabled  and enum_cast_snippet  (node, 'template <> inline') or {},
        G.enum.cast.value_cast.enabled and value_cast_snippet (node, 'template <> inline') or {})
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

    local records = labels_and_values(node, G.enum.shift.value)
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

-- Optionally replicate the lines and generate multiple completion items that can be triggered by different labels.
local function shift_items(lines)
    return
    {
        {
            label            = G.enum.shift.trigger,
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

---------------------------------------------------------------------------------------------------
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

-- Add elements of one table into another table
local function add_to(to, from)
    for _,item in ipairs(from) do
        table.insert(to, item)
    end
end
---------------------------------------------------------------------------------------------------
-- Generate from string functions for an enum nodes.
---------------------------------------------------------------------------------------------------
function M.generate()
    log.trace("generate:", ast.details(preceding_node), ast.details(enclosing_node))

    local items = {}

    if ast.is_enum(preceding_node) then
        if ast.is_class(enclosing_node) then
            add_to(items, to_string_member_items(preceding_node))
            add_to(items, cast_member_items(preceding_node))
            add_to(items, shift_member_items(preceding_node))
        else
            add_to(items, to_string_free_items(preceding_node))
            add_to(items, cast_free_items(preceding_node))
            add_to(items, shift_free_items(preceding_node))
        end
    end

    return items
end

---------------------------------------------------------------------------------------------------
--- Info callback
---------------------------------------------------------------------------------------------------
local function combine(name, trigger)
    return name == trigger and name or name .. ' or ' .. trigger
end

function M.info()
    return {
        { combine(G.enum.to_string.name, G.enum.to_string.trigger), "Enum to string converter"   },
        { combine(G.enum.cast.name, G.enum.cast.trigger),           "Enum from string and enum from underlying type converter" },
        { G.enum.shift.trigger,                                     "Enum output stream shift operator" }
    }
end

---------------------------------------------------------------------------------------------------
--- Initialization callback. Capture relevant parts of the configuration.
---------------------------------------------------------------------------------------------------
function M.setup(opts)
    G.keepindent = opts.keepindent
    G.attributes = opts.attributes
    G.enum       = opts.enum
end

return M
