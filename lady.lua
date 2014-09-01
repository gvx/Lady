local pairs, ipairs, tostring, type, concat, dump, floor = pairs, ipairs, tostring, type, table.concat, string.dump, math.floor
local M = {}
local registered_classes_by_name = {}
local registered_classes_by_value = {}
local kw = {['and'] = true, ['break'] = true, ['do'] = true, ['else'] = true,
	['elseif'] = true, ['end'] = true, ['false'] = true, ['for'] = true,
	['function'] = true, ['goto'] = true, ['if'] = true, ['in'] = true,
	['local'] = true, ['nil'] = true, ['not'] = true, ['or'] = true,
	['repeat'] = true, ['return'] = true, ['then'] = true, ['true'] = true,
	['until'] = true, ['while'] = true}
local function valid_identifier(s)
	return s:match '^[_%a][_%w]*$' and not kw[s]
end

function M.register_class(c, name)
	name = name or c.name or c.__name__
	assert(type(name) == 'string', 'class must be given a string name')
	assert(valid_identifier(name), 'name must be a valid identifier')
	assert(registered_classes_by_name[name] == nil, ('class with the name %s has already been registered'):format(name))
	assert(registered_classes_by_value[c] == nil, 'class has already been registered')
	registered_classes_by_name[name] = c
	registered_classes_by_value[c] = name
	return c
end

local function getchr(c)
	return "\\" .. c:byte()
end

local function make_safe(text)
	return ("%q"):format(text):gsub('\n', 'n'):gsub("[\128-\255]", getchr)
end

local oddvals = {inf = '1/0', ['-inf'] = '-1/0', [tostring(0/0)] = '0/0'}
local function write(t, memo, rev_memo)
	local ty = type(t)
	if ty == 'number' or ty == 'boolean' or ty == 'nil' then
		t = tostring(t)
		return oddvals[t] or t
	elseif ty == 'string' then
		return make_safe(t)
	elseif ty == 'table' or ty == 'function' then
		if not memo[t] then
			local index = #rev_memo + 1
			memo[t] = index
			rev_memo[index] = t
		end
		return '_' .. memo[t]
	else
		error("Trying to serialize unsupported type " .. ty)
	end
end

local function write_key_value_pair(k, v, memo, rev_memo, name)
	if type(k) == 'string' and valid_identifier(k) then
		return (name and name .. '.' or '') .. k ..' = ' .. write(v, memo, rev_memo)
	else
		return (name or '') .. '[' .. write(k, memo, rev_memo) .. '] = ' .. write(v, memo, rev_memo)
	end
end

-- fun fact: this function is not perfect
-- it has a few false positives sometimes
-- but no false negatives, so that's good
local function is_cyclic(memo, sub, super)
	local m = memo[sub]
	local p = memo[super]
	return m and p and m < p
end

local function write_table_ex(t, memo, rev_memo, srefs, name)
	if type(t) == 'function' then
		return 'local _' .. name .. ' = loadstring ' .. make_safe(dump(t))
	end
	-- check for class
	local pretable = '{'
	local posttable = '}'
	local classkey = nil
	local classname = nil
	if registered_classes_by_value[t.class] then
		-- assume MiddleClass
		classname = registered_classes_by_value[t.class]
		classkey = 'class'
		pretable = 'setmetatable({'
		posttable = '}, ' .. classname .. '.__instanceDict)'
	elseif registered_classes_by_value[t.__baseclass] then
		-- assume SECS
		classname = registered_classes_by_value[t.__baseclass]
		classkey = '__baseclass'
		pretable = 'setmetatable({'
		posttable = '}, getmetatable(' .. classname .. '))'
	elseif registered_classes_by_value[getmetatable(t)] then
		-- assume hump.class
		classname = registered_classes_by_value[getmetatable(t)]
		pretable = 'setmetatable({'
		posttable = '}, ' .. classname .. ')'
	elseif registered_classes_by_value[t.__class__] then
		-- assume Slither
		local cls = t.__class__
		classname = registered_classes_by_value[cls]
		pretable = 'setmetatable({'
		posttable = '}, slithermt(' .. classname .. '))'
	end
	local m = {'local _', name, ' = ', pretable}
	local mi = 4
	for i = 1, #t do -- don't use ipairs here, we need the gaps
		local v = t[i]
		if v == t or is_cyclic(memo, v, t) then
			srefs[#srefs + 1] = {name, i, v}
			m[mi + 1] = 'nil, '
			mi = mi + 1
		else
			m[mi + 1] = write(v, memo, rev_memo)
			m[mi + 2] = ', '
			mi = mi + 2
		end
	end
	for k,v in pairs(t) do
		if type(k) ~= 'number' or floor(k) ~= k or k < 1 or k > #t then
			if k == classkey then
				m[mi + 1] = k
				m[mi + 2] = ' = '
				m[mi + 3] = classname
				m[mi + 4] = ', '
				mi = mi + 4
			elseif v == t or k == t or is_cyclic(memo, v, t) or is_cyclic(memo, k, t) then
				srefs[#srefs + 1] = {name, k, v}
			else
				m[mi + 1] = write_key_value_pair(k, v, memo, rev_memo)
				m[mi + 2] = ', '
				mi = mi + 2
			end
		end
	end
	m[mi > 4 and mi or mi + 1] = posttable
	return concat(m)
end

function M.save_all(savename, ...)
	local memo = {}
	local rev_memo = {...}
	for k, v in ipairs(rev_memo) do
		memo[v] = k
	end
	local srefs = {}
	local result = {}

	-- phase 1: recursively descend the table structure
	local n = 1
	while rev_memo[n] do
		result[n] = write_table_ex(rev_memo[n], memo, rev_memo, srefs, n)
		n = n + 1
	end

	-- phase 2: reverse order
	for i = 1, (n - 1)*.5 do
		local j = n - i
		result[i], result[j] = result[j], result[i]
	end

	-- phase 3: add all the tricky cyclic stuff
	for i, v in ipairs(srefs) do
		result[n] = write_key_value_pair(v[2], v[3], memo, rev_memo, '_' .. v[1])
		n = n + 1
	end

	-- phase 4: add something about returning the main tables
	local r = {'return '}
	for i = 1, select('#', ...) do
		r[i * 3 - 1] = '_'
		r[i * 3] = tostring(i)
		r[i * 3 + 1] = ', '
	end
	r[#r] = nil
	result[n] = table.concat(r)

	-- phase 5: just concatenate everything
	local contents = concat(result, '\n')
	
	-- phase 6: store contents
	love.filesystem.write(savename, contents)
end

local function slithernewindex(self, key, value)
	if self.__setattr__ then
		return self:__setattr__(key, value)
	else
		return rawset(self, key, value)
	end
end

local function slither_instance_mt(cls)
	local smt = getmetatable(cls)
	local mt = {__index = smt.__index, __newindex = slithernewindex}

	if cls.__cmp__ then
		if not smt.eq or not smt.lt then
			function smt.eq(a, b)
				return a.__cmp__(a, b) == 0
			end
			function smt.lt(a, b)
				return a.__cmp__(a, b) < 0
			end
		end
		mt.__eq = smt.eq
		mt.__lt = smt.lt
	end

	for i, v in pairs{
		__call__ = "__call", __len__ = "__len",
		__add__ = "__add", __sub__ = "__sub",
		__mul__ = "__mul", __div__ = "__div",
		__mod__ = "__mod", __pow__ = "__pow",
		__neg__ = "__unm", __concat__ = "__concat",
		__str__ = "__tostring",
		} do
		if cls[i] then mt[v] = cls[i] end
	end

	return mt
end

local load_mt = {__index = registered_classes_by_name}
function M.load_all(savename)
	local contents = love.filesystem.read(savename)
	local s = loadstring(contents)
	setfenv(s, setmetatable({setmetatable = setmetatable, getmetatable = getmetatable, slithermt = slither_instance_mt}, load_mt))
	return s()
end

return M
