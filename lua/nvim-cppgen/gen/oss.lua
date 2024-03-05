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

-- Calculate the longest length of the childe's label and name
local function maxlen(node)
    local max_lab_len = 0
    local max_nam_len = 0

    ast.visit_children(node,
        function(n)
            if n.kind == "EnumConstant" or n.kind == "Field" then
                max_lab_len = math.max(max_lab_len, string.len(label(ast.name(n))))
                max_nam_len = math.max(max_nam_len, string.len(ast.name(n)))
            end
        end
    )
    return max_lab_len, max_nam_len
end

-- Apply node object to the format string 
local function apply(format, node)
    local name = ast.name(node)
    local labl = label(ast.name(node))
    local lpad = string.rep(' ', P.llen - string.len(labl))
    local npad = string.rep(' ', P.nlen - string.len(name))
    local spec = P.spec or ''

    local result  = format

    result = string.gsub(result, "<spec>", spec)
    result = string.gsub(result, "<name>", name)
    result = string.gsub(result, "<labl>", labl)
    result = string.gsub(result, "<indt>", P.indt)
    result = string.gsub(result, "<lpad>", lpad)
    result = string.gsub(result, "<npad>", npad)
    result = string.gsub(result, "<eqls>", P.equalsgn)
    result = string.gsub(result, "<fsep>", P.fieldsep)
    return result;
end

-- Generate output stream shift operator for a class type node.
local function shift_class_impl(node)
    log.debug("shift_class_impl:", ast.details(node))
    P.llen, P.nlen = maxlen(node)

    local lines = {}

    table.insert(lines, apply('<spec> std::ostream& operator<<(std::ostream& s, const <name>& o)', node))
    table.insert(lines, apply('{', node))
    if P.keepindt then
        table.insert(lines, apply('<indt>// clang-format off', node))
    end

    local cnt = ast.count_children(node,
        function(n)
            return n.kind == "Field"
        end
    )

    if P.printcname then
        table.insert(lines, apply([[<indt>s << ]] .. P.printcname .. [[;]], node))
    end

    local idx = 1
    ast.visit_children(node,
        function(n)
            if n.kind == "Field" then
                if idx == cnt then
                    table.insert(lines, apply([[<indt>s << "<labl><eqls>"<lpad> << o.<name>;]], n))
                else
                    table.insert(lines, apply([[<indt>s << "<labl><eqls>"<lpad> << o.<name><npad> << <fsep>;]], n))
                end
                idx = idx + 1
            end
        end
    )

    if P.keepindt then
        table.insert(lines, apply('<indt>// clang-format on', node))
    end
    table.insert(lines, apply('<indt>return s;', node))
    table.insert(lines, apply('}', node))

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

-- Generate output stream shift operator for an enum type node.
local function shift_enum_impl(node)
    log.trace("shift_enum_impl:", ast.details(node))
    P.llen, P.nlen = maxlen(node)

    local lines = {}

    table.insert(lines, apply('<spec> std::ostream& operator<<(std::ostream& s, <name> o)', node))
    table.insert(lines, apply('{', node))
    table.insert(lines, apply('<indt>switch(o)', node))
    table.insert(lines, apply('<indt>{', node))
    if P.keepindt then
        table.insert(lines, apply('<indt><indt>// clang-format off', node))
    end

    ast.visit_children(node,
        function(n)
            if n.kind == "EnumConstant" then
                table.insert(lines, apply('<indt><indt>case ' .. ast.name(node) .. [[::<name>:<npad> s << "<name>";<npad> break;]], n))
            end
        end
    )

    if P.keepindt then
        table.insert(lines, apply('<indt><indt>// clang-format on', node))
    end
    table.insert(lines, apply('<indt>};', node))

    table.insert(lines, apply('<indt>return s;', node))
    table.insert(lines, apply('}', node))

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

local function isEnum(node)
    return node and node.role == "declaration" and (node.kind == "Enum" or node.kind == "Field")
end

local function isClass(node)
    return node and node.role == "declaration" and (node.kind == "CXXRecord" or node.kind == "Field")
end

--- Returns true if the node is of interest to us
function M.interesting(preceding, enclosing)
    -- We can generate shift operator for preceding enumeration node and both preceding and enclosing class nodes
    if isEnum(preceding) or isClass(preceding) or isClass(enclosing) then
        return true
    end
    return false
end

-- Generate plain output stream shift operator for a class and enum nodes.
function M.completion_items(preceding, enclosing)
    log.trace("completion_items:", ast.details(preceding), ast.details(enclosing))

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

    if isClass(preceding) then
        if isClass(enclosing) then
            table.insert(items, friend_shift_class_item(preceding))
        else
            table.insert(items, inline_shift_class_item(preceding))
        end
    end
    if isClass(enclosing) then
        table.insert(items, friend_shift_class_item(enclosing))
    end

    if isEnum(preceding) then
        if isClass(enclosing) then
            table.insert(items, friend_shift_enum_item(preceding))
        else
            table.insert(items, inline_shift_enum_item(preceding))
        end
    end

    return items
end

return M
