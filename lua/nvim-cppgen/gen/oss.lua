local ast = require('nvim-cppgen.ast')
local log = require('nvim-cppgen.log')

local cmp = require('cmp')

---------------------------------------------------------------------------------------------------
-- Output stream shift operators generator.
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Global parameters for code generation.
---------------------------------------------------------------------------------------------------
local G = {}

G.keepindent = true

---------------------------------------------------------------------------------------------------
-- Class specific parameters
---------------------------------------------------------------------------------------------------
G.class = {}
G.class.separator = "' '"

-- Create the string that will be printed before any member fierlds.
G.class.preamble = function(classname)
    return '[' .. classname .. ']='
end

-- Create the label string for the member field. By default we use camelized name.
G.class.label = function(classname, fieldname, camelized)
    return camelized .. ': '
end

-- Create the value string for the member field. By default we use field reference
G.class.value = function(fieldref)
    return fieldref
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

local function capitalize(s)
    return (string.gsub(s, '^%l', string.upper))
end

local function camelize(s)
    s = string.gsub(s, '^%a_', '')
    return (string.gsub(s, '%W*(%w+)', capitalize))
end

---------------------------------------------------------------------------------------------------
-- Local parameters for code generation.
---------------------------------------------------------------------------------------------------
local P = {}

-- Apply parameters to the format string 
local function apply(format)
    local result  = format

    result = string.gsub(result, "<label>",     P.label     or '')
    result = string.gsub(result, "<labelpad>",  P.labelpad  or '')
    result = string.gsub(result, "<value>",     P.value     or '')
    result = string.gsub(result, "<valuepad>",  P.valuepad  or '')
    result = string.gsub(result, "<specifier>", P.specifier or '')
    result = string.gsub(result, "<classname>", P.classname or '')
    result = string.gsub(result, "<fieldname>", P.fieldname or '')
    result = string.gsub(result, "<separator>", P.separator or '')
    result = string.gsub(result, "<indent>",    P.indent    or '')

    return result;
end

-- Collect names and values for a class type node.
local function class_labels_and_values(node, object)
    local records = {}
    ast.visit_children(node,
        function(n)
            if n.kind == "Field" then
                local record = {}
                record.field = ast.name(n)
                record.label = G.class.label(ast.name(node), record.field, camelize(record.field))
                record.value = G.class.value(object .. '.' .. record.field)
                table.insert(records, record)
            end
        end
    )
    return records
end

---------------------------------------------------------------------------------------------------
-- Generate output stream shift operator for a class type node.
---------------------------------------------------------------------------------------------------
local function shift_class_snippet(node, specifier)
    log.debug("shift_class_snippet:", ast.details(node))

    P.specifier = specifier
    P.classname = ast.name(node)
    P.separator = G.class.separator
    P.indent    = string.rep(' ', vim.lsp.util.get_effective_tabstop())

    local records = class_labels_and_values(node, 'o')
    local maxllen, maxvlen = max_lengths(records)

    local lines = {}

    table.insert(lines, apply('<specifier> std::ostream& operator<<(std::ostream& s, const <classname>& o)'))
    table.insert(lines, apply('{'))
    if G.keepindent then
        table.insert(lines, apply('<indent>// clang-format off'))
    end

    if G.class.preamble then
        table.insert(lines, apply('<indent>s << "' .. G.class.preamble(P.classname) .. '";'))
    end

    local idx = 1
    for _,r in ipairs(records) do
        P.fieldname = r.field
        P.label     = r.label
        P.value     = r.value
        P.labelpad  = string.rep(' ', maxllen - string.len(r.label))
        P.valuepad  = string.rep(' ', maxvlen - string.len(r.value))
        if idx == #records then
            table.insert(lines, apply('<indent>s << "<label>"<labelpad> << <value>;'))
        else
            table.insert(lines, apply('<indent>s << "<label>"<labelpad> << <value><valuepad> << <separator>;'))
        end
        idx = idx + 1
    end

    if G.keepindent then
        table.insert(lines, apply('<indent>// clang-format on'))
    end
    table.insert(lines, apply('<indent>return s;'))
    table.insert(lines, apply('}'))

    for _,l in ipairs(lines) do log.debug(l) end
    return lines
end

-- Generate output stream friend shift operator completion item for a class type node.
local function friend_shift_class_item(node)
    log.trace("friend_shift_class_item:", ast.details(node))
    local lines = shift_class_snippet(node, 'friend')
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

-- Generate output stream inline shift operator completion item for a class type node.
local function inline_shift_class_item(node)
    log.trace("inline_shift_class_item:", ast.details(node))
    local lines = shift_class_snippet(node, 'inline')
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

---------------------------------------------------------------------------------------------------
-- Generate output stream shift operator for an enum type node.
---------------------------------------------------------------------------------------------------
local function shift_enum_snippet(node, specifier)
    log.trace("shift_enum_snippet:", ast.details(node))

    P.specifier = specifier
    P.classname = ast.name(node)
    P.indent    = string.rep(' ', vim.lsp.util.get_effective_tabstop())

    local records = enum_labels_and_values(node)
    local maxllen, maxvlen = max_lengths(records)

    local lines = {}

    table.insert(lines, apply('<specifier> std::ostream& operator<<(std::ostream& s, <classname> o)'))
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
local function friend_shift_enum_item(node)
    log.trace("friend_shift_enum_item:", ast.details(node))
    local lines = shift_enum_snippet(node, 'friend')
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
local function inline_shift_enum_item(node)
    log.trace("inline_shift_enum_item:", ast.details(node))
    local lines = shift_enum_snippet(node, 'inline')
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

local M = {}

local function is_enum(node)
    return node and node.role == "declaration" and node.kind == "Enum"
end

local function is_class(node)
    return node and node.role == "declaration" and node.kind == "CXXRecord"
end

local enclosing_node = nil
local preceding_node = nil

--- Generator will call this method before presenting set of new candidate nodes
function M.reset()
    enclosing_node = nil
    preceding_node = nil
end

--- Generator will call this method with new candidate node
function M.visit(node, line)
    -- We can generate shift operator for enclosing class node
    if ast.encloses(node, line) and is_class(node) then
        log.debug("visit:", "Accepted enclosing node", ast.details(node))
        enclosing_node = node
    end
    -- We can generate shift operator for preceding enumeration and class nodes
    if ast.precedes(node, line) and (is_enum(node) or is_class(node)) then
        log.debug("visit:", "Accepted preceding node", ast.details(node))
        preceding_node = node
    end
end

--- Generator will call this method to check if the module can generate code
function M.available()
    return enclosing_node or preceding_node
end

-- Generate plain output stream shift operator for a class and enum nodes.
function M.completion_items()
    log.trace("completion_items:")

    local items = {}

    if is_class(preceding_node) then
        if is_class(enclosing_node) then
            table.insert(items, friend_shift_class_item(preceding_node))
        else
            table.insert(items, inline_shift_class_item(preceding_node))
        end
    end
    if is_class(enclosing_node) then
        table.insert(items, friend_shift_class_item(enclosing_node))
    end

    if is_enum(preceding_node) then
        if is_class(enclosing_node) then
            table.insert(items, friend_shift_enum_item(preceding_node))
        else
            table.insert(items, inline_shift_enum_item(preceding_node))
        end
    end

    return items
end

---------------------------------------------------------------------------------------------------
--- Initialization callback
---------------------------------------------------------------------------------------------------
function M.setup(opts)
    if opts then
        if opts.keepindent then
            G.keepindent = opts.keepindent
        end
        if opts.oss then
            if opts.oss.class then
                if opts.oss.class.separator then
                    G.class.separator = opts.oss.class.separator
                end
                if opts.oss.class.preamble then
                    G.class.preamble = opts.oss.class.preamble
                end
                if opts.oss.class.label then
                    G.class.label = opts.oss.class.label
                end
                if opts.oss.class.value then
                    G.class.value = opts.oss.class.value
                end
            end
            if opts.oss.enum then
                if opts.oss.enum.value then
                    G.enum.value = opts.oss.enum.value
                end
            end
        end
    end
end

return M
