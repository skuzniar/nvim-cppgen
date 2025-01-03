local ast = require('cppgen.ast')
local log = require('cppgen.log')

local cmp = require('cmp')

---------------------------------------------------------------------------------------------------
-- Class function generators.
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

-- Create the string that will be printed before class member fields are printed.
G.class.preamble = function(classname)
    return '[' .. classname .. ']='
end

-- Create the label string for the member field. By default we use camelized name.
G.class.label = function(classname, fieldname, camelized)
    return camelized .. ': '
end

-- Create the value string for the member field. By default we use field reference
G.class.value = function(fieldref, type)
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

-- Local parameters for code generation.
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

-- Collect names and values for a class type node.
local function labels_and_values(node, object)
    local records = {}
    ast.visit_children(node,
        function(n)
            if n.kind == "Field" then
                local record = {}
                record.field = ast.name(n)
                record.label = G.class.label(ast.name(node), record.field, camelize(record.field))
                record.value = G.class.value(object .. '.' .. record.field, ast.type(n))
                table.insert(records, record)
            end
            return true
        end
    )
    return records
end

-- Generate output stream shift operator for a class type node.
local function shift_snippet(node, specifier)
    log.debug("shift_snippet:", ast.details(node))

    P.specifier  = specifier
    P.attributes = G.attributes and ' ' .. G.attributes or ''
    P.classname  = ast.name(node)
    P.separator  = G.class.separator
    P.indent     = string.rep(' ', vim.lsp.util.get_effective_tabstop())

    local records = labels_and_values(node, 'o')
    local maxllen, maxvlen = max_lengths(records)

    local lines = {}

    table.insert(lines, apply('<specifier><attributes> std::ostream& operator<<(std::ostream& s, const <classname>& o)'))
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

-- Generate output stream inline shift operator completion item for a class type node.
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

local M = {}

local enclosing_node = nil
local preceding_node = nil

---------------------------------------------------------------------------------------------------
--- Generator will call this method before presenting a set of new candidate nodes.
---------------------------------------------------------------------------------------------------
function M.reset()
    enclosing_node = nil
    preceding_node = nil
end

---------------------------------------------------------------------------------------------------
--- Generator will call this method with a node and a cursor line location.
---------------------------------------------------------------------------------------------------
function M.visit(node, line)
    -- We can generate shift operator for enclosing class node
    if ast.encloses(node, line) and ast.is_class(node) then
        log.debug("visit:", "Accepted enclosing node", ast.details(node))
        enclosing_node = node
    end
    -- We can generate shift operator for preceding enumeration and class nodes
    if ast.precedes(node, line) and (ast.is_enum(node) or ast.is_class(node)) then
        log.debug("visit:", "Accepted preceding node", ast.details(node))
        preceding_node = node
    end
end

---------------------------------------------------------------------------------------------------
--- Generator will call this method to check if the module can generate code.
---------------------------------------------------------------------------------------------------
function M.available()
    return enclosing_node ~= nil or preceding_node ~= nil
end

---------------------------------------------------------------------------------------------------
-- Generate plain output stream shift operator for a class and enum nodes.
---------------------------------------------------------------------------------------------------
function M.generate()
    log.trace("generate:", ast.details(preceding_node), ast.details(enclosing_node))

    local items = {}

    if ast.is_class(preceding_node) then
        if ast.is_class(enclosing_node) then
            table.insert(items, friend_shift_item(preceding_node))
        else
            table.insert(items, inline_shift_item(preceding_node))
        end
    end
    if ast.is_class(enclosing_node) then
        table.insert(items, friend_shift_item(enclosing_node))
    end

    return items
end

---------------------------------------------------------------------------------------------------
--- Status callback
---------------------------------------------------------------------------------------------------
function M.status()
    return {
        { "inline",  "Generate class output stream shift operator" },
        { "friend",  "Generate class output stream shift operator" }
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
        if opts.class then
            if opts.class.keepindent ~= nil then
                G.keepindent = opts.class.keepindent
            end
            if opts.class.attributes ~= nil then
                G.attributes = opts.class.attributes
            end
            if opts.class.separator then
                G.class.separator = opts.class.separator
            end
            if opts.class.preamble then
                G.class.preamble = opts.class.preamble
            end
            if opts.class.label then
                G.class.label = opts.class.label
            end
            if opts.class.value then
                G.class.value = opts.class.value
            end
        end
    end
end

return M
