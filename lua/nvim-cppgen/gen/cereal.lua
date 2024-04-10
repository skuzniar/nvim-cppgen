local ast = require('nvim-cppgen.ast')
local log = require('nvim-cppgen.log')

local cmp = require('cmp')

---------------------------------------------------------------------------------------------------
-- Serializarion function generator.
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

-- Create the label string for the member field. By default we use camelized name.
G.class.label = function(classname, fieldname, camelized)
    return camelized
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
                if (object) then
                    record.value = G.class.value(object .. '.' .. record.field)
                else
                    record.value = G.class.value(record.field)
                end
                table.insert(records, record)
            end
        end
    )
    return records
end

---------------------------------------------------------------------------------------------------
-- Generate serialization snippet for a class type node.
---------------------------------------------------------------------------------------------------
local function save_class_snippet(node, specifier, member)
    log.debug("save_class_snippet:", ast.details(node))

    P.specifier = specifier
    P.classname = ast.name(node)
    P.indent    = string.rep(' ', vim.lsp.util.get_effective_tabstop())

    local records = member and class_labels_and_values(node) or class_labels_and_values(node, 'o')
    local maxllen, maxvlen = max_lengths(records)

    local lines = {}

    if member then
        table.insert(lines, apply('<specifier> void save(Archive& archive) const'))
    else
        table.insert(lines, apply('<specifier> void save(Archive& archive, const <classname>& o)'))
    end
    table.insert(lines, apply('{'))
    if G.keepindent then
        table.insert(lines, apply('<indent>// clang-format off'))
    end

    table.insert(lines, apply('<indent>archive('))
    local idx = 1
    for _,r in ipairs(records) do
        P.fieldname = r.field
        P.label     = r.label
        P.value     = r.value
        P.labelpad  = string.rep(' ', maxllen - string.len(r.label))
        P.valuepad  = string.rep(' ', maxvlen - string.len(r.value))
        if idx == #records then
            table.insert(lines, apply('<indent><indent>cereal::make_nvp("<label>",<labelpad> <value>)'))
        else
            table.insert(lines, apply('<indent><indent>cereal::make_nvp("<label>",<labelpad> <value>),'))
        end
        idx = idx + 1
    end
    table.insert(lines, apply('<indent>);'))

    if G.keepindent then
        table.insert(lines, apply('<indent>// clang-format on'))
    end
    table.insert(lines, apply('}'))

    for _,l in ipairs(lines) do log.debug(l) end
    return lines
end

-- Generate serialization function snippet item for a class type node.
local function save_class_member_item(node)
    log.trace("save_class_member_item:", ast.details(node))
    local lines = save_class_snippet(node, 'template <typename Archive>', true)
    return
    {
        label            = 'save',
        kind             = cmp.lsp.CompletionItemKind.Snippet,
        insertTextMode   = 2,
        insertTextFormat = cmp.lsp.InsertTextFormat.Snippet,
        insertText       = table.concat(lines, '\n'),
        documentation    = table.concat(lines, '\n')
    }
end

local function save_class_inline_item(node)
    log.trace("save_class_inline_item:", ast.details(node))
    local lines = save_class_snippet(node, 'template <typename Archive>', false)
    return
    {
        label            = 'save',
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
    -- We can generate serialization function for enclosing class node
    if ast.encloses(node, line) and is_class(node) then
        log.debug("visit:", "Accepted enclosing node", ast.details(node))
        enclosing_node = node
    end
    -- We can generate serialization function for preceding class node
    if ast.precedes(node, line) and is_class(node) then
        log.debug("visit:", "Accepted preceding node", ast.details(node))
        preceding_node = node
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

    if is_class(enclosing_node) then
        table.insert(items, save_class_member_item(enclosing_node))
    end
    if is_class(preceding_node) then
        table.insert(items, save_class_inline_item(preceding_node))
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
        if opts.cereal then
            if opts.cereal.keepindent ~= nil then
                G.keepindent = opts.cereal.keepindent
            end
            if opts.cereal.class then
                if opts.cereal.class.label then
                    G.class.label = opts.cereal.class.label
                end
                if opts.cereal.class.value then
                    G.class.value = opts.cereal.class.value
                end
            end
            if opts.cereal.enum then
                if opts.cereal.enum.value then
                    G.enum.value = opts.cereal.enum.value
                end
            end
        end
    end
end

return M
