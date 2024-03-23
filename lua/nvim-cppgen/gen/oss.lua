local ast = require('nvim-cppgen.ast')
local cfg = require('nvim-cppgen.cfg')
local log = require('nvim-cppgen.log')

local cmp = require('cmp')

---------------------------------------------------------------------------------------------------
-- Output stream shift operators generator.
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Parameters
---------------------------------------------------------------------------------------------------
local P = {}

P.droppfix = false
P.camelize = false
P.indt     = '   '
P.equalsgn = ': '
P.fieldsep = "' '"

local function capitalize(s)
    return (string.gsub(s, '^%l', string.upper))
end

local function camelize(s)
    return (string.gsub(s, '%W*(%w+)', capitalize))
end

local function label(name)
    if P.droppfix then
        name = string.gsub(name, '^%a_', '')
    end
    if P.camelize then
        name = camelize(name)
    end

    return name
end

-- Calculate the longest length of labels and values
local function maxlens(records)
    local max_lab_len = 0
    local max_val_len = 0

    for _,r in ipairs(records) do
        max_lab_len = math.max(max_lab_len, string.len(r.label))
        max_val_len = math.max(max_val_len, string.len(r.value))
    end
    return max_lab_len, max_val_len
end

-- Apply global parameters to the format string 
local function apply(format)
    local lpad = string.rep(' ', P.llen - string.len(P.labl))
    local vpad = string.rep(' ', P.vlen - string.len(P.valu))

    local result  = format

    result = string.gsub(result, "<spec>", P.spec or '')
    result = string.gsub(result, "<name>", P.name)
    result = string.gsub(result, "<labl>", P.labl)
    result = string.gsub(result, "<valu>", P.valu)
    result = string.gsub(result, "<indt>", P.indt)
    result = string.gsub(result, "<lpad>", lpad)
    result = string.gsub(result, "<vpad>", vpad)
    result = string.gsub(result, "<eqls>", P.equalsgn)
    result = string.gsub(result, "<fsep>", P.fieldsep)

    return result;
end

-- Collect names and values for a class type node.
local function class_labels_and_values(node)
    local records = {}
    ast.visit_children(node,
        function(n)
            if n.kind == "Field" then
                local record = {}
                record.label = label(ast.name(n))
                record.value = ast.name(n)
                table.insert(records, record)
            end
        end
    )
    return records
end

-- Generate output stream shift operator for a class type node.
local function shift_class_impl(node)
    log.debug("shift_class_impl:", ast.details(node))

    P.name = ast.name(node)
    P.labl = ''
    P.valu = ''

    local records  = class_labels_and_values(node)
    P.llen, P.vlen = maxlens(records)

    local lines = {}

    table.insert(lines, apply('<spec> std::ostream& operator<<(std::ostream& s, const <name>& o)'))
    table.insert(lines, apply('{'))
    if P.keepindt then
        table.insert(lines, apply('<indt>// clang-format off'))
    end

    if P.printcname then
        table.insert(lines, apply([[<indt>s << ]] .. P.printcname .. [[;]]))
    end

    local idx = 1
    for _,r in ipairs(records) do
        P.labl = r.label
        P.valu = r.value
        if idx == #records then
            table.insert(lines, apply([[<indt>s << "<labl><eqls>"<lpad> << o.<valu>;]]))
        else
            table.insert(lines, apply([[<indt>s << "<labl><eqls>"<lpad> << o.<valu><vpad> << <fsep>;]]))
        end
        idx = idx + 1
    end

    if P.keepindt then
        table.insert(lines, apply('<indt>// clang-format on'))
    end
    table.insert(lines, apply('<indt>return s;'))
    table.insert(lines, apply('}'))

    for _,l in ipairs(lines) do log.debug(l) end

    return table.concat(lines,"\n")
end

-- Generate output stream friend shift operator snippet for a class type node.
local function friend_shift_class_snippet(node)
    log.trace("friend_shift_class_snippet:", ast.details(node))
    P.spec = 'friend'
    return shift_class_impl(node)
end

-- Generate output stream inline shift operator snippet for a class type node.
local function inline_shift_class_snippet(node)
    log.trace("inline_shift_class_snippet:", ast.details(node))
    P.spec = 'inline'
    return shift_class_impl(node)
end

-- Generate output stream friend shift operator completion item for a class type node.
local function friend_shift_class_item(node)
    log.trace("friend_shift_class_item:", ast.details(node))
    return
    {
        label            = 'friend',
        kind             = cmp.lsp.CompletionItemKind.Snippet,
        insertTextMode   = 2,
        insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
        insertText       = friend_shift_class_snippet(node)
    }
end

-- Generate output stream inline shift operator completion item for a class type node.
local function inline_shift_class_item(node)
    log.trace("inline_shift_class_item:", ast.details(node))
    return
    {
        label            = 'inline',
        kind             = cmp.lsp.CompletionItemKind.Snippet,
        insertTextMode   = 2,
        insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
        insertText       = inline_shift_class_snippet(node)
    }
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
                local lit = integral_literal(n)
                if (lit) then
                    record.value = '"' .. lit .. '(' .. ast.name(n) .. ')' .. '"'
                else
                    record.value = '"' .. ast.name(n) .. '"'
                end

                table.insert(records, record)
            end
        end
    )
    return records
end

-- Generate output stream shift operator for an enum type node.
local function shift_enum_impl(node)
    log.trace("shift_enum_impl:", ast.details(node))

    P.name = ast.name(node)
    P.labl = ''
    P.valu = ''

    local records  = enum_labels_and_values(node)
    P.llen, P.vlen = maxlens(records)

    local lines = {}

    table.insert(lines, apply('<spec> std::ostream& operator<<(std::ostream& s, <name> o)'))
    table.insert(lines, apply('{'))
    table.insert(lines, apply('<indt>switch(o)'))
    table.insert(lines, apply('<indt>{'))
    if P.keepindt then
        table.insert(lines, apply('<indt><indt>// clang-format off'))
    end

    for _,r in ipairs(records) do
        P.labl = r.label
        P.valu = r.value
        table.insert(lines, apply('<indt><indt>case <labl>:<lpad> s << <valu>;<vpad> break;'))
    end

    if P.keepindt then
        table.insert(lines, apply('<indt><indt>// clang-format on'))
    end
    table.insert(lines, apply('<indt>};'))

    table.insert(lines, apply('<indt>return s;'))
    table.insert(lines, apply('}'))

    for _,l in ipairs(lines) do log.debug(l) end

    return table.concat(lines,"\n")
end

-- Generate output stream friend shift operator snippet for an enum type node.
local function friend_shift_enum_snippet(node)
    log.trace("friend_shift_enum_snippet:", ast.details(node))
    P.spec = 'friend'
    return shift_enum_impl(node)
end

-- Generate output stream inline shift operator snippet for an enum type node.
local function inline_shift_enum_snippet(node)
    log.trace("inline_shift_enum_snippet:", ast.details(node))
    P.spec = 'inline'
    return shift_enum_impl(node)
end

-- Generate output stream friend shift operator completion item for an enum type node.
local function friend_shift_enum_item(node)
    log.trace("friend_shift_enum_item:", ast.details(node))
    return
    {
        label            = 'friend',
        kind             = cmp.lsp.CompletionItemKind.Snippet,
        insertTextMode   = 2,
        insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
        insertText       = friend_shift_enum_snippet(node)
    }
end

-- Generate output stream inline shift operator completion item for an enum type node.
local function inline_shift_enum_item(node)
    log.trace("inline_shift_enum_item:", ast.details(node))
    return
    {
        label            = 'inline',
        kind             = cmp.lsp.CompletionItemKind.Snippet,
        insertTextMode   = 2,
        insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
        insertText       = inline_shift_enum_snippet(node)
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
        log.debug("visit:", "Acepted enclosing node", ast.details(node))
        enclosing_node = node
    end
    -- We can generate shift operator for preceding enumeration and class nodes
    if ast.precedes(node, line) and (is_enum(node) or is_class(node)) then
        log.debug("visit:", "Acepted preceding node", ast.details(node))
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

    P.droppfix = cfg.options.oss and cfg.options.oss.drop_prefix
    P.camelize = cfg.options.oss and cfg.options.oss.camelize
    P.keepindt = cfg.options.oss and cfg.options.oss.keep_indentation
    if cfg.options.oss and cfg.options.oss.indentation then
        P.indt = cfg.options.oss.indentation
    end
    if cfg.options.oss and cfg.options.oss.equal_sign then
        P.equalsgn = cfg.options.oss.equal_sign
    end
    if cfg.options.oss and cfg.options.oss.field_separator then
        P.fieldsep = cfg.options.oss.field_separator
    end
    if cfg.options.oss and cfg.options.oss.print_class_name then
        P.printcname = cfg.options.oss.print_class_name
    end

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

return M
