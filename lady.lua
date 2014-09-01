local pairs, ipairs, tostring, type, getmetatable, setmetatable, concat, sort, dump, floor = pairs, ipairs, tostring, type, getmetatable, setmetatable, table.concat, table.sort, string.dump, math.floor
local M = {}
local registered_things_by_name = {}
local registered_things_by_value = {}
local kw = {['and'] = true, ['break'] = true, ['do'] = true, ['else'] = true,
	['elseif'] = true, ['end'] = true, ['false'] = true, ['for'] = true,
	['function'] = true, ['goto'] = true, ['if'] = true, ['in'] = true,
	['local'] = true, ['nil'] = true, ['not'] = true, ['or'] = true,
	['repeat'] = true, ['return'] = true, ['then'] = true, ['true'] = true,
	['until'] = true, ['while'] = true}
local function valid_identifier(s)
	return s:match '^[_%a][_%w]*$' and not kw[s]
end
local function valid_classname(s)
	return s:match '^%a[_%w]*$' and not kw[s]
end


function M.register_class(c, name)
	name = name or c.__name__ or c.name
	assert(type(name) == 'string', 'class must be given a string name')
	assert(valid_classname(name), 'name must be a valid identifier that doesn\'t start with an underscore')
	assert(registered_things_by_name[name] == nil, ('class with the name %s has already been registered'):format(name))
	assert(registered_things_by_value[c] == nil, 'class has already been registered')
	registered_things_by_name[name] = c
	registered_things_by_value[c] = name
	return c
end

function M.register_resource(r, name)
	assert(type(name) == 'string', 'resource must be given a string name')
	assert(valid_identifier(name), 'name must be a valid identifier')
	assert(registered_things_by_name['_R' .. name] == nil, ('resource with the name %s has already been registered'):format(name))
	assert(registered_things_by_value[r] == nil, 'resource has already been registered')
	name = '_R' .. name
	registered_things_by_name[name] = r
	registered_things_by_value[r] = name
	return r
end

function M.register_resource_table(rt, tname)
	tname = tname and tname .. '_' or ''
	for k, v in pairs(rt) do
		M.register_resource(v, tname .. k)
	end
	return rt
end

local function getchr(c)
	return "\\" .. c:byte()
end

local function make_safe(text)
	return ("%q"):format(text):gsub('\n', 'n'):gsub("[\128-\255]", getchr)
end

local oddvals = {inf = '1/0', ['-inf'] = '-1/0', [tostring(0/0)] = '0/0'}
local userdata_constructor = {}
local function write(t, memo, rev_memo)
	local ty = type(t)
	if ty == 'number' or ty == 'boolean' or ty == 'nil' then
		t = tostring(t)
		return oddvals[t] or t
	elseif ty == 'string' then
		return make_safe(t)
	elseif ty == 'table' or ty == 'function' or (ty == 'userdata' and userdata_constructor[t:type()]) then
		if not memo[t] then
			local index = #rev_memo + 1
			memo[t] = index
			rev_memo[index] = t
		end
		return '_' .. memo[t]
	elseif ty == 'userdata' then
		if registered_things_by_value[t] then
			return registered_things_by_value[t]
		end
		error("Trying to serialize unregistered userdata " .. t:type())
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

function userdata_constructor:World(srefs, memo, rev_memo)
	local s = memo[self]
	if self:getCallbacks() ~= nil then
		srefs[#srefs + 1] = {s, ':', 'setCallbacks', self:getCallbacks()}
	end
	if self:getContactFilter() ~= nil then
		srefs[#srefs + 1] = {s, ':', 'setContactFilter', self:getContactFilter()}
	end
	local x, y = self:getGravity( )
	return x, y, self:isSleepingAllowed()
end
function userdata_constructor:Body(srefs, memo, rev_memo)
	local s = memo[self]
	srefs[#srefs + 1] = {s, ':', 'setSleepingAllowed', self:isSleepingAllowed()}
	srefs[#srefs + 1] = {s, ':', 'setAngle', self:getAngle()}
	srefs[#srefs + 1] = {s, ':', 'setAngularDamping', self:getAngularDamping()}
	srefs[#srefs + 1] = {s, ':', 'setAngularVelocity', self:getAngularVelocity()}
	srefs[#srefs + 1] = {s, ':', 'setGravityScale', self:getGravityScale()}
	srefs[#srefs + 1] = {s, ':', 'setInertia', self:getInertia()}
	srefs[#srefs + 1] = {s, ':', 'setLinearDamping', self:getLinearDamping()}
	srefs[#srefs + 1] = {s, ':', 'setLinearVelocity', self:getLinearVelocity()}
	srefs[#srefs + 1] = {s, ':', 'setMass', self:getMass()}
	srefs[#srefs + 1] = {s, ':', 'setAwake', self:isAwake()}
	srefs[#srefs + 1] = {s, ':', 'setBullet', self:isBullet()}
	local x, y = self:getPosition()
	return self.getWorld and self:getWorld() or rev_memo[1], x, y, self:getType()
end
function userdata_constructor:ChainShape(srefs)
	return false, self:getPoints()
end
function userdata_constructor:CircleShape(srefs)
	local x, y = self:getPoint()
	return x, y, self:getRadius()
end
function userdata_constructor:EdgeShape(srefs)
	return self:getPoints()
end
function userdata_constructor:PolygonShape(srefs)
	return self:getPoints()
end
function userdata_constructor:Fixture(srefs, memo, rev_memo)
	local s = memo[self]
	--the ones commented out are just replicating the data from get/setFilterData
	--srefs[#srefs + 1] = {s, ':', 'setCategory', self:getCategory()}
	srefs[#srefs + 1] = {s, ':', 'setDensity', self:getDensity()}
	srefs[#srefs + 1] = {s, ':', 'setFilterData', self:getFilterData()}
	srefs[#srefs + 1] = {s, ':', 'setFriction', self:getFriction()}
	--srefs[#srefs + 1] = {s, ':', 'setGroupIndex', self:getGroupIndex()}
	--srefs[#srefs + 1] = {s, ':', 'setMask', self:getMask()}
	srefs[#srefs + 1] = {s, ':', 'setRestitution', self:getRestitution()}
	srefs[#srefs + 1] = {s, ':', 'setSensor', self:isSensor()}
	if self:getUserData() ~= nil then
		srefs[#srefs + 1] = {s, ':', 'setUserData', self:getUserData()}
	end
	return self:getBody(), self:getShape(), self:getDensity()
end

local function write_table_ex(t, memo, rev_memo, srefs, name)
	if type(t) == 'function' then
		return 'local _' .. name .. ' = _L ' .. make_safe(dump(t))
	elseif type(t) == 'userdata' then
		local m = {'local _' .. name .. ' = love.physics.new' .. t:type() .. '('}
		for i, arg in ipairs{userdata_constructor[t:type()](t, srefs, memo, rev_memo)} do
			m[#m + 1] = write(arg, memo, rev_memo)
			m[#m + 1] = ', '
		end
		m[#m > 1 and #m or #m + 1] = ')'
		return concat(m)
	end
	-- check for class
	local pretable = '{'
	local posttable = '}'
	local classkey = nil
	local classname = nil
	if registered_things_by_value[t.class] then
		-- assume MiddleClass
		classname = registered_things_by_value[t.class]
		classkey = 'class'
		pretable = '_S({'
		posttable = '}, ' .. classname .. '.__instanceDict)'
	elseif registered_things_by_value[t.__baseclass] then
		-- assume SECS
		classname = registered_things_by_value[t.__baseclass]
		classkey = '__baseclass'
		pretable = '_S({'
		posttable = '}, _M(' .. classname .. '))'
	elseif registered_things_by_value[getmetatable(t)] then
		-- assume hump.class
		classname = registered_things_by_value[getmetatable(t)]
		pretable = '_S({'
		posttable = '}, ' .. classname .. ')'
	elseif registered_things_by_value[t.__class__] then
		-- assume Slither
		classname = registered_things_by_value[t.__class__]
		pretable = '_S({'
		posttable = '}, _I(' .. classname .. '))'
	end
	local m = {'local _', name, ' = ', pretable}
	local mi = 4
	for i = 1, #t do -- don't use ipairs here, we need the gaps
		local v = t[i]
		if v == t or is_cyclic(memo, v, t) then
			srefs[#srefs + 1] = {name, '.', i, v}
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
				srefs[#srefs + 1] = {name, '.', k, v}
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

local function orderobjects(a, b)
	if type(a[2]) == 'userdata' then
		if type(b[2]) ~= 'userdata' then
			return true
		end
		if a[2]:typeOf('World') then
			return true
		end
		if b[2]:typeOf('World') then
			return false
		end
		if a[2]:typeOf('Fixture') then
			return false
		end
		if b[2]:typeOf('Fixture') then
			return true
		end
	elseif type(b[2]) == 'userdata' then
		return false
	end
	return b[1] < a[1]
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
		result[n] = {n, rev_memo[n], write_table_ex(rev_memo[n], memo, rev_memo, srefs, n)}
		n = n + 1
	end

	-- phase 2: the right order
	sort(result, orderobjects)
	for i = 1, #result do
		result[i] = result[i][3]
	end

	-- phase 3: add all the tricky cyclic stuff
	for i, v in ipairs(srefs) do
		if v[2] == '.' then
			result[n] = write_key_value_pair(v[3], v[4], memo, rev_memo, '_' .. v[1])
		else
			local tmp = {'_', v[1], ':', v[3], '('}
			for i = 4, #v do
				tmp[i * 2 - 2] = write(v[i], memo, rev_memo)
				tmp[i * 2 - 1] = ', '
			end
			tmp[#tmp] = ')'
			result[n] = concat(tmp)
		end
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
	result[n] = concat(r)

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

local load_mt = {__index = registered_things_by_name}
function M.load_all(savename)
	local contents = love.filesystem.read(savename)
	local s = loadstring(contents)
	setfenv(s, setmetatable({_L = loadstring, _S = setmetatable, _M = getmetatable, _I = slither_instance_mt, love = love}, load_mt))
	return s()
end

return M
